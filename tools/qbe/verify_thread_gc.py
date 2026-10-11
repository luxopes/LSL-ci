#!/usr/bin/env python3
"""Repeat the real automatic-GC/thread regression under scheduler contention.

First compile tests/automatic_gc_threads_conformance.lsl with the candidate,
then supply that executable. This checks exact maintained output on every run;
it records correctness only, never performance measurements.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--executable', type=Path, required=True)
    parser.add_argument('--expected', type=Path,
                        default=ROOT / 'tests/automatic_gc_threads_conformance.out')
    parser.add_argument('--repeat', type=int, default=100)
    parser.add_argument('--jobs', type=int, default=4)
    parser.add_argument('--timeout', type=float, default=20)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    if args.repeat <= 0 or args.jobs <= 0 or args.timeout <= 0:
        parser.error('repeat, jobs and timeout must be positive')
    executable = args.executable.resolve()
    expected = args.expected.read_bytes()
    digest = hashlib.sha256(executable.read_bytes()).hexdigest()

    def run(index):
        process = subprocess.Popen([str(executable)], cwd=ROOT,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   start_new_session=True)
        timed_out = False
        try:
            stdout, stderr = process.communicate(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
        return {'iteration': index, 'returncode': process.returncode,
                'timed_out': timed_out, 'stdout': stdout.decode(errors='replace'),
                'stderr': stderr.decode(errors='replace'),
                'pass': not timed_out and process.returncode == 0 and stdout == expected}

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        rows = list(pool.map(run, range(args.repeat)))
    unchanged = hashlib.sha256(executable.read_bytes()).hexdigest() == digest
    report = {'complete': True, 'scope': 'Correctness stress only; no timing benchmark',
              'executable_sha256': digest,
              'expected_stdout_sha256': hashlib.sha256(expected).hexdigest(),
              'concurrency': args.jobs, 'repeat': args.repeat, 'runs': rows,
              'executable_unchanged': unchanged,
              'all_pass': unchanged and all(row['pass'] for row in rows)}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    failed = sum(not row['pass'] for row in rows)
    print(f'{args.repeat - failed}/{args.repeat} PASS; {args.report}')
    return 0 if report['all_pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
