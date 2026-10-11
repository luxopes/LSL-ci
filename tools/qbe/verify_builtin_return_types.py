#!/usr/bin/env python3
"""Compare raw-equality and fd-snapshot intrinsic result types with LSL 0.8.9."""
import argparse
import json
from pathlib import Path

from verify_public_int import ROOT, digest, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--backend', required=True, type=Path)
    parser.add_argument('--baseline', required=True, type=Path)
    parser.add_argument('--before', type=Path)
    parser.add_argument('--build-directory', required=True, type=Path)
    args = parser.parse_args()
    build = args.build_directory.resolve()
    build.mkdir(parents=True, exist_ok=True)
    compiler, backend, baseline = args.compiler.resolve(), args.backend.resolve(), args.baseline.resolve()
    fixture = ROOT / 'tests/qbe/native_builtin_return_types.lsl'
    expected = fixture.with_suffix('.out').read_text()
    report = {'compiler_sha256': digest(compiler), 'backend_sha256': digest(backend),
              'baseline_sha256': digest(baseline), 'fixture_sha256': digest(fixture),
              'checks': [], 'all_pass': False}
    drivers = [('baseline', baseline), ('native', compiler)]
    if args.before:
        drivers.append(('before', args.before.resolve()))
    for mode in ('public', 'internal'):
        source = build / (mode + '.lsl')
        source.write_text(('# lsl: internal-abi\n' if mode == 'internal' else '') + fixture.read_text())
        for name, driver in drivers:
            image = build / (name + '-' + mode)
            command = [driver] + ([] if name == 'baseline' else ['--unsafe']) + [source, image] + ([] if name == 'baseline' else [backend])
            compilation = run(command)
            row = {'abi': mode, 'compiler': name, 'build': compilation}
            if compilation['returncode'] == 0 and not compilation['timed_out']:
                result = run([image])
                row['execution'] = result
                row['matches_oracle'] = result['returncode'] == 0 and not result['timed_out'] and result['stdout'] == expected
            else:
                row['matches_oracle'] = False
            row['pass'] = row['matches_oracle'] if name != 'before' else not row['matches_oracle']
            report['checks'].append(row)
            print(('PASS ' if row['pass'] else 'FAIL ') + name + '/' + mode, flush=True)
    report['all_pass'] = all(row['pass'] for row in report['checks'])
    (build / 'verification.json').write_text(json.dumps(report, indent=2) + '\n')
    return 0 if report['all_pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
