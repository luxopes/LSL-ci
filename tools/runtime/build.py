#!/usr/bin/env python3
"""Sestaví runtime LSL: část v LSL (runtime/*.lsl) a zbývající x86 emitory.

Během přepisu do LSL obsahuje compiler/qbe/runtime.o obě části. Rutiny,
které už definuje runtime v LSL (rt_runtime_*), nemají x86 můstek.

Použití: build.py --compiler LSLC [--output compiler/qbe/runtime.o]
"""
import argparse, pathlib, subprocess, shutil

ROOT = pathlib.Path(__file__).resolve().parents[2]


def run(*command, **kw):
    subprocess.run([str(c) for c in command], check=True, cwd=ROOT, **kw)


# Cíl -> (cíl LuxIR, příznaky LuxIR, assembler, příznaky as, linker, arch, objekt)
TARGETS = {
    'linux-x86_64': ('amd64_sysv', [], 'as', ['--64'], 'ld', 'linux_x86_64', 'runtime.o'),
    'linux-arm64': ('arm64', [], 'aarch64-linux-gnu-as', [], 'aarch64-linux-gnu-ld', 'linux_arm64', 'runtime-linux-arm64.o'),
    'linux-riscv64': ('rv64', ['-p'], 'riscv64-linux-gnu-as', ['-march=rv64gc'], 'riscv64-linux-gnu-ld', 'linux_riscv64', 'runtime-linux-riscv64.o'),
}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--compiler', type=pathlib.Path, required=True,
                    help='existující LSL compiler (SOURCE OUTPUT [BACKEND])')
    ap.add_argument('--target', default='linux-x86_64', choices=sorted(TARGETS))
    ap.add_argument('--backend', type=pathlib.Path, default=ROOT / 'compiler/pure/luxir')
    ap.add_argument('--output', type=pathlib.Path, help='výchozí compiler/qbe/<objekt cíle>')
    ap.add_argument('--build', type=pathlib.Path, default=ROOT / 'build/runtime')
    ap.add_argument('--bootstrap-runtime', type=pathlib.Path, default=ROOT / 'build/runtime/bootstrap.o',
                    help='ověřený runtime.o pro nástroje sestavení')
    a = ap.parse_args()
    luxir_target, luxir_flags, assembler, as_flags, linker, arch, object_name = TARGETS[a.target]
    output = (a.output or ROOT / 'compiler/qbe' / object_name).resolve()
    build = (a.build / a.target).resolve() if a.target != 'linux-x86_64' else a.build.resolve()
    build.mkdir(parents=True, exist_ok=True)
    compiler = a.compiler.resolve()
    backend = a.backend.resolve()
    # Nástroje sestavení (hostitel x86_64) se linkují s ověřeným runtime
    # (--bootstrap-runtime), ne s tím, který se právě přestavuje.
    host_runtime = ROOT / 'compiler/qbe/runtime.o'
    current = host_runtime.read_bytes()
    shutil.copyfile(a.bootstrap_runtime.resolve(), host_runtime)
    try:
        run(compiler, 'compiler/pure/lslc_runtime.lsl', build / 'lslc-runtime')
        if a.target == 'linux-x86_64':
            run(compiler, 'compiler/pure/qbe_runtime_dump.lsl', build / 'runtime-dump')
    finally:
        host_runtime.write_bytes(current)
    # 1. Runtime v LSL -> LuxIR -> objekt; vrstva architektury.
    run(build / 'lslc-runtime', '--target', a.target, 'runtime/runtime.lsl', build / 'lslrt.lir')
    run(backend, '-t', luxir_target, *luxir_flags, '-o', build / 'lslrt.s', build / 'lslrt.lir')
    run(assembler, *as_flags, '-o', build / 'lslrt.o', build / 'lslrt.s')
    run(assembler, *as_flags, '-o', build / 'arch.o', f'runtime/arch/{arch}.S')
    parts = [build / 'lslrt.o', build / 'arch.o']
    replaced = []
    if a.target == 'linux-x86_64':
        symbols = subprocess.run(['nm', '-g', '--defined-only', str(build / 'lslrt.o'), str(build / 'arch.o')],
                                 capture_output=True, text=True, check=True).stdout.split()
        # Rozhraní, které už dodává LSL nebo vrstva architektury: x86 část ho
        # negeneruje (můstky, vstup _start, chybové funkce, lsl_state).
        replaced = sorted(set(n for n in symbols if n.startswith('rt_runtime_') or n.startswith('qbe_') or n in ('_start', 'lsl_state')))
        (build / 'replaced.txt').write_text('\n'.join(replaced) + '\n')
        # 2. Zbývající x86 emitory bez nahrazených můstků.
        run(build / 'runtime-dump', build / 'x86')
        run('python3', 'tools/qbe/runtime_object.py', build / 'x86', build / 'replaced.txt')
        parts.insert(0, build / 'x86.o')
    # 3. Jeden relokovatelný objekt pro linker.
    run(linker, '-r', '-o', build / 'runtime.o', *parts)
    shutil.copyfile(build / 'runtime.o', output)
    print(f'runtime {a.target}: {len(replaced) or "all"} routines from LSL -> {output}')


if __name__ == '__main__':
    main()
