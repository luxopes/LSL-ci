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
    # 'luxir' jako assembler: vestavěný assembler LuxIR (luxir -a -t cíl).
    'linux-x86_64': ('amd64_sysv', [], 'luxir', [], None, 'linux_x86_64', 'runtime.o'),
    'linux-arm64': ('arm64', [], 'luxir', [], None, 'linux_arm64', 'runtime-linux-arm64.o'),
    'linux-riscv64': ('rv64', ['-p'], 'luxir', [], None, 'linux_riscv64', 'runtime-linux-riscv64.o'),
    'baremetal-riscv64': ('rv64', ['-p'], 'luxir', [], None, 'baremetal_riscv64', 'runtime-baremetal-riscv64.o'),
    # Windows: vestavěný assembler LuxIR zapisuje objekty COFF.
    'windows-x86_64': ('amd64_win', [], 'luxir', [], None, 'windows_x86_64', 'runtime-windows-x86_64.o'),
    'windows-arm64': ('arm64_win', [], 'luxir', [], None, 'windows_arm64', 'runtime-windows-arm64.o'),
    # WebAssembly: runtime zůstává v LIR (runtime-wasm32-wasi.lir); kompilátor
    # ho přeloží spolu s programem do jednoho modulu (vrstva architektury
    # runtime/arch/wasi_wasm32.wat).
    'wasm32-wasi': ('wasm32', [], None, [], None, 'wasi_wasm32', 'runtime-wasm32-wasi.lir'),
    # macOS: vestavěný assembler LuxIR zapisuje objekty Mach-O.
    'macos-x86_64': ('amd64_apple', [], 'luxir', [], None, 'macos_x86_64', 'runtime-macos-x86_64.o'),
    'macos-arm64': ('arm64_apple', [], 'luxir', [], None, 'macos_arm64', 'runtime-macos-arm64.o'),
    # 32bitové cíle: backend LuxIR arm/i386, k runtime pomocné funkce
    # 64bitového dělení a převodů (runtime/arch/w32_helpers.lir).
    'linux-arm': ('arm', [], 'luxir', [], None, 'linux_arm', 'runtime-linux-arm.o'),
    'linux-x86': ('i386', [], 'luxir', [], None, 'linux_x86', 'runtime-linux-x86.o'),
}


# Funkce Win32, které volá runtime a knihovny (stdlib/_*_windows_*.lsl),
# podle DLL. Zapíšou se jako soubory .def vedle objektu runtime; linker
# LuxIR z nich vytvoří tabulky importů (bez importních knihoven).
WINDOWS_IMPORTS = {
    'kernel32': ('kernel32.dll', '''AssignProcessToJobObject CloseHandle CreateDirectoryW CreateJobObjectW CreateFileMappingW CreateFileW CreatePipe
        CreateProcessW CreateThread CreateTimerQueueTimer DeleteFileW DeleteTimerQueueTimer DeleteProcThreadAttributeList ExitProcess ExitThread FindClose FindFirstFileW FindNextFileW FlushInstructionCache
        FreeEnvironmentStringsW GetCommandLineW GetConsoleCP GetConsoleMode GetConsoleScreenBufferInfo
        GetCurrentProcess GetModuleHandleW GetCurrentProcessId GetCurrentThreadId GetEnvironmentStringsW GetExitCodeProcess
        GetFileAttributesW GetFileInformationByHandle GetFileType GetFinalPathNameByHandleW
        GetHandleInformation GetLastError GetModuleFileNameW GetProcessAffinityMask GetStdHandle
        GetSystemTimePreciseAsFileTime GetTempFileNameW GetTempPathW GetThreadContext
        InitializeProcThreadAttributeList MapViewOfFile MoveFileExW MultiByteToWideChar PeekConsoleInputW PeekNamedPipe
        QueryPerformanceCounter QueryPerformanceFrequency ReadConsoleInputW ReadConsoleW ReadFile
        RemoveDirectoryW ResumeThread SetConsoleCP SetConsoleMode SetFilePointerEx SetHandleInformation SetInformationJobObject
        SetUnhandledExceptionFilter Sleep SuspendThread SwitchToThread TerminateProcess TlsAlloc
        UnmapViewOfFile UpdateProcThreadAttribute VirtualProtect VirtualAlloc VirtualFree WaitForSingleObject
        WideCharToMultiByte WriteConsoleW WriteFile'''),
    'synchronization': ('api-ms-win-core-synch-l1-2-0.dll', 'WaitOnAddress WakeByAddressAll WakeByAddressSingle'),
    'bcrypt': ('bcrypt.dll', 'BCryptGenRandom'),
    'ws2_32': ('ws2_32.dll', '''WSAGetLastError WSAPoll WSASocketW WSAStartup accept bind closesocket
        getsockname getsockopt listen recv send setsockopt'''),
}


