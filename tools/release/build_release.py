#!/usr/bin/env python3
"""Rebuild native Linux x86_64 release tools and prove both fixed points.

Run prepare_sources.py first. The committed LSL compiler and native LuxIR are
bootstrap seeds; this build never executes the reference C implementation.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seed', type=Path, default=ROOT / 'compiler/lslc')
    parser.add_argument('--build-directory', type=Path, default=ROOT / 'build/release-build')
    args = parser.parse_args()
    build = args.build_directory.resolve()
    build.mkdir(parents=True, exist_ok=True)
    lock = json.loads((ROOT / 'release.json').read_text())
    backend_source = Path(lock['backend']['directory']) / 'lsl/luxir.lsl'
    backend = ROOT / 'compiler/pure/luxir'
    if not (ROOT / backend_source).is_file():
        parser.error('run tools/release/prepare_sources.py first')
    seed = build / 'bootstrap-frontend'
    seed_backend = build / 'bootstrap-backend'
    shutil.copy2(args.seed.resolve(), seed)
    shutil.copy2(backend, seed_backend)
    report = {'complete': False, 'commands': [], 'bootstrap': {
        'frontend_sha256': digest(seed), 'backend_sha256': digest(seed_backend)}}
    report_path = build / 'build.json'

    def save():
        report_path.write_text(json.dumps(report, indent=2) + '\n')

    def run(command):
        def limit():
            resource.setrlimit(resource.RLIMIT_AS, (4 * 1024**3, 4 * 1024**3))
        command = list(map(str, command))
        start = time.monotonic()
        process = subprocess.run(command, cwd=ROOT, capture_output=True,
                                 timeout=180, preexec_fn=limit)
        row = {'command': command, 'seconds': time.monotonic() - start,
               'returncode': process.returncode,
               'stdout': process.stdout.decode(errors='replace'),
               'stderr': process.stderr.decode(errors='replace')}
        report['commands'].append(row)
        save()
        print(command[1], process.returncode, round(row['seconds'], 3), flush=True)
        if process.returncode:
            raise RuntimeError(row['stderr'] or row['stdout'])

    try:
        f2, f3, b2, b3 = (build / name for name in ('frontend2', 'frontend3', 'luxir2', 'luxir3'))
        run([seed, 'compiler/pure/lslc_qbe.lsl', f2, seed_backend])
        run([f2, 'compiler/pure/lslc_qbe.lsl', f3, seed_backend])
        if digest(f2) != digest(f3):
            raise RuntimeError('frontend fixed point differs')
        run([f3, backend_source, b2, seed_backend])
        run([f3, backend_source, b3, b2])
        if digest(b2) != digest(b3):
            raise RuntimeError('backend fixed point differs')
        outputs = {'compiler/pure/lslc-qbe': f3, 'compiler/lslc': f3,
                   'compiler/pure/luxir': b3}
        for source, destination in (
            ('compiler/pure/lslc_direct.lsl', 'compiler/pure/lslc-direct'),
            ('compiler/pure/cli.lsl', 'compiler/pure/lsl-cli'),
            ('compiler/pure/install.lsl', 'compiler/pure/lsl-install'),
            ('stdlib/configure.lsl', 'compiler/pure/lsl-configure'),
            ('tests/test_runner.lsl', 'tests/lsl-test')):
            output = build / Path(destination).name
            run([f3, '--unsafe', source, output, b3])
            outputs[destination] = output
        outputs['lsl'] = outputs['compiler/pure/lsl-cli']
        for name, source in outputs.items():
            destination = ROOT / name
            temporary = destination.with_name(destination.name + '.release-tmp')
            shutil.copy2(source, temporary)
            temporary.chmod(0o755)
            os.replace(temporary, destination)
        # Development compatibility paths; installed tools resolve their sibling backend.
        compatibility = ROOT / 'build/luxir/luxir'
        compatibility.parent.mkdir(parents=True, exist_ok=True)
        if compatibility.is_symlink():
            compatibility.unlink()
        shutil.copy2(backend, compatibility)
        report.update(complete=True, frontend_fixed_point=True, backend_fixed_point=True,
                      artifacts={name: digest(ROOT / name) for name in outputs})
        save()
        return 0
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        report['error'] = str(error)
        save()
        raise


if __name__ == '__main__':
    raise SystemExit(main())
