#!/usr/bin/env python3
"""Differentially compare a QBE-compatible backend with upstream QBE 1.3."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / 'vendor/qbe-1.3/test'
DEFAULT_TARGETS = ['amd64_sysv', 'amd64_apple', 'amd64_win', 'arm64', 'arm64_apple', 'rv64']


def first_diff(reference, backend, context=48):
    limit = min(len(reference), len(backend))
    index = next((i for i in range(limit) if reference[i] != backend[i]), limit)
    lo, hi = max(0, index-context), min(max(len(reference), len(backend)), index+context)
    return {
        'byte_offset': index,
        'reference_length': len(reference),
        'backend_length': len(backend),
        'reference_context': repr(reference[lo:min(hi, len(reference))]),
        'backend_context': repr(backend[lo:min(hi, len(backend))]),
    }


def invoke(executable, target, source, output, timeout):
    command = [str(executable), '-t', target, '-o', str(output), str(source)]
    started = time.monotonic()
    try:
        result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=timeout, check=False)
        elapsed = time.monotonic() - started
        return {'command': command, 'returncode': result.returncode,
                'success': result.returncode == 0, 'stdout': result.stdout,
                'stderr': result.stderr, 'elapsed_seconds': elapsed,
                'timed_out': False}
    except subprocess.TimeoutExpired as exc:
        elapsed = time.monotonic() - started
        return {'command': command, 'returncode': None, 'success': False,
                'stdout': exc.stdout or b'', 'stderr': exc.stderr or b'',
                'elapsed_seconds': elapsed, 'timed_out': True}


def run_case(reference, backend, target, source, timeout, temp_root=None):
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix='qbe-diff-', dir=temp_root) as case_dir:
        case = Path(case_dir)
        ref_out = case / 'reference.s'
        back_out = case / 'backend.s'
        ref = invoke(reference, target, source, ref_out, timeout)
        back = invoke(backend, target, source, back_out, timeout)
        error = None
        if ref['timed_out'] or back['timed_out']:
            error = {'kind': 'timeout', 'reference_timed_out': ref['timed_out'],
                     'backend_timed_out': back['timed_out']}
        elif ref['success'] != back['success']:
            error = {'kind': 'status_mismatch', 'reference_success': ref['success'],
                     'backend_success': back['success'],
                     'reference_returncode': ref['returncode'],
                     'backend_returncode': back['returncode']}
        elif ref['success']:
            ref_bytes = ref_out.read_bytes() if ref_out.exists() else b''
            back_bytes = back_out.read_bytes() if back_out.exists() else b''
            if ref_bytes != back_bytes:
                error = {'kind': 'assembly_mismatch',
                         'first_diff': first_diff(ref_bytes, back_bytes)}
        detail = {
            'target': target, 'input': str(source),
            'reference_success': ref['success'], 'backend_success': back['success'],
            'reference_seconds': ref['elapsed_seconds'],
            'backend_seconds': back['elapsed_seconds'],
            'elapsed_seconds': time.monotonic() - started,
        }
        if error:
            detail['error'] = error
            detail['reference_stderr'] = ref['stderr'][-4096:].decode('utf-8', 'replace')
            detail['backend_stderr'] = back['stderr'][-4096:].decode('utf-8', 'replace')
            detail['reference_command'] = ref['command']
            detail['backend_command'] = back['command']
        return detail


def write_report(path, report):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_text(json.dumps(report, indent=2) + '\n')
    temporary.replace(path)


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backend', type=Path, default=ROOT/'build/qbe-port-tools/qbe-lsl')
    parser.add_argument('--reference', type=Path, default=ROOT/'build/qbe/qbe')
    parser.add_argument('--test-directory', type=Path, default=TESTS,
                        help='directory containing the .ssa differential corpus')
    parser.add_argument('--timeout', type=float, default=30.0,
                        help='seconds allowed for each backend command (default: 30)')
    parser.add_argument('--target', action='append', choices=DEFAULT_TARGETS,
                        help='target to test; repeat to select several (default: all six)')
    parser.add_argument('--report', type=Path,
                        default=ROOT/'build/qbe-port-tools/differential.json')
    args = parser.parse_args()
    reference = args.reference.resolve()
    backend = args.backend.resolve()
    targets = args.target or DEFAULT_TARGETS
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    if not reference.is_file() or not os.access(reference, os.X_OK):
        parser.error(f'reference executable is missing or not executable: {reference}')
    if not backend.is_file() or not os.access(backend, os.X_OK):
        parser.error(f'backend executable is missing or not executable: {backend}')
    test_directory = args.test_directory.resolve()
    sources = sorted(test_directory.glob('*.ssa'))
    if not sources:
        parser.error(f'no .ssa tests found in {test_directory}')

    report = {
        'reference': str(reference), 'backend': str(backend),
        'test_directory': str(test_directory), 'timeout_seconds_per_command': args.timeout,
        'sha256': {
            'reference_binary': sha256(reference),
            'backend_binary': sha256(backend),
            'backend_source': sha256(ROOT/'compiler/pure/qbe_port/qbe_backend.lsl'),
            'stdio_source': sha256(ROOT/'compiler/pure/qbe_port/qbe_stdio.lsl'),
            'libc_source': sha256(ROOT/'compiler/pure/qbe_port/qbe_libc.lsl'),
            'stdio_test': sha256(ROOT/'tests/qbe_port/stdio_conformance.lsl'),
            'libc_test': sha256(ROOT/'tests/qbe_port/libc_conformance.lsl'),
        },
        'targets': targets, 'input_count': len(sources), 'started_at_epoch': time.time(),
        'completed_target_count': 0, 'completed_case_pairs': 0,
        'summary': {}, 'errors': [],
    }
    all_started = time.monotonic()
    write_report(args.report, report)
    with tempfile.TemporaryDirectory(prefix='qbe-differential-') as temp_root:
        for target in targets:
            summary = {'cases': 0, 'matching_success': 0,
                       'matching_failure': 0, 'mismatches': 0,
                       'timeouts': 0, 'reference_seconds': 0.0,
                       'backend_seconds': 0.0, 'status': 'running'}
            report['summary'][target] = summary
            for source in sources:
                result = run_case(reference, backend, target, source,
                                  args.timeout, temp_root)
                summary['cases'] += 1
                summary['reference_seconds'] += result['reference_seconds']
                summary['backend_seconds'] += result['backend_seconds']
                error = result.get('error')
                if error:
                    summary['mismatches'] += 1
                    if error['kind'] == 'timeout':
                        summary['timeouts'] += 1
                    report['errors'].append(result)
                elif result['reference_success']:
                    summary['matching_success'] += 1
                else:
                    summary['matching_failure'] += 1
            summary['status'] = 'complete'
            report['completed_target_count'] += 1
            report['completed_case_pairs'] += summary['cases']
            report['elapsed_seconds'] = time.monotonic() - all_started
            write_report(args.report, report)
            print(f"{target}: {summary['cases']} cases, {summary['mismatches']} mismatches, "
                  f"{summary['timeouts']} timeouts", flush=True)
    report['elapsed_seconds'] = time.monotonic() - all_started
    report['finished_at_epoch'] = time.time()
    write_report(args.report, report)
    total = sum(x['cases'] for x in report['summary'].values())
    mismatches = len(report['errors'])
    print(f"checked {total} target/case pairs across {len(sources)} inputs; "
          f"{mismatches} mismatches; report: {args.report}")
    return 1 if mismatches else 0


if __name__ == '__main__':
    raise SystemExit(main())
