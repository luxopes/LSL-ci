#!/usr/bin/env python3
"""Check failed HTTP transport trailers without adding String ordering semantics."""
import argparse
import json
import shutil
from pathlib import Path

from verify_public_int import ROOT, digest, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--backend', required=True, type=Path)
    parser.add_argument('--baseline', required=True, type=Path)
    parser.add_argument('--build-directory', required=True, type=Path)
    args = parser.parse_args()
    build = args.build_directory.resolve()
    build.mkdir(parents=True, exist_ok=True)
    tools = build / 'tools'
    tools.mkdir(exist_ok=True)
    # Both compiler binaries must read this checkout's patched stdlib, rather
    # than the installed 0.8.9 resources adjacent to the baseline executable.
    resources = tools / 'stdlib'
    if not resources.exists():
        resources.symlink_to(ROOT / 'stdlib', target_is_directory=True)
    compiler, baseline, backend = args.compiler.resolve(), args.baseline.resolve(), args.backend.resolve()
    native, old = tools / 'native', tools / 'baseline'
    shutil.copy2(compiler, native)
    shutil.copy2(baseline, old)
    child = build / 'failed-transport'
    child.write_text('#!/usr/bin/python3\nimport os, sys\nos.write(2, sys.argv[1].encode("utf-8"))\nsys.exit(7)\n')
    child.chmod(0o755)
    source = ROOT / 'tests/http_transport_error_conformance.lsl'
    expected = source.with_suffix('.out').read_text()
    fallback = 'curl exited with status 7'
    cases = [
        ('valid-zero', 'connection failed\n000', 'connection failed'),
        ('valid-999', 'connection failed\n999', 'connection failed'),
        ('unicode-message', 'Žluťoučký kůň\n404', 'Žluťoučký kůň'),
        ('empty-after-trailer', '\n000', fallback),
        ('empty-stderr', '', fallback),
        ('short-stderr', 'x', 'x'),
        ('lowercase-malformed', 'failed\n0a0', 'failed\n0a0'),
        ('uppercase-malformed', 'failed\n0A0', 'failed\n0A0'),
        ('first-digit-malformed', 'failed\na00', 'failed\na00'),
        ('last-digit-malformed', 'failed\n00a', 'failed\n00a'),
        ('wrong-separator', 'failed:000', 'failed:000'),
        ('unicode-digits', 'failed\n１２３', 'failed\n１２３'),
        ('bounded-message', 'x' * 4100 + '\n000', 'x' * 4096),
    ]
    report = {'compiler_sha256': digest(compiler), 'backend_sha256': digest(backend),
              'baseline_sha256': digest(baseline), 'http_source_sha256': digest(ROOT / 'stdlib/http.lsl'),
              'scope': 'Both ABIs, installed 0.8.9 compiler and native compiler, same patched stdlib; no network or C QBE.',
              'builds': [], 'checks': [], 'numeric_only': [], 'all_pass': False}
    for mode in ('public', 'internal'):
        fixture = build / (mode + '.lsl')
        fixture.write_text(('# lsl: internal-abi\n' if mode == 'internal' else '') + source.read_text())
        for name, driver in (('baseline', old), ('native', native)):
            program = build / (mode + '-' + name)
            command = [driver, fixture, program] + ([backend] if name == 'native' else [])
            compilation = run(command)
            report['builds'].append({'abi': mode, 'compiler': name, 'result': compilation})
            if compilation['returncode'] or compilation['timed_out']:
                raise RuntimeError('Fixture compilation failed: ' + str(compilation))
            for label, message, trimmed in cases:
                result = run([program, child, message, trimmed])
                passed = result['returncode'] == 0 and not result['timed_out'] and result['stdout'] == expected
                report['checks'].append({'abi': mode, 'compiler': name, 'case': label,
                                         'execution': result, 'pass': passed})
                print(('PASS ' if passed else 'FAIL ') + mode + '/' + name + '/' + label, flush=True)
        for operator in ('<', '<=', '>', '>='):
            rejected = build / (mode + '-ordering.lsl')
            rejected.write_text(('# lsl: internal-abi\n' if mode == 'internal' else '') + 'print "a" ' + operator + ' "b"\n')
            for name, driver in (('baseline', old), ('native', native)):
                image = build / (mode + '-ordering-' + name)
                command = [driver, rejected, image] + ([backend] if name == 'native' else [])
                result = run(command)
                if name == 'native' and result['returncode'] == 0:
                    # The QBE frontend records path-sensitive validation errors;
                    # the resulting native program must reject when reached.
                    execution = run([image])
                else:
                    execution = result
                passed = execution['returncode'] != 0 and not execution['timed_out'] and 'ordered comparison requires numeric operands' in (execution['stdout'] + execution['stderr'])
                report['numeric_only'].append({'abi': mode, 'compiler': name, 'operator': operator,
                                               'build': result, 'rejection': execution, 'pass': passed})
    report['all_pass'] = all(row['pass'] for row in report['checks'] + report['numeric_only'])
    (build / 'verification.json').write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    return 0 if report['all_pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
