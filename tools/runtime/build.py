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


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--compiler', type=pathlib.Path, required=True,
                    help='existující LSL compiler (SOURCE OUTPUT [BACKEND])')
    ap.add_argument('--backend', type=pathlib.Path, default=ROOT / 'compiler/pure/luxir')
    ap.add_argument('--output', type=pathlib.Path, default=ROOT / 'compiler/qbe/runtime.o')
    ap.add_argument('--build', type=pathlib.Path, default=ROOT / 'build/runtime')
    ap.add_argument('--bootstrap-runtime', type=pathlib.Path, default=ROOT / 'build/runtime/bootstrap.o',
                    help='ověřený runtime.o pro nástroje sestavení')
    a = ap.parse_args()
    build = a.build.resolve()
    build.mkdir(parents=True, exist_ok=True)
    compiler = a.compiler.resolve()
    backend = a.backend.resolve()
    # Nástroje sestavení se linkují s ověřeným runtime (--bootstrap-runtime),
    # ne s tím, který se právě přestavuje: chyba v novém runtime nesmí
    # rozbít jeho vlastní sestavení.
    target = a.output.resolve()
    current = target.read_bytes()
    shutil.copyfile(a.bootstrap_runtime.resolve(), target)
    try:
        run(compiler, 'compiler/pure/lslc_runtime.lsl', build / 'lslc-runtime')
        run(compiler, 'compiler/pure/qbe_runtime_dump.lsl', build / 'runtime-dump')
    finally:
        target.write_bytes(current)
    # 1. Runtime v LSL -> LuxIR -> objekt.
    run(build / 'lslc-runtime', 'runtime/runtime.lsl', build / 'lslrt.lir')
    run(backend, '-t', 'amd64_sysv', '-o', build / 'lslrt.s', build / 'lslrt.lir')
    run('as', '--64', '-o', build / 'lslrt.o', build / 'lslrt.s')
    run('as', '--64', '-o', build / 'arch.o', 'runtime/arch/linux_x86_64.S')
    symbols = subprocess.run(['nm', '-g', '--defined-only', str(build / 'lslrt.o')],
                             capture_output=True, text=True, check=True).stdout.split()
    replaced = sorted(n for n in symbols if n.startswith('rt_runtime_') or n.startswith('qbe_'))
    (build / 'replaced.txt').write_text('\n'.join(replaced) + '\n')
    # 2. Zbývající x86 emitory bez nahrazených můstků.
    run(build / 'runtime-dump', build / 'x86')
    run('python3', 'tools/qbe/runtime_object.py', build / 'x86', build / 'replaced.txt')
    # 3. Jeden relokovatelný objekt pro linker.
    run('ld', '-r', '-o', build / 'runtime.o', build / 'x86.o', build / 'lslrt.o', build / 'arch.o')
    shutil.copyfile(build / 'runtime.o', a.output.resolve())
    print(f'runtime: {len(replaced)} routines from LSL -> {a.output}')


if __name__ == '__main__':
    main()
