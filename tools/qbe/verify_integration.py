#!/usr/bin/env python3
"""Run the complete maintained pure-LSL regression runner through native QBE.

Unlike verify_language.py this includes process servers, stdin, config,
packages, installed resources, updater, negative diagnostics and native
frontend/backend fixed points. CUDA hardware and capability-sandbox tests keep
its original explicit availability gates; they are reported, never implied.
"""
import argparse
import hashlib
import json
import os
import tempfile
from pathlib import Path

from verify_public_int import digest, run

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--build-directory', required=True, type=Path)
    parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--timeout', type=int, default=1800)
    parser.add_argument('--mode', choices=('qbe', 'qbe-fast', 'qbe-fixed-point'), default='qbe')
    parser.add_argument('--phase', choices=('complete', 'post-aggregate'), default='complete',
                        help='post-aggregate diagnoses only the original checks after full_conformance')
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    build = args.build_directory.resolve()
    build.mkdir(parents=True, exist_ok=True)
    runner = build / 'lsl-test-qbe'
    sources = sorted([*ROOT.joinpath('compiler/pure').rglob('*.lsl'),
                      *ROOT.joinpath('stdlib').rglob('*.lsl'),
                      *ROOT.joinpath('tests').rglob('*.lsl'),
                      *ROOT.joinpath('tests').rglob('*.out'),
                      *ROOT.joinpath('tests').rglob('*.err')])
    manifest = {str(path.relative_to(ROOT)): digest(path) for path in sources}
    sandbox = (any(Path(path).exists() for path in ('/usr/bin/bwrap', '/bin/bwrap'))
               and any(Path(path).exists() for path in ('/usr/bin/systemd-run', '/bin/systemd-run'))
               and bool(os.getenv('XDG_RUNTIME_DIR')) and bool(os.getenv('DBUS_SESSION_BUS_ADDRESS')))
    runner_source = Path('tests/test_runner.lsl')
    expected_tail = 'pure LSL tests passed\n'
    if args.phase == 'post-aggregate':
        if args.mode != 'qbe':
            parser.error('--phase post-aggregate requires --mode qbe')
        source = ROOT.joinpath(runner_source).read_text()
        preamble_end = '# Standalone smoke/fixed-table programs cannot safely share aggregate state.\n'
        tail_begin = 'extensions_test = test_path("language-extensions-negative")\n'
        assert source.count(preamble_end) == 1 and source.count(tail_begin) == 1
        source = (source.split(preamble_end)[0] +
                  '# Diagnostic phase: original pre-aggregate checks are NOT executed.\n' +
                  tail_begin + source.split(tail_begin)[1])
        source = source.replace('print "pure LSL tests passed"',
                                'print "pure LSL post-aggregate diagnostic checks passed"')
        (build / 'post-aggregate-runner.lsl').write_text(source)
        # Keep the original tests/ library search context while compiling.
        with tempfile.NamedTemporaryFile(mode='w', suffix='.lsl',
                                         prefix='.qbe-post-aggregate-',
                                         dir=ROOT / 'tests', delete=False) as temporary:
            temporary.write(source)
            runner_source = Path(temporary.name)
        expected_tail = 'pure LSL post-aggregate diagnostic checks passed\n'
    report = {'scope': ('Complete original tests/test_runner.lsl with native QBE backend'
                        if args.phase == 'complete' else
                        'Only original checks after aggregated full_conformance: diagnostics, fuzz, GC, config and fixed points'),
              'phase': args.phase,
              'mode': args.mode, 'compiler': str(compiler), 'compiler_sha256': digest(compiler),
              'source_manifest_sha256': hashlib.sha256(json.dumps(manifest, sort_keys=True).encode()).hexdigest(),
              'source_manifest': manifest,
              'optional_checks': {'cuda_hardware_requested': os.getenv('LSL_CUDA_HARDWARE_TEST') == '1',
                                  'capability_sandbox_available': sandbox,
                                  'signed_public_release_archive': 'separate external-artifact integration',
                                  'managed_install_migration': 'separate secure-prefix integration'},
              'commands': [], 'complete': False, 'all_pass': False}
    if args.phase == 'post-aggregate':
        report['generated_runner_sha256'] = digest(build / 'post-aggregate-runner.lsl')
        report['complete_original_corpus'] = False

    def save():
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n')

    save()
    try:
        result = run([compiler, '--unsafe', runner_source, runner], timeout=120)
    finally:
        if args.phase == 'post-aggregate':
            runner_source.unlink(missing_ok=True)
    report['commands'].append({'name': 'compile original runner', **result})
    save()
    if result['returncode'] != 0 or result['timed_out']:
        return 1
    result = run([runner, args.mode, compiler], timeout=args.timeout)
    report['commands'].append({'name': 'run original regression corpus', **result})
    report['process_completed'] = not result['timed_out']
    expected = {'qbe': expected_tail, 'qbe-fast': 'pure LSL fast tests passed\n',
                'qbe-fixed-point': 'pure LSL fixed point passed\n'}[args.mode]
    report['all_pass'] = (result['returncode'] == 0 and not result['timed_out']
                          and result['stdout'].endswith(expected))
    report['complete'] = report['all_pass']
    report['compiler_unchanged'] = digest(compiler) == report['compiler_sha256']
    report['sources_unchanged'] = all(path.exists() and digest(path) == manifest[str(path.relative_to(ROOT))]
                                      for path in sources)
    save()
    print(result['stdout'][-5000:])
    print(result['stderr'][-5000:])
    return 0 if report['all_pass'] and report['compiler_unchanged'] and report['sources_unchanged'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
