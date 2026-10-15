#!/usr/bin/env python3
"""Build the release tools for another Linux architecture.

The released x86_64 compiler (compiler/lslc with compiler/pure/luxir, after
build_release.py) translates the same sources as build_release.py with
--target, so the tools for linux-arm64 and linux-riscv64 come from the
compiler that passed the fixed points. The output directory receives bin/
with lslc, luxir, lsl, lsl-install, lsl-configure and lsl-test.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
TARGETS = ('linux-arm64', 'linux-riscv64')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', required=True, choices=TARGETS)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--compiler', type=Path, default=ROOT / 'compiler/lslc')
    parser.add_argument('--backend', type=Path, default=ROOT / 'compiler/pure/luxir')
    args = parser.parse_args()
    lock = json.loads((ROOT / 'release.json').read_text())
    backend_source = Path(lock['backend']['directory']) / 'lsl/luxir.lsl'
    if not (ROOT / backend_source).is_file():
        parser.error('run tools/release/prepare_sources.py first')
    bin_directory = args.output.resolve() / 'bin'
    bin_directory.mkdir(parents=True, exist_ok=True)
    tools = [('lslc', [], 'compiler/pure/lslc_qbe.lsl'),
             ('luxir', [], str(backend_source)),
             ('lsl', ['--unsafe'], 'compiler/pure/cli.lsl'),
             ('lsl-install', ['--unsafe'], 'compiler/pure/install.lsl'),
             ('lsl-configure', ['--unsafe'], 'stdlib/configure.lsl'),
             ('lsl-test', ['--unsafe'], 'tests/test_runner.lsl')]
    report = {'target': args.target, 'compiler_sha256': digest(args.compiler.resolve()),
              'backend_sha256': digest(args.backend.resolve()), 'artifacts': {}}
    for name, flags, source in tools:
        output = bin_directory / name
        command = [str(args.compiler.resolve()), *flags, '--target', args.target, source,
                   str(output), str(args.backend.resolve())]
        process = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=600)
        if process.returncode:
            raise SystemExit(f'{name}: ' + (process.stderr or process.stdout).decode(errors='replace'))
        output.chmod(0o755)
        report['artifacts'][name] = digest(output)
        print(name, report['artifacts'][name], flush=True)
    (args.output.resolve() / 'build.json').write_text(json.dumps(report, indent=2) + '\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