def windows_import_definitions(directory):
    directory.mkdir(parents=True, exist_ok=True)
    for name, (dll, functions) in WINDOWS_IMPORTS.items():
        (directory / f'{name}.def').write_text(f'LIBRARY {dll}\nEXPORTS\n' + ''.join(f'{f}\n' for f in functions.split()))


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
    if assembler == 'luxir':
        assembler = a.backend.resolve()
        as_flags = ['-a', '-t', luxir_target]
    output = (a.output or ROOT / 'compiler/qbe' / object_name).resolve()
    build = (a.build / a.target).resolve() if a.target != 'linux-x86_64' else a.build.resolve()
    build.mkdir(parents=True, exist_ok=True)
    compiler = a.compiler.resolve()
    backend = a.backend.resolve()
    # Nástroje sestavení (hostitel x86_64) se linkují s ověřeným runtime
    # (--bootstrap-runtime), ne s tím, který se právě přestavuje.
    host_runtime = ROOT / 'compiler/qbe/runtime.o'
    current = host_runtime.read_bytes()
    # V čisté kopii (CI) je ověřený runtime přímo compiler/qbe/runtime.o.
    if a.bootstrap_runtime.resolve() != host_runtime.resolve():
        shutil.copyfile(a.bootstrap_runtime.resolve(), host_runtime)
    try:
        run(compiler, 'compiler/pure/lslc_runtime.lsl', build / 'lslc-runtime')
    finally:
        host_runtime.write_bytes(current)
    # 1. Runtime v LSL -> LuxIR -> objekt; vrstva architektury.
    run(build / 'lslc-runtime', '--target', a.target, 'runtime/runtime.lsl', build / 'lslrt.lir')
    if assembler is None:
        # Kontrola, že backend runtime přeloží; do modulu jde LIR.
        run(backend, '-t', luxir_target, '-o', build / 'lslrt.wat', build / 'lslrt.lir')
        shutil.copyfile(build / 'lslrt.lir', output)
        print(f'runtime {a.target}: LSL -> {output}')
        return
    run(backend, '-t', luxir_target, *luxir_flags, '-o', build / 'lslrt.s', build / 'lslrt.lir')
    if assembler == a.backend.resolve():
        # Vestavěný assembler: runtime, vrstva architektury a pomocné funkce
        # v jednom objektu (jeden běh místo ld -r).
        sources = [build / 'lslrt.s', ROOT / f'runtime/arch/{arch}.S']
        if luxir_target in ('arm', 'i386'):
            run(backend, '-t', luxir_target, '-o', build / 'helpers.s', ROOT / 'runtime/arch/w32_helpers.lir')
            sources.append(build / 'helpers.s')
        if a.target.startswith('macos-'):
            # Mach-O: každý symbol ve vlastní podsekci (linker vypustí
            # nepoužité funkce).
            (build / 'subsections.s').write_text('.subsections_via_symbols\n')
            sources.append(build / 'subsections.s')
        run(assembler, *as_flags, '-o', build / 'runtime.o', *sources)
        shutil.copyfile(build / 'runtime.o', output)
        if a.target.startswith('windows-'):
            windows_import_definitions(output.parent / a.target)
        print(f'runtime {a.target}: LSL + arch {arch} -> {output}')
        return
    if linker is None:
        combined = (ROOT / f'runtime/arch/{arch}.S').read_text() + '\n' + (build / 'lslrt.s').read_text()
        if a.target.startswith('macos-'):
            # Mach-O: každý symbol ve vlastní podsekci pro -dead_strip.
            combined += '\n.subsections_via_symbols\n'
        (build / 'runtime.s').write_text(combined)
        run(assembler, *as_flags, '-o', build / 'runtime.o', build / 'runtime.s')
    else:
        run(assembler, *as_flags, '-o', build / 'lslrt.o', build / 'lslrt.s')
        run(assembler, *as_flags, '-o', build / 'arch.o', f'runtime/arch/{arch}.S')
        parts = [build / 'lslrt.o', build / 'arch.o']
        if luxir_target in ('arm', 'i386'):
            run(backend, '-t', luxir_target, '-o', build / 'helpers.s', ROOT / 'runtime/arch/w32_helpers.lir')
            run(assembler, *as_flags, '-o', build / 'helpers.o', build / 'helpers.s')
            parts.append(build / 'helpers.o')
        # 2. Jeden relokovatelný objekt pro linker.
        run(*(linker if isinstance(linker, list) else [linker]), '-r', '-o', build / 'runtime.o', *parts)
    shutil.copyfile(build / 'runtime.o', output)
    print(f'runtime {a.target}: LSL + arch {arch} -> {output}')


if __name__ == '__main__':
    main()
