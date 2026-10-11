#!/usr/bin/env python3
"""Reproduce numeric/address collisions and check typed source-byte metadata."""
import argparse
import json
from pathlib import Path

from verify_public_int import ROOT, digest, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--backend', required=True, type=Path)
    parser.add_argument('--before', type=Path)
    parser.add_argument('--build-directory', required=True, type=Path)
    args = parser.parse_args()
    build = args.build_directory.resolve()
    build.mkdir(parents=True, exist_ok=True)
    compiler, backend = args.compiler.resolve(), args.backend.resolve()
    report = {'complete': False, 'compiler_sha256': digest(compiler),
              'backend_sha256': digest(backend), 'checks': [],
              'scope': 'Known Int/Bool operands at internal generic arithmetic boundaries; typed module byte counter. The historical isolated startup failure is not reproduced by this test.'}
    destination = build / 'verification.json'

    def check(frontend, source_name, suffix, program_args=(), expected_failure=False):
        source = ROOT / 'tests/qbe' / (source_name + '.lsl')
        program = build / (source_name + suffix)
        row = {'source': str(source.relative_to(ROOT)), 'source_sha256': digest(source),
               'expected_sha256': digest(source.with_suffix('.out')),
               'build': run([frontend, source, program, backend])}
        if row['build']['returncode'] == 0 and not row['build']['timed_out']:
            row['execution'] = run([program, *program_args])
            execution = row['execution']
            row['matches_expected'] = (execution['returncode'] == 0 and
                                       not execution['timed_out'] and
                                       execution['stdout'] == source.with_suffix('.out').read_text())
            row['matches'] = (not row['matches_expected'] if expected_failure else
                              row['matches_expected']) and execution['returncode'] == 0
        else:
            row['matches'] = False
        report['checks'].append(row)
        destination.write_text(json.dumps(report, indent=2) + '\n')
        print('PASS' if row['matches'] else 'FAIL', source_name, suffix, flush=True)

    if args.before:
        report['before_sha256'] = digest(args.before.resolve())
        check(args.before.resolve(), 'native_internal_numeric_collision', '-before', expected_failure=True)
    check(compiler, 'native_internal_numeric_collision', '-after')
    check(compiler, 'native_source_budget', '-after', [build])
    report['complete'] = True
    report['all_pass'] = all(row['matches'] for row in report['checks'])
    destination.write_text(json.dumps(report, indent=2) + '\n')
    return 0 if report['all_pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
