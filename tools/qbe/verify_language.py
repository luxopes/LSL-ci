#!/usr/bin/env python3
"""Audit maintained output fixtures using the historical trusted compiler mode.

Only the native candidate receives --unsafe; installed 0.8.9 arguments stay
unchanged. Public CLI default-safety behavior is audited separately.
"""
import argparse
import json
from pathlib import Path

from verify_public_int import digest, run

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--backend', required=True, type=Path)
    parser.add_argument('--cases', required=True, type=Path,
                        help='JSON list of source paths with committed .out oracles')
    parser.add_argument('--baseline', type=Path,
                        help='optional installed compiler to check failed fixtures independently')
    parser.add_argument('--build-directory', required=True, type=Path)
    parser.add_argument('--report', required=True, type=Path)
    args = parser.parse_args()
    build = args.build_directory.resolve()
    build.mkdir(parents=True, exist_ok=True)
    compiler, backend = args.compiler.resolve(), args.backend.resolve()
    sources = [ROOT / path for path in json.loads(args.cases.read_text())]
    report = {'scope': 'Unmodified maintained source/output fixtures; sequential execution',
              'compiler': str(compiler), 'compiler_sha256': digest(compiler),
              'backend': str(backend), 'backend_sha256': digest(backend),
              'runtime_sha256': digest(ROOT / 'build/qbe/runtime.o'),
              'cases': [], 'complete': False, 'all_pass': False}

    def save():
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n')

    def check(frontend, source, output, native):
        command = [frontend] + (["--unsafe"] if native else []) + [source.relative_to(ROOT), output]
        if native:
            command.append(backend)
        row = {'build': run(command, timeout=60)}
        if row['build']['returncode'] == 0 and not row['build']['timed_out']:
            runtime_args = [str(build)] if source.name in {'bytearray_conformance.lsl', 'io_conformance.lsl', 'env_conformance.lsl', 'security_runtime_conformance.lsl', 'native_elf_conformance.lsl'} else []
            row['execution'] = run([output, *runtime_args], timeout=30)
            row['matches_expected'] = (row['execution']['returncode'] == 0
                                       and not row['execution']['timed_out']
                                       and row['execution']['stdout'] == source.with_suffix('.out').read_text())
        else:
            row['matches_expected'] = False
        row['status'] = 'PASS' if row['matches_expected'] else 'FAIL'
        return row

    save()
    for source in sources:
        if not source.with_suffix('.out').is_file():
            raise ValueError('Missing committed output oracle: ' + str(source))
        row = {'source': str(source.relative_to(ROOT)),
               'source_sha256': digest(source),
               'expected_sha256': digest(source.with_suffix('.out')),
               'candidate': check(compiler, source, build / source.stem, True)}
        report['cases'].append(row)
        save()
        if row['candidate']['status'] == 'FAIL' and args.baseline:
            row['baseline'] = check(args.baseline.resolve(), source,
                                    build / (source.stem + '-baseline'), False)
        print(row['candidate']['status'], source.name,
              ('baseline=' + row['baseline']['status']) if 'baseline' in row else '', flush=True)
        save()
    report['complete'] = True
    report['all_pass'] = all(row['candidate']['matches_expected'] for row in report['cases'])
    report['binaries_unchanged'] = (digest(compiler) == report['compiler_sha256']
                                   and digest(backend) == report['backend_sha256']
                                   and digest(ROOT / 'build/qbe/runtime.o') == report['runtime_sha256'])
    save()
    return 0 if report['all_pass'] and report['binaries_unchanged'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
