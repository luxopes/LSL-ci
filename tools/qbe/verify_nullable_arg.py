#!/usr/bin/env python3
"""Check absent and present arg() values in public and internal ABI programs."""
import argparse
import json
from pathlib import Path

from verify_public_int import ROOT, digest, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--backend', required=True, type=Path)
    parser.add_argument('--build-directory', required=True, type=Path)
    parser.add_argument('--baseline', type=Path)
    args = parser.parse_args()
    build = args.build_directory.resolve()
    build.mkdir(parents=True, exist_ok=True)
    compiler, backend = args.compiler.resolve(), args.backend.resolve()
    original = ROOT / 'tests/qbe/native_nullable_arg.lsl'
    expected = original.with_suffix('.out').read_text()
    report = {'compiler_sha256': digest(compiler), 'backend_sha256': digest(backend),
              'checks': [], 'all_pass': False}
    for mode in ['public', 'internal']:
        source = build / ('arg-' + mode + '.lsl')
        source.write_text(('# lsl: internal-abi\n' if mode == 'internal' else '') + original.read_text())
        program = source.with_suffix('')
        row = {'mode': mode, 'source_sha256': digest(source),
               'build': run([compiler, source, program, backend])}
        if row['build']['returncode'] == 0 and not row['build']['timed_out']:
            row['execution'] = run([program, 'present'])
            result = row['execution']
            row['pass'] = result['returncode'] == 0 and not result['timed_out'] and result['stdout'] == expected
        else:
            row['pass'] = False
        report['checks'].append(row)
        print(('PASS' if row['pass'] else 'FAIL') + ' nullable arg ' + mode, flush=True)
    if args.baseline:
        baseline = args.baseline.resolve()
        report['baseline_sha256'] = digest(baseline)
        original = ROOT / 'tests/qbe/native_scalar_identity.lsl'
        for mode in ['public', 'internal']:
            source = build / ('identity-' + mode + '.lsl')
            source.write_text(('# lsl: internal-abi\n' if mode == 'internal' else '') + original.read_text())
            oracle = source.with_suffix('.baseline')
            program = source.with_suffix('')
            row = {'mode': mode, 'source_sha256': digest(source),
                   'baseline_build': run([baseline, source, oracle]),
                   'build': run([compiler, source, program, backend])}
            if row['baseline_build']['returncode'] == 0 and row['build']['returncode'] == 0:
                row['baseline_execution'] = run([oracle])
                row['execution'] = run([program])
                expected, actual = row['baseline_execution'], row['execution']
                row['pass'] = (expected['returncode'] == actual['returncode'] == 0 and
                               not expected['timed_out'] and not actual['timed_out'] and
                               expected['stdout'] == actual['stdout'])
            else:
                row['pass'] = False
            report['checks'].append(row)
            print(('PASS' if row['pass'] else 'FAIL') + ' scalar and collection identity ' + mode, flush=True)
    report['all_pass'] = all(row['pass'] for row in report['checks'])
    (build / 'verification.json').write_text(json.dumps(report, indent=2) + '\n')
    return 0 if report['all_pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
