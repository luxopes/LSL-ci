#!/usr/bin/env python3
"""Sestaví runtime LSL pro cíl: runtime/*.lsl přes LuxIR a tenkou vrstvu
architektury runtime/arch/<cíl>.S do jednoho relokovatelného objektu.

Použití: build.py --compiler LSLC [--target linux-x86_64] [--output OBJEKT]
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
    'windows-x86_64': ('amd64_win', [], 'x86_64-w64-mingw32-as', [], 'x86_64-w64-mingw32-ld', 'windows_x86_64', 'runtime-windows-x86_64.o'),
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
    finally:
        host_runtime.write_bytes(current)
    # 1. Runtime v LSL -> LuxIR -> objekt; vrstva architektury.
    run(build / 'lslc-runtime', '--target', a.target, 'runtime/runtime.lsl', build / 'lslrt.lir')
    run(backend, '-t', luxir_target, *luxir_flags, '-o', build / 'lslrt.s', build / 'lslrt.lir')
    run(assembler, *as_flags, '-o', build / 'lslrt.o', build / 'lslrt.s')
    run(assembler, *as_flags, '-o', build / 'arch.o', f'runtime/arch/{arch}.S')
    parts = [build / 'lslrt.o', build / 'arch.o']
    # 2. Jeden relokovatelný objekt pro linker.
    run(linker, '-r', '-o', build / 'runtime.o', *parts)
    shutil.copyfile(build / 'runtime.o', output)
    print(f'runtime {a.target}: LSL + arch {arch} -> {output}')


if __name__ == '__main__':
    main()
