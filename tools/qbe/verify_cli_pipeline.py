#!/usr/bin/env python3
"""Check the native compiler's public safety and CLI entry contracts.

The public CLI must be rebuilt from the same sources as the compiler. Tests
exercise its real compile/run/config paths; no fake backend is substituted.
"""
import argparse
import json
from pathlib import Path

from verify_public_int import ROOT, digest, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--cli', required=True, type=Path)
    parser.add_argument('--build-directory', required=True, type=Path)
    args = parser.parse_args()
    compiler, cli = args.compiler.resolve(), args.cli.resolve()
    build = args.build_directory.resolve()
    build.mkdir(parents=True, exist_ok=True)
    report = {'complete': False, 'compiler_sha256': digest(compiler),
              'cli_sha256': digest(cli), 'checks': []}
    output = build / 'verification.json'

    def check(name, command, status=0, stdout=None, diagnostic=None):
        sample = run(command, timeout=90)
        sample['name'] = name
        sample['matches'] = (sample['returncode'] == status and not sample['timed_out']
                             and (stdout is None or sample['stdout'] == stdout)
                             and (diagnostic is None or diagnostic in
                                  sample['stdout'] + sample['stderr']))
        report['checks'].append(sample)
        output.write_text(json.dumps(report, indent=2) + '\n')
        print('PASS' if sample['matches'] else 'FAIL', name, flush=True)
        return sample['matches']

    safe = build / 'safe.lsl'
    safe.write_text('print "native public", 6 * 7\n')
    unsafe = build / 'private.lsl'
    unsafe.write_text('print __lsl_syscall(39, 0, 0, 0, 0) > 0\n')
    lexical = build / 'lexical.lsl'
    lexical.write_text('unsafe:\n    print __lsl_syscall(39, 0, 0, 0, 0) > 0\nend\n')
    entry = build / 'entry.lsl'
    entry.write_text('unsafe:\n    print __lsl_entry_source()\nend\nprint arg(1)\n')
    internal = build / 'internal.lsl'
    internal.write_text('# lsl: internal-abi\nprint __lsl_syscall(39, 0, 0, 0, 0) > 0\n')
    executable = build / 'program'

    if check('compiler default native backend', [compiler, safe, executable]):
        check('compiler output', [executable], stdout='native public 42\n')
    check('compiler default rejects private intrinsic', [compiler, unsafe, executable],
          status=1, diagnostic='unsafe operation outside an unsafe block')
    check('compiler explicit safe rejects private intrinsic',
          [compiler, '--safe', unsafe, executable], status=1,
          diagnostic='unsafe operation outside an unsafe block')
    if check('compiler explicit unsafe', [compiler, '--unsafe', unsafe, executable]):
        check('compiler unsafe output', [executable], stdout='True\n')
    if check('compiler safe lexical unsafe block', [compiler, lexical, executable]):
        check('compiler lexical output', [executable], stdout='True\n')
    check('compiler sandbox rejects unsafe block',
          [compiler, '--sandbox', lexical, executable], status=1,
          diagnostic='unsafe block is forbidden in sandbox compilation')
    if check('compiler sandbox safe source', [compiler, '--sandbox', safe, executable]):
        check('compiler sandbox output', [executable], stdout='native public 42\n')
    if check('compiler internal ABI compatibility', [compiler, internal, executable]):
        check('compiler internal ABI output', [executable], stdout='True\n')
    check('compiler explicit safe overrides internal ABI',
          [compiler, '--safe', internal, executable], status=1,
          diagnostic='internal ABI requires compiler trust mode')
    check('compiler rejects unknown option', [compiler, '--missing', safe, executable], status=2)
    check('compiler missing target value', [compiler, '--target'], status=2)
    # Od 0.10 jsou Windows, macOS, WebAssembly i bare metal dostupné cíle.
    check('compiler unavailable target',
          [compiler, '--target', 'solaris-sparc64', safe, executable], status=1,
          diagnostic='unsupported compilation target')
    if check('public CLI compile', [cli, 'compile', safe, executable]):
        check('public CLI compiled output', [executable], stdout='native public 42\n')
    check('public CLI safe compile', [cli, 'compile', unsafe, executable], status=1,
          diagnostic='unsafe operation outside an unsafe block')
    if check('public CLI explicit unsafe', [cli, 'compile', '--unsafe', unsafe, executable]):
        check('public CLI unsafe output', [executable], stdout='True\n')
    check('public CLI source run', [cli, safe], stdout='native public 42\n')
    check('public CLI source run remains safe', [cli, unsafe], status=1,
          diagnostic='unsafe operation outside an unsafe block')
    check('public CLI internal pragma grants no trust', [cli, internal], status=1,
          diagnostic='unsafe operation outside an unsafe block')
    if check('public CLI compiled entry identity', [cli, 'compile', entry, executable]):
        check('compiled entry source is empty', [executable, 'probe'], stdout='\nprobe\n')
    check('source run entry identity and arguments', [cli, entry, 'probe'],
          stdout=str(entry) + '\nprobe\n')
    config = ROOT / 'tests/config/defaults.lsl'
    check('public CLI config evaluator', [cli, 'config', config],
          stdout=config.with_suffix('.out').read_text())
    report['complete'] = True
    report['all_pass'] = all(sample['matches'] for sample in report['checks'])
    report['binaries_unchanged'] = (report['compiler_sha256'] == digest(compiler)
                                     and report['cli_sha256'] == digest(cli))
    output.write_text(json.dumps(report, indent=2) + '\n')
    return 0 if report['all_pass'] and report['binaries_unchanged'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
