#!/usr/bin/env python3
"""Compare backend wall time on identical IL, requiring exact assembly output.

This measures backend execution only, excluding LSL source parsing and linking.
Use full frontend/backend self-host IL as workloads, not just tiny smoke tests.
Runs alternate order to reduce cache/load bias; reports medians and all samples.
"""
import argparse
import hashlib
import json
import platform
from pathlib import Path
import statistics
import subprocess
import tempfile
import time


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backend', type=Path, required=True)
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--repeats', type=int, default=3)
    parser.add_argument('--timeout', type=float, default=180)
    parser.add_argument('--max-ratio', type=float, default=1.1)
    parser.add_argument('inputs', type=Path, nargs='+')
    args = parser.parse_args()
    if args.repeats < 1:
        parser.error('--repeats must be positive')
    binaries = {'reference': args.reference.resolve(), 'backend': args.backend.resolve()}
    report = {'platform': platform.platform(), 'machine': platform.machine(),
              'scope': 'backend execution, exact same IL and amd64_sysv target',
              'binaries': {k: {'path': str(v), 'sha256': digest(v)} for k, v in binaries.items()},
              'repeats': args.repeats, 'max_ratio': args.max_ratio,
              'workloads': [], 'complete': False}

    def save():
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2)+'\n')

    save()
    try:
        with tempfile.TemporaryDirectory(prefix='qbe-benchmark-') as temporary:
            for source in args.inputs:
                source = source.resolve()
                row = {'input': str(source), 'input_sha256': digest(source),
                       'input_bytes': source.stat().st_size, 'samples': [],
                       'assembly_matches': True}
                report['workloads'].append(row)
                expected = None
                for repeat in range(args.repeats):
                    order = ('reference', 'backend') if repeat % 2 == 0 else ('backend', 'reference')
                    for kind in order:
                        output = Path(temporary)/f'{kind}.s'
                        command = [str(binaries[kind]), '-t', 'amd64_sysv', '-o', str(output), str(source)]
                        start = time.monotonic()
                        process = subprocess.run(command, capture_output=True, timeout=args.timeout)
                        sample = {'kind': kind, 'repeat': repeat, 'seconds': time.monotonic()-start,
                                  'returncode': process.returncode}
                        row['samples'].append(sample)
                        if process.returncode:
                            sample['stderr'] = process.stderr.decode(errors='replace')[-4000:]
                            raise RuntimeError(f'{kind} failed on {source}')
                        sample['assembly_sha256'] = digest(output)
                        if expected is None:
                            expected = sample['assembly_sha256']
                        row['assembly_matches'] &= sample['assembly_sha256'] == expected
                        save()
                row['median_seconds'] = {kind: statistics.median(
                    s['seconds'] for s in row['samples'] if s['kind'] == kind) for kind in binaries}
                row['ratio'] = row['median_seconds']['backend']/row['median_seconds']['reference']
                row['speed_goal_met'] = row['ratio'] <= args.max_ratio
                print(f'{source.name}: C {row["median_seconds"]["reference"]:.3f}s, '
                      f'LSL {row["median_seconds"]["backend"]:.3f}s, '
                      f'ratio {row["ratio"]:.2f}, exact={row["assembly_matches"]}', flush=True)
                save()
        report['complete'] = all(r['assembly_matches'] and r['speed_goal_met'] for r in report['workloads'])
    except Exception as exc:
        report['error'] = str(exc)
    save()
    return 0 if report['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
