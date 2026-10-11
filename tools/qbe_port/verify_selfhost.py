#!/usr/bin/env python3
"""Verify the LSL frontend and QBE 1.3 port using only the native LSL backend.

C QBE is an external bootstrap/oracle, never invoked by these measured builds.
Keep logs and partial results on failures; terminate the complete process group
on timeout, including compiler subprocesses.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import resource
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / 'build/qbe-port-tools/native-selfhost'


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=ROOT/'build/qbe-port-tools/compiler-select')
    parser.add_argument('--backend', type=Path, default=ROOT/'build/qbe-port-tools/qbe-lsl')
    parser.add_argument('--timeout', type=float, default=180)
    parser.add_argument('--memory-gib', type=float, default=4,
                        help='virtual address-space limit for each complete build')
    args = parser.parse_args()
    if args.timeout <= 0 or args.memory_gib <= 0:
        parser.error('timeout and memory limit must be positive')
    BUILD.mkdir(parents=True, exist_ok=True)
    report = {'platform': platform.platform(), 'upstream_version': '1.3',
              'builds': [], 'fixed_points': {}, 'complete': False,
              'memory_limit_gib': args.memory_gib}
    sources = sorted((ROOT/'compiler/pure').rglob('*.lsl'))
    source_snapshot = {str(p.relative_to(ROOT)): digest(p) for p in sources}
    report['source_sha256'] = source_snapshot
    report_path = BUILD / 'verification.json'

    def save():
        report_path.write_text(json.dumps(report, indent=2)+'\n')

    def compile_source(compiler, backend, source, output):
        cmd = [str(compiler), source, str(output), str(backend)]
        record = {'command': cmd, 'compiler_sha256': digest(compiler),
                  'backend_sha256': digest(backend), 'source': source,
                  'source_sha256': digest(ROOT/source),
                  'runtime_sha256': digest(ROOT/'build/qbe/runtime.o')}
        report['builds'].append(record)
        save()
        start = time.monotonic()
        def limit_memory():
            limit = int(args.memory_gib * 1024**3)
            resource.setrlimit(resource.RLIMIT_AS, (limit, limit))
        with output.with_suffix('.log').open('wb') as log:
            process = subprocess.Popen(cmd, cwd=ROOT, stdout=log,
                                       stderr=subprocess.STDOUT, start_new_session=True,
                                       preexec_fn=limit_memory)
            try:
                process.wait(timeout=args.timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                record['timed_out'] = True
        record['seconds'] = time.monotonic()-start
        record['returncode'] = process.returncode
        record['under_60_seconds'] = record['seconds'] < 60
        if process.returncode == 0:
            record['output_sha256'] = digest(output)
        save()
        print(f'{output.name}: {record["seconds"]:.3f}s, exit {process.returncode}', flush=True)
        if process.returncode:
            raise RuntimeError(f'build failed: {output.with_suffix(".log")}')
        if digest(ROOT/'build/qbe/runtime.o') != record['runtime_sha256']:
            raise RuntimeError('runtime changed during measured build')

    compiler = args.compiler.resolve()
    backend = args.backend.resolve()
    try:
        frontends, backends = [], []
        report['generation_seconds'] = []
        # Advance both halves together: generation three's frontend must use
        # the newly self-built backend, not the immutable bootstrap backend.
        for stage in (2, 3, 4):
            output = BUILD / f'frontend-stage{stage}'
            compile_source(compiler, backend, 'compiler/pure/lslc_qbe.lsl', output)
            compiler = output
            frontends.append(output)
            output = BUILD / f'qbe-stage{stage}'
            compile_source(compiler, backend, 'compiler/pure/qbe_port/qbe_backend.lsl', output)
            backend = output
            backends.append(output)
            report['generation_seconds'].append(sum(b['seconds'] for b in report['builds'][-2:]))
            if len(frontends) >= 2:
                report['fixed_points']['frontend'] = digest(frontends[-2]) == digest(frontends[-1])
                report['fixed_points']['backend'] = digest(backends[-2]) == digest(backends[-1])
                if all(report['fixed_points'].values()):
                    break
        report['bootstrap_convergence_generations'] = len(frontends)
        report['sources_unchanged'] = source_snapshot == {
            str(p.relative_to(ROOT)): digest(p) for p in sources}
        report['whole_generation_under_60_seconds'] = report['generation_seconds'][-1] < 60
        report['complete'] = all(report['fixed_points'].values()) and all(
            b['under_60_seconds'] for b in report['builds']) and report['sources_unchanged'] and report['whole_generation_under_60_seconds']
    except Exception as exc:
        report['error'] = str(exc)
    save()
    print(report_path, flush=True)
    return 0 if report['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
