#!/usr/bin/env python3
"""Build the release tools for another host platform.

The released x86_64 compiler (compiler/lslc with compiler/pure/luxir, after
build_release.py) translates the same sources as build_release.py with
--target, so the tools for every host come from the compiler that passed the
fixed points. The output directory receives bin/ with lslc, luxir, lsl,
lsl-install and lsl-configure (plus lsl-test on Linux; .exe on Windows).

--layout also assembles lib/lsl like an installed package: compiler sources,
standard library, the runtimes of all targets with the Windows import
definitions, the wasm and bare metal runners and the pinned manual. No
assembler or linker is bundled: luxir assembles and links programs for
every target itself.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
TARGETS = ('linux-arm64', 'linux-riscv64', 'linux-arm', 'linux-x86', 'windows-x86_64', 'windows-arm64', 'macos-x86_64', 'macos-arm64')
RUNTIMES = ['runtime.o', 'runtime-linux-arm64.o', 'runtime-linux-riscv64.o', 'runtime-linux-arm.o', 'runtime-linux-x86.o', 'runtime-windows-x86_64.o',
            'runtime-windows-arm64.o', 'runtime-macos-x86_64.o', 'runtime-macos-arm64.o',
            'runtime-wasm32-wasi.lir', 'runtime-baremetal-riscv64.o', 'libSystem.tbd']
IMPORTS = ['kernel32.def', 'synchronization.def', 'bcrypt.def', 'ws2_32.def']


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def layout(output):
    library = output / 'lib' / 'lsl'
    copies = [(ROOT / 'compiler/pure', library / 'compiler/pure', '*.lsl'),
              (ROOT / 'stdlib', library / 'stdlib', '*.lsl'),
              (ROOT / 'build/manual-source', library / 'docs/developer_guides', '*')]
    for source, destination, pattern in copies:
        if not source.is_dir():
            # Manuál chybí jen mimo vydání (CI bez prepare_sources).
            print('skipped missing', source.relative_to(ROOT), flush=True)
            continue
        destination.mkdir(parents=True, exist_ok=True)
        for path in sorted(source.glob(pattern)):
            if path.is_file() and path.name != 'qbe_emit_diagnostic.lsl':
                shutil.copy2(path, destination / path.name)
    (library / 'compiler/qbe').mkdir(parents=True, exist_ok=True)
    for name in RUNTIMES:
        shutil.copy2(ROOT / 'compiler/qbe' / name, library / 'compiler/qbe' / name)
    for machine in ('windows-x86_64', 'windows-arm64'):
        (library / 'compiler/qbe' / machine).mkdir(parents=True, exist_ok=True)
        for name in IMPORTS:
            shutil.copy2(ROOT / 'compiler/qbe' / machine / name, library / 'compiler/qbe' / machine / name)
    (library / 'runtime/arch').mkdir(parents=True, exist_ok=True)
    for name in ('wasi_wasm32.wat', 'wasi_wasm32_threads.wat', 'baremetal_riscv64.ld'):
        shutil.copy2(ROOT / 'runtime/arch' / name, library / 'runtime/arch' / name)
    (library / 'tools').mkdir(parents=True, exist_ok=True)
    for name in ('wasi_run.mjs', 'baremetal_run.py'):
        shutil.copy2(ROOT / 'tools' / name, library / 'tools' / name)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--target', required=True, choices=TARGETS)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--compiler', type=Path, default=ROOT / 'compiler/lslc')
    parser.add_argument('--backend', type=Path, default=ROOT / 'compiler/pure/luxir')
    parser.add_argument('--layout', action='store_true', help='also assemble lib/lsl')
    args = parser.parse_args()
    windows = args.target.startswith('windows-')
    lock = json.loads((ROOT / 'release.json').read_text())
    backend_source = Path(lock['backend']['directory']) / 'lsl/luxir.lsl'
    if not (ROOT / backend_source).is_file():
        parser.error('run tools/release/prepare_sources.py first')
    output = args.output.resolve()
    bin_directory = output / 'bin'
    bin_directory.mkdir(parents=True, exist_ok=True)
    suffix = '.exe' if windows else ''
    tools = [('lslc', [], 'compiler/pure/lslc_qbe.lsl'),
             ('luxir', [], str(backend_source)),
             ('lsl', ['--unsafe'], 'compiler/pure/cli.lsl'),
             ('lsl-install', ['--unsafe'], 'compiler/pure/install.lsl'),
             ('lsl-configure', ['--unsafe'], 'stdlib/configure.lsl')]
    if args.target.startswith('linux-'):
        tools.append(('lsl-test', ['--unsafe'], 'tests/test_runner.lsl'))
    report = {'target': args.target, 'compiler_sha256': digest(args.compiler.resolve()),
              'backend_sha256': digest(args.backend.resolve()), 'artifacts': {}}
    for name, flags, source in tools:
        target_file = bin_directory / (name + suffix)
        command = [str(args.compiler.resolve()), *flags, '--target', args.target, source,
                   str(target_file), str(args.backend.resolve())]
        process = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=900)
        if process.returncode:
            raise SystemExit(f'{name}: ' + (process.stderr or process.stdout).decode(errors='replace'))
        target_file.chmod(0o755)
        report['artifacts'][name + suffix] = digest(target_file)
        print(name + suffix, report['artifacts'][name + suffix], flush=True)
    if args.layout:
        layout(output)
    (output / 'build.json').write_text(json.dumps(report, indent=2) + '\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
