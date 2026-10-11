#!/usr/bin/env python3
"""Compare typed frontend state and exact SSA before/after structural caching.

Diagnostic correctness runs may overlap other agents. Their elapsed times are
recorded for reproducibility and must not be treated as performance results.
"""
import argparse
import json
from pathlib import Path
import shutil

from verify_public_int import ROOT, digest, run


CASES = [
    'tests/qbe/return_dependency_inference.lsl',
    'tests/qbe/frontend_scope_shadowing.lsl',
    'tests/recursive_return_conformance.lsl',
    'tests/class_method_return_conformance.lsl',
    'tests/inheritance_conformance.lsl',
    'tests/comprehension_conformance.lsl',
    'tests/rang_value_conformance.lsl',
    'tests/class_module_smoke.lsl',
    'tests/boxed_collection_conformance.lsl',
    'tests/qbe/public_call_inference.lsl',
    'tests/compiler/frontend_conformance.lsl',
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', required=True, type=Path)
    parser.add_argument('--after', required=True, type=Path)
    parser.add_argument('--backend', required=True, type=Path)
    parser.add_argument('--runtime', required=True, type=Path)
    parser.add_argument('--build-directory', required=True, type=Path)
    args = parser.parse_args()
    before, after, backend = args.before.resolve(), args.after.resolve(), args.backend.resolve()
    build = args.build_directory.resolve()
    build.mkdir(parents=True, exist_ok=True)
    runtime = build / 'runtime.o'
    shutil.copyfile(args.runtime.resolve(), runtime)
    report = {'scope': __doc__, 'complete': False, 'all_pass': False,
              'before_sha256': digest(before), 'after_sha256': digest(after),
              'backend_sha256': digest(backend), 'runtime_sha256': digest(runtime),
              'checks': []}
    destination = build / 'verification.json'
    for relative in CASES:
        source = ROOT / relative
        for mode in ['public', 'internal']:
            key = source.stem + '-' + mode
            old, new = build / (key + '-before'), build / (key + '-after')
            row = {'source': relative, 'source_sha256': digest(source), 'mode': mode,
                   'before': run([before, source, old, mode]),
                   'after': run([after, source, new, mode]), 'pass': False}
            if row['before']['returncode'] == row['after']['returncode'] == 0:
                old_types, new_types = old.with_suffix('.typed.json'), new.with_suffix('.typed.json')
                # Prefixes contain no suffix; with_suffix appends the desired extension.
                row['typed_equal'] = json.loads(old_types.read_text()) == json.loads(new_types.read_text())
                row['typed_sha256'] = digest(new_types)
                row['function_scope_count'] = len(json.loads(new_types.read_text())[4])
                old_ssa, new_ssa = old.with_suffix('.ssa'), new.with_suffix('.ssa')
                row['ssa_equal'] = old_ssa.read_bytes() == new_ssa.read_bytes()
                row['ssa_sha256'] = digest(new_ssa)
                row['pass'] = row['typed_equal'] and row['ssa_equal']
                if mode == 'public' and row['pass']:
                    assembly, obj, program = build / (key + '.s'), build / (key + '.o'), build / key
                    row['lower'] = run([backend, '-t', 'amd64_sysv', '-o', assembly, new_ssa])
                    row['assemble'] = run(['/usr/bin/as', '--64', '-o', obj, assembly])
                    row['link'] = run(['/usr/bin/ld', '-nostdlib', '-static', '-pie', '--no-dynamic-linker',
                                       '-z', 'text', '-z', 'noexecstack', '--build-id=none', '-s',
                                       '-o', program, obj, runtime])
                    if all(row[phase]['returncode'] == 0 for phase in ['lower', 'assemble', 'link']):
                        row['execution'] = run([program])
                        expected = source.with_suffix('.out')
                        row['expected_sha256'] = digest(expected)
                        row['output_equal'] = (row['execution']['returncode'] == 0 and
                                               row['execution']['stdout'] == expected.read_text())
                        row['pass'] = row['pass'] and row['output_equal']
                    else:
                        row['pass'] = False
            report['checks'].append(row)
            destination.write_text(json.dumps(report, indent=2) + '\n')
            print(('PASS' if row['pass'] else 'FAIL') + ' ' + relative + ' ' + mode, flush=True)
    report['complete'] = True
    report['all_pass'] = all(row['pass'] for row in report['checks'])
    report['typed_ssa_comparisons'] = len(report['checks'])
    report['maintained_output_executions'] = sum('execution' in row for row in report['checks'])
    destination.write_text(json.dumps(report, indent=2) + '\n')
    return 0 if report['all_pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
