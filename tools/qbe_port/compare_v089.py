#!/usr/bin/env python3
"""Compare installed LSL 0.8.9 with a selected native LSL compiler/backend.

Measure complete source-to-executable builds and separate executable wall times.
Both compilers receive identical ordinary public-ABI source files and iteration
counts. Alternate order, record every sample, and check independent checksums.
This is a version comparison, including runtime/stdlib differences, not an
isolated backend-only comparison. No changes to the installed compiler are made.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import resource
import signal
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / 'build/qbe-port-tools/v089-comparison'


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def checksum(name, count):
    if name == 'integer_loop':
        q, r = divmod(count, 97)
        return q * 97 * 96 // 2 + r * (r - 1) // 2
    if name in ('intarray_access', 'list_access', 'dictionary_access'):
        size = 128 if name == 'dictionary_access' else 1024
        q, r = divmod(count, size)
        return (q * size * (size - 1) // 2 + r * (r - 1) // 2
                + size * q * (q + 1) // 2 + r * (q + 1))
    if name == 'function_calls':
        a, b, value, modulus = 1664525, 1013904223, 1, 1 << 31
        while count:
            if count & 1:
                value = (a * value + b) % modulus
            a, b = a * a % modulus, (a + 1) * b % modulus
            count >>= 1
        return value
    if name == 'float_loop':
        value = 0.0
        for _ in range(count):
            value = (value + 0.5) * 1.000001
        return int(value * 1024.0)
    if name == 'string_split_join':
        return count * (len('alpha,beta,gamma,delta' * 3) + len('gamma'))
    if name == 'allocation_gc':
        return count
    raise ValueError(name)


def execute(command, timeout=180, cwd=ROOT):
    def memory_limit():
        resource.setrlimit(resource.RLIMIT_AS, (4 * 1024**3, 4 * 1024**3))
    start = time.monotonic()
    process = subprocess.Popen([str(x) for x in command], cwd=cwd,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               start_new_session=True, preexec_fn=memory_limit)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate()
        raise RuntimeError(f'timeout: {command}: {stderr[-2000:]!r}')
    seconds = time.monotonic() - start
    if process.returncode:
        raise RuntimeError(f'exit {process.returncode}: {command}\n'
                           + stdout.decode(errors='replace')[-2000:]
                           + stderr.decode(errors='replace')[-4000:])
    return {'seconds': seconds, 'returncode': process.returncode,
            'stdout_sha256': hashlib.sha256(stdout).hexdigest()}, stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--old', type=Path, default=Path.home()/'.local/bin/lslc')
    parser.add_argument('--new', type=Path,
                        default=ROOT/'build/qbe-port-tools/native-selfhost/frontend-stage3')
    parser.add_argument('--backend', type=Path,
                        default=ROOT/'build/qbe-port-tools/native-selfhost/qbe-stage3')
    parser.add_argument('--new-label', default='qbe_lsl',
                        help='label for the measured new compiler, e.g. luxir_lsl')
    parser.add_argument('--build-directory', type=Path, default=BUILD)
    parser.add_argument('--compile-repeats', type=int, default=3)
    parser.add_argument('--run-repeats', type=int, default=5)
    parser.add_argument('--large-source', type=Path,
                        help='optional identical compiler source to translate with both versions')
    parser.add_argument('--report', type=Path,
                        default=ROOT/'tests/qbe_port/comparison-v089-linux-x86_64.json')
    args = parser.parse_args()
    if min(args.compile_repeats, args.run_repeats) < 1:
        parser.error('repeat counts must be positive')
    if not args.new_label or args.new_label == 'v089':
        parser.error('--new-label must be nonempty and different from v089')
    build = args.build_directory.resolve()
    build.mkdir(parents=True, exist_ok=True)
    binaries = {'v089': args.old.resolve(), args.new_label: args.new.resolve()}
    report = {'platform': platform.platform(), 'machine': platform.machine(),
              'scope': 'complete compiler builds and execution of identical public LSL programs',
              'baseline_version': '0.8.9', 'memory_limit_gib': 4,
              'compile_repeats': args.compile_repeats, 'run_repeats': args.run_repeats,
              'timing': 'wall clock including process startup; alternating execution order; medians',
              'calibration': 'one pilot per binary; scale shared iterations to about 0.5s for the slower binary',
              'binaries': {k: {'path': str(v), 'sha256': digest(v)} for k,v in binaries.items()},
              'backend': {'path': str(args.backend.resolve()), 'sha256': digest(args.backend)},
              'runtime_sha256': digest(ROOT/'build/qbe/runtime.o'),
              'stdlib_sha256': {
                  'v089': digest(Path.home()/'.local/lib/lsl/compiler/pure/dynamic_stdlib.lsl'),
                  args.new_label: digest(ROOT/'compiler/pure/dynamic_stdlib.lsl')},
              'workloads': [], 'correctness_failures': [], 'complete': False}

    def save():
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2)+'\n')

    def compile_command(kind, source, output):
        cmd = [binaries[kind], source, output]
        if kind == args.new_label:
            cmd.append(args.backend.resolve())
        return cmd

    cases = [('integer_loop', 2000000), ('function_calls', 200000),
             ('float_loop', 50000), ('intarray_access', 100000),
             ('list_access', 100000), ('dictionary_access', 50000),
             ('string_split_join', 10000), ('allocation_gc', 50000)]
    save()
    try:
        for case_index, (name, initial) in enumerate(cases):
            source = ROOT/'tests/benchmarks/v089'/f'{name}.lsl'
            row = {'name': name, 'source': str(source.relative_to(ROOT)),
                   'source_sha256': digest(source), 'compile_samples': [], 'run_samples': []}
            report['workloads'].append(row)
            try:
                outputs = {kind: build/f'{name}-{kind}' for kind in binaries}
                for repeat in range(args.compile_repeats):
                    order = tuple(binaries) if (repeat+case_index)%2 == 0 else tuple(reversed(binaries))
                    for kind in order:
                        cmd = compile_command(kind, source, outputs[kind])
                        sample, _ = execute(cmd)
                        sample.update(kind=kind, repeat=repeat, command=[str(x) for x in cmd],
                                      binary_sha256=digest(outputs[kind]),
                                      binary_bytes=outputs[kind].stat().st_size)
                        row['compile_samples'].append(sample)
                        save()
                pilots = []
                expected = f'{checksum(name, initial)}\n'.encode()
                for kind in binaries:
                    sample, stdout = execute([outputs[kind], initial], timeout=60)
                    if stdout != expected:
                        row['mismatch'] = {'kind': kind, 'iterations': initial, 'actual_stdout': stdout.decode(errors='replace'), 'expected_stdout': expected.decode()}
                        raise RuntimeError(f'{name} {kind}: checksum mismatch: {stdout!r} != {expected!r}')
                    sample['kind'] = kind
                    pilots.append(sample)
                scale = min(50, max(0.1, 0.5/max(s['seconds'] for s in pilots)))
                count = min(100000000, max(1, int(initial*scale)))
                row.update(iterations=count, pilot_iterations=initial, pilots=pilots)
                expected = f'{checksum(name, count)}\n'.encode()
                row['expected_stdout'] = expected.decode()
                for repeat in range(args.run_repeats):
                    order = tuple(binaries) if (repeat+case_index)%2 == 0 else tuple(reversed(binaries))
                    for kind in order:
                        sample, stdout = execute([outputs[kind], count], timeout=60)
                        if stdout != expected:
                            row['mismatch'] = {'kind': kind, 'iterations': count, 'actual_stdout': stdout.decode(errors='replace'), 'expected_stdout': expected.decode()}
                            raise RuntimeError(f'{name} {kind}: checksum mismatch: {stdout!r} != {expected!r}')
                        sample.update(kind=kind, repeat=repeat, checksum_matches=True)
                        row['run_samples'].append(sample)
                        save()
                for stage in ('compile', 'run'):
                    medians = {kind: statistics.median(s['seconds'] for s in row[stage+'_samples']
                                                      if s['kind']==kind) for kind in binaries}
                    row[stage+'_median_seconds'] = medians
                    row[stage+'_new_over_old'] = medians[args.new_label]/medians['v089']
                print(name, 'compile', row['compile_median_seconds'],
                      'run', row['run_median_seconds'], flush=True)
                save()
                row['status'] = 'PASS'
                row['executable_bytes'] = {kind: output.stat().st_size
                                           for kind, output in outputs.items()}
            except Exception as exc:
                row['status'] = 'FAIL'
                row['error'] = str(exc)
                report['correctness_failures'].append(name)
                print(name, 'FAIL:', exc, flush=True)
                save()
        if args.large_source:
            try:
                source = args.large_source.resolve()
                row = {'source': str(source), 'source_sha256': digest(source), 'samples': []}
                report['common_compiler_source'] = row
                for repeat in range(args.compile_repeats):
                    for kind in (tuple(binaries) if repeat%2==0 else tuple(reversed(binaries))):
                        output = build/f'common-compiler-{kind}'
                        cmd = compile_command(kind, source, output)
                        sample, _ = execute(cmd, timeout=180)
                        sample.update(kind=kind, repeat=repeat, command=[str(x) for x in cmd],
                                      output_sha256=digest(output),
                                      output_bytes=output.stat().st_size)
                        row['samples'].append(sample)
                        print('common compiler', kind, round(sample['seconds'],3), flush=True)
                        save()
                row['median_seconds'] = {kind: statistics.median(s['seconds'] for s in row['samples']
                                                                 if s['kind']==kind) for kind in binaries}
                row['new_over_old'] = row['median_seconds'][args.new_label]/row['median_seconds']['v089']
            except Exception as exc:
                row['status'] = 'FAIL'
                row['error'] = str(exc)
                report['common_compiler_source_failure'] = str(exc)
                print('common compiler FAIL:', exc, flush=True)
                save()
        report['measurements_finished'] = True
        report['binaries_unchanged'] = all(digest(binaries[kind]) == record['sha256'] for kind,record in report['binaries'].items()) and digest(args.backend) == report['backend']['sha256']
        report['complete'] = (not report['correctness_failures'] and 'common_compiler_source_failure' not in report and report['binaries_unchanged'])
    except Exception as exc:
        report['error'] = str(exc)
        print('FAILED:', exc, flush=True)
    save()
    return 0 if report['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
