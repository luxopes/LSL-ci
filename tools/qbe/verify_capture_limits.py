#!/usr/bin/env python3
"""Check native capture preserves inherited RLIMIT_FSIZE bounds."""
import argparse
import json
import resource
import subprocess
from pathlib import Path
from verify_public_int import digest, run

ROOT = Path(__file__).resolve().parents[2]
CAP = 134217728


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--build-directory', required=True, type=Path)
    parser.add_argument('--report', required=True, type=Path)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    build = args.build_directory.resolve()
    build.mkdir(parents=True, exist_ok=True)
    source = ROOT / 'tests/qbe_port/native_capture_file_limits.lsl'
    report = {'scope': __doc__, 'compiler_sha256': digest(compiler),
              'source_sha256': digest(source),
              'runtime_object_sha256': digest(ROOT / 'build/qbe/runtime.o'),
              'runtime_source_sha256': digest(ROOT / 'compiler/pure/process_runtime_linux_x86_64.lsl'),
              'correctness_only': True,
              'commands': [], 'rows': [], 'all_pass': False}

    def save():
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n')

    save()
    for mode in ('public', 'internal'):
        target_source = source
        if mode == 'internal':
            target_source = build / 'capture-limits-internal.lsl'
            target_source.write_text('# lsl: internal-abi\n' + source.read_text())
        binary = build / ('capture-limits-' + mode)
        result = run([compiler, '--unsafe', target_source, binary], timeout=120)
        report['commands'].append({'mode': mode, **result})
        save()
        if result['returncode'] != 0 or result['timed_out']:
            return 1
        report['commands'][-1]['binary_sha256'] = digest(binary)
        for soft, hard in ((16777216, 16777216), (67108864, 67108864),
                           (CAP, CAP), (1048576, 67108864),
                           (16777216, 268435456), (-1, -1)):
            def set_limits():
                resource.setrlimit(resource.RLIMIT_FSIZE, (soft, hard))
            result = subprocess.run([binary], capture_output=True, text=True,
                                    preexec_fn=set_limits, timeout=30, cwd=ROOT)
            child_soft = CAP if soft == -1 else min(soft, CAP)
            child_hard = CAP if hard == -1 else min(hard, CAP)
            expected = (f'before {soft} {hard}\n'
                        f'captured {child_soft} {child_hard}\n'
                        f'after {soft} {hard}\n')
            row = {'mode': mode, 'inherited_limits': [soft, hard],
                   'returncode': result.returncode, 'stdout': result.stdout,
                   'stderr': result.stderr, 'expected_stdout': expected,
                   'pass': result.returncode == 0 and result.stdout == expected}
            report['rows'].append(row)
            save()
    report['all_pass'] = len(report['rows']) == 12 and all(row['pass'] for row in report['rows'])
    save()
    print('Inherited file limits:', len(report['rows']), 'PASS' if report['all_pass'] else 'FAIL')
    return 0 if report['all_pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
