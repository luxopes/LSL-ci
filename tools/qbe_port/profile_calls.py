#!/usr/bin/env python3
"""Count emitted call sites in a diagnostic copy of x86-64 QBE assembly.

The original assembly, runtime and executable are never changed. Counters do
not measure inclusive runtime internals or cycles. Do not time this instrumented
executable: a counter changes flags and memory at each call (SysV call-clobbered
flags), and the entry return writes its counters to stderr with a syscall.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess

from compare_v089 import execute


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assembly', type=Path, required=True)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('arguments', nargs='*')
    args = parser.parse_args()
    assembly = args.assembly.read_text()
    targets = sorted(set(re.findall(r'^\s*callq?\s+([^\n]+)', assembly, re.M)))
    ids = {target: index for index, target in enumerate(targets)}
    result = []
    entry = False
    dumps = 0
    for line in assembly.splitlines():
        if line == 'lsl_entry:':
            entry = True
        elif line.startswith('.type lsl_entry,'):
            entry = False
        match = re.match(r'^\s*callq?\s+([^\n]+)', line)
        if match:
            result.append(f'\taddq $1, .Lprofile_counts+{8*ids[match[1]]}(%rip)')
        if entry and line.strip() == 'ret':
            result += ['pushq %rax', 'pushq %rcx', 'pushq %r11',
                       'mov $1, %eax', 'mov $2, %edi',
                       'lea .Lprofile_counts(%rip), %rsi',
                       f'mov ${8*len(targets)}, %edx', 'syscall',
                       'popq %r11', 'popq %rcx', 'popq %rax']
            dumps += 1
        result.append(line)
    if dumps != 1:
        raise RuntimeError(f'expected one lsl_entry return, found {dumps}')
    result += ['.bss', '.balign 8', '.Lprofile_counts:', f'.zero {8*len(targets)}']
    args.output.parent.mkdir(parents=True, exist_ok=True)
    instrumented = args.output.with_suffix('.profile.s')
    instrumented.write_text('\n'.join(result)+'\n')
    command = ['cc', '-nostdlib', '-no-pie', '-Wl,--build-id=none',
               '-o', args.output, instrumented, args.runtime]
    build, _ = execute(command, timeout=60)
    run_command = [str(args.output.resolve()), *args.arguments]
    # Small, bounded diagnostic inputs only. The normal comparison runner is
    # responsible for memory-capped, uninstrumented performance samples.
    process = subprocess.run(run_command, capture_output=True, timeout=60)
    if process.returncode or len(process.stderr) != len(targets)*8:
        raise RuntimeError(f'profile failed: {process.returncode}: {process.stderr!r}')
    counts = struct.unpack('<'+'Q'*len(targets), process.stderr)
    report = {'scope': 'dynamic counts at emitted direct/indirect call sites; excludes runtime-internal calls',
              'assembly_sha256': digest(args.assembly), 'runtime_sha256': digest(args.runtime),
              'instrumented_sha256': digest(instrumented), 'binary_sha256': digest(args.output),
              'build_command': [str(x) for x in command], 'run_command': run_command,
              'build': build, 'returncode': process.returncode,
              'stdout': process.stdout.decode(), 'counts': dict(zip(targets, counts))}
    args.report.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({k: v for k, v in report['counts'].items() if v}, indent=2))


if __name__ == '__main__':
    main()
