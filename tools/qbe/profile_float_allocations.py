#!/usr/bin/env python3
"""Count Float boxing in a diagnostic copy of the runtime and executable.

No production compiler, runtime object, or source fixture is modified. The
counter wrappers preserve all registers; the entry wrapper writes counts to
stderr after the ordinary program returns. Instrumented wall times are not
performance evidence. This requires the Linux x86_64 runtime assembly artifact.
"""
import argparse
import json
from pathlib import Path

from verify_public_int import run, digest
import source_artifacts

ROOT = Path(__file__).resolve().parents[2]
SYMBOLS = (
    'runtime_float_new', 'runtime_alloc', 'runtime_add_any',
    'runtime_mul_any', 'runtime_box_dynamic_int', 'runtime_coerce_float',
    'runtime_float_from_int', 'runtime_gc', 'rt_runtime_maybe_gc',
)


def instrument_runtime(source):
    text = source.read_text()
    wrappers = ['.text']
    for index, name in enumerate(SYMBOLS):
        label = name + ':'
        if text.splitlines().count(label) != 1:
            raise RuntimeError('expected one runtime label: ' + name)
        text = text.replace('\n' + label + '\n',
                            '\ndiag_body_' + label + '\n')
        wrappers += [name + ':', f'addq $1,diag_counts+{index * 8}(%rip)',
                     'jmp diag_body_' + name]
    wrappers += ['.bss', '.align 8', '.globl diag_counts', 'diag_counts:',
                 f'.zero {len(SYMBOLS) * 8}']
    return text + '\n' + '\n'.join(wrappers) + '\n'


def instrument_program(source):
    text = source.read_text()
    if text.splitlines().count('lsl_entry:') != 1:
        raise RuntimeError('expected one program entry')
    text = text.replace('\nlsl_entry:\n', '\ndiag_program_entry:\n')
    text = text.replace('.type lsl_entry, @function',
                        '.type diag_program_entry, @function')
    text = text.replace('.size lsl_entry, .-lsl_entry',
                        '.size diag_program_entry, .-diag_program_entry')
    assembly = ['.text', 'lsl_entry:', 'sub $8,%rsp',
                'call diag_program_entry', 'mov %rax,(%rsp)']
    for index, name in enumerate(SYMBOLS):
        assembly += [f'mov diag_counts+{index * 8}(%rip),%rax',
                     f'lea diag_digits_{index}+16(%rip),%rdx', 'mov $16,%ecx',
                     f'diag_hex_{index}:', 'mov %rax,%r8', 'and $15,%r8',
                     'lea diag_hex_chars(%rip),%r9', 'movzbl (%r9,%r8),%r8d',
                     'dec %rdx', 'mov %r8b,(%rdx)', 'shr $4,%rax',
                     'dec %ecx', f'jnz diag_hex_{index}',
                     'mov $1,%eax', 'mov $2,%edi',
                     f'lea diag_line_{index}(%rip),%rsi',
                     f'mov ${len(name) + 18},%edx', 'syscall']
    assembly += ['mov (%rsp),%rax', 'add $8,%rsp', 'ret', '.data',
                 'diag_hex_chars:', '.ascii "0123456789abcdef"']
    for index, name in enumerate(SYMBOLS):
        assembly += [f'diag_line_{index}:', '.ascii "' + name + ' "',
                     f'diag_digits_{index}:', '.ascii "0000000000000000\\n"']
    return text + '\n' + '\n'.join(assembly) + '\n'


def expected_checksum(count):
    value = 0.0
    for _ in range(count):
        value = (value + 0.5) * 1.000001
    return f'{int(value * 1024)}\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--backend', type=Path, required=True)
    parser.add_argument('--runtime-assembly', type=Path, required=True)
    parser.add_argument('--build-directory', type=Path,
                        default=ROOT / 'build/qbe-float-profile')
    parser.add_argument('--iterations', type=int, action='append')
    args = parser.parse_args()
    counts = args.iterations or [1000, 10000]
    if any(count < 0 for count in counts):
        parser.error('iteration counts must be nonnegative')
    build = args.build_directory.resolve()
    build.mkdir(parents=True, exist_ok=True)
    runtime_source = args.runtime_assembly.resolve()
    runtime_object = ROOT / 'build/qbe/runtime.o'
    snapshot = digest(runtime_object)
    report = {'complete': False, 'scope': 'diagnostic call counts, not timings',
              'runtime_sha256': snapshot,
              'runtime_assembly_sha256': digest(runtime_source),
              'backend_sha256': digest(args.backend.resolve()), 'builds': [], 'checks': []}
    path = build / 'verification.json'

    def save():
        path.write_text(json.dumps(report, indent=2) + '\n')

    def checked(command):
        result = run(command)
        report['builds'].append(result)
        save()
        if result['returncode'] or result['timed_out']:
            raise RuntimeError('diagnostic build failed: ' + str(command))

    try:
        # Reject a stale runtime assembly dump before adding counters. Wrapper
        # changes can otherwise make a historical .s differ from runtime.o.
        original_object = build / 'runtime-uninstrumented.o'
        checked(['/usr/bin/cc', '-c', runtime_source, '-o', original_object])
        report['uninstrumented_runtime_sha256'] = digest(original_object)
        if digest(original_object) != snapshot:
            raise RuntimeError('runtime assembly does not reproduce production runtime.o')
        assembly = build / 'runtime-counted.s'
        assembly.write_text(instrument_runtime(runtime_source))
        counted_runtime = build / 'runtime-counted.o'
        checked(['/usr/bin/cc', '-c', assembly, '-o', counted_runtime])
        fixture = ROOT / 'tests/benchmarks/v089/float_loop.lsl'
        report['fixture_sha256'] = digest(fixture)
        for kind, compiler in [('baseline', args.baseline), ('candidate', args.compiler)]:
            compiler = compiler.resolve()
            report[kind + '_sha256'] = digest(compiler)
            output = build / ('float-' + kind)
            source_artifacts.clear(output)
            checked([compiler] + (["--unsafe"] if kind == "candidate" else [])
                    + [fixture, output, args.backend.resolve()])
            _, program_assembly, provenance = source_artifacts.obtain(
                compiler, args.backend.resolve(), fixture, output)
            report.setdefault("program_artifacts", {})[kind] = provenance
            counted_source = output.with_suffix('.counted.s')
            counted_source.write_text(instrument_program(program_assembly))
            counted_binary = output.with_suffix('.counted')
            checked(['/usr/bin/cc', '-nostdlib', '-no-pie', '-Wl,--build-id=none',
                     '-o', counted_binary, counted_source, counted_runtime])
            for count in counts:
                result = run([counted_binary, count])
                counters = {}
                for line in result['stderr'].splitlines():
                    name, number = line.split()
                    counters[name] = int(number, 16)
                result.update(kind=kind, iterations=count, counters=counters,
                              expected=expected_checksum(count))
                result['matches'] = (result['returncode'] == 0 and
                                     result['stdout'] == result['expected'] and
                                     set(counters) == set(SYMBOLS))
                report['checks'].append(result)
                save()
                if not result['matches']:
                    raise RuntimeError('instrumented program differs from oracle')
        report['runtime_unchanged'] = digest(runtime_object) == snapshot
        report['complete'] = report['runtime_unchanged']
    except Exception as error:
        report['error'] = str(error)
    save()
    print(('PASS' if report['complete'] else 'FAIL') + ': ' + str(path))
    return 0 if report['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
