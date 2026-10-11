#!/usr/bin/env python3
"""Compare maintained and boundary class fixtures with the installed compiler."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
POSITIVE = ['class_method_return_conformance', 'wide_class_abi_conformance',
            'inheritance_conformance', 'class_module_smoke', 'origin_function_conformance',
            'qbe/classes', 'qbe/class_default_call_flow']
NEGATIVE = ['private_class_negative', 'inheritance_cycle_negative', 'origin_without_parent_negative']
# Installed 0.8.9 has the same skipped-default-body inference bug. Its pointer
# numbers are retained as a failed control, not the intended language result.
ORACLE_ONLY = ['qbe/class_default_call_flow']

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def execute(command):
    def limit():
        resource.setrlimit(resource.RLIMIT_AS, (4*1024**3, 4*1024**3))
    start = time.monotonic()
    process = subprocess.Popen([str(x) for x in command], cwd=ROOT,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True, preexec_fn=limit)
    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=30)
    except subprocess.TimeoutExpired:
        timed_out = True
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate()
    return {'command': [str(x) for x in command], 'seconds': time.monotonic()-start,
            'returncode': process.returncode, 'timed_out': timed_out,
            'stdout': stdout.decode(errors='replace'), 'stderr': stderr.decode(errors='replace')}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--backend', type=Path, required=True)
    parser.add_argument('--old', type=Path, default=Path.home()/'.local/bin/lslc')
    parser.add_argument('--before', type=Path)
    parser.add_argument('--build-directory', type=Path, default=ROOT/'build/qbe-classes/verification')
    args = parser.parse_args()
    build = args.build_directory.resolve()
    build.mkdir(parents=True, exist_ok=True)
    compilers = {'v089': args.old.resolve(), 'candidate': args.compiler.resolve()}
    if args.before:
        compilers['before'] = args.before.resolve()
    report = {'scope': 'Class declarations, constructor/method/origin ABI and recoverable errors',
              'compilers': {k: {'path': str(v), 'sha256': digest(v)} for k, v in compilers.items()},
              'backend_sha256': digest(args.backend), 'runtime_sha256': digest(ROOT/'build/qbe/runtime.o'),
              'emitter_sha256': digest(ROOT/'compiler/pure/qbe_emit.lsl'),
              'semantic_sha256': digest(ROOT/'compiler/pure/semantic.lsl'),
              'memory_limit_gib': 4, 'timeout_seconds': 30, 'cases': [], 'complete': False}
    path = build/'verification.json'
    for name in POSITIVE+NEGATIVE:
        source = ROOT/'tests'/(name+'.lsl')
        positive = name in POSITIVE
        row = {'source': str(source.relative_to(ROOT)), 'source_sha256': digest(source),
               'positive': positive, 'comparison_required': name not in ORACLE_ONLY, 'runs': {}}
        if positive:
            row['expected'] = source.with_suffix('.out').read_text()
        report['cases'].append(row)
        for kind, compiler in compilers.items():
            output = build/(name.replace('/', '-')+'-'+kind)
            command = [compiler, source, output]
            if kind != 'v089':
                command.append(args.backend.resolve())
            result = {'build': execute(command)}
            row['runs'][kind] = result
            if result['build']['returncode'] == 0:
                result['binary_sha256'] = digest(output)
                result['execution'] = execute([output])
            if positive:
                execution = result.get('execution', {})
                result['passed'] = (execution.get('returncode') == 0
                                    and execution.get('stdout') == row['expected'])
            else:
                result['passed'] = (result['build']['returncode'] == 1
                                    and result['build']['stdout'].startswith('error[E2001]:'))
            print(name, kind, 'PASS' if result['passed'] else 'FAIL', flush=True)
            path.write_text(json.dumps(report, indent=2)+'\n')
        if not positive:
            old = row['runs']['v089']['build']
            new = row['runs']['candidate']['build']
            row['same_diagnostic'] = (old['stdout'], old['stderr']) == (new['stdout'], new['stderr'])
        row['passed'] = ((row['runs']['v089']['passed'] or not row['comparison_required'])
                         and row['runs']['candidate']['passed']
                         and row.get('same_diagnostic', True))
    report['old_control_failures'] = [row['source'] for row in report['cases']
                                      if not row['runs']['v089']['passed']]
    report['binaries_unchanged'] = all(digest(v) == report['compilers'][k]['sha256'] for k, v in compilers.items())
    report['complete'] = all(row['passed'] for row in report['cases']) and report['binaries_unchanged']
    path.write_text(json.dumps(report, indent=2)+'\n')
    return 0 if report['complete'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
