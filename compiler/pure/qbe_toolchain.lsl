# Sestavení nativního obrazu přes backend LuxIR. Program nemá C runtime.
load qbe_emit
load host

# Cíl backendu podle platformy LSL.
BACKEND_TARGETS = {"linux-x86_64":"amd64_sysv","linux-arm64":"arm64","linux-riscv64":"rv64","windows-x86_64":"amd64_win","windows-arm64":"arm64_win","macos-x86_64":"amd64_apple","macos-arm64":"arm64_apple","wasm32-wasi":"wasm32","wasm32-wasi-threads":"wasm32","baremetal-riscv64":"rv64","linux-arm":"arm","linux-x86":"i386"}
# Příznaky backendu pro cíl (WebAssembly s vlákny: -g).
BACKEND_FLAGS = {"linux-x86_64":[],"linux-arm64":[],"linux-riscv64":["-p"],"windows-x86_64":[],"windows-arm64":[],"macos-x86_64":[],"macos-arm64":[],"wasm32-wasi":[],"wasm32-wasi-threads":["-g"],"baremetal-riscv64":["-p"],"linux-arm":[],"linux-x86":[]}
RUNTIME_OBJECTS = {"linux-x86_64":"runtime.o","linux-arm64":"runtime-linux-arm64.o","linux-riscv64":"runtime-linux-riscv64.o","windows-x86_64":"runtime-windows-x86_64.o","windows-arm64":"runtime-windows-arm64.o","macos-x86_64":"runtime-macos-x86_64.o","macos-arm64":"runtime-macos-arm64.o","wasm32-wasi":"runtime-wasm32-wasi.lir","wasm32-wasi-threads":"runtime-wasm32-wasi.lir","baremetal-riscv64":"runtime-baremetal-riscv64.o","linux-arm":"runtime-linux-arm.o","linux-x86":"runtime-linux-x86.o"}
# Windows: importy Win32 (kernel32, WaitOnAddress, BCryptGenRandom, Winsock)
# jako soubory .def vedle objektu runtime (tools/runtime/build.py); linker
# LuxIR z nich vytvoří tabulky importů.
WINDOWS_IMPORTS = ["kernel32", "synchronization", "bcrypt", "ws2_32"]

# Nativní cíle: LuxIR program přeloží, sestaví vestavěným assemblerem
# a slinkuje vestavěným linkerem v jednom běhu (luxir -a -l): ELF pro
# Linux x86-64, i386, arm, arm64, riscv64, obraz bare metal RISC-V, PE32+
# pro Windows x86-64 a arm64 a Mach-O pro macOS x86-64 a arm64. Žádný cíl
# nepotřebuje binutils, LLVM ani Xcode.
BUILTIN_ASSEMBLER = {"linux-x86_64":"amd64_sysv","linux-x86":"i386","linux-arm64":"arm64","linux-riscv64":"rv64","linux-arm":"arm","baremetal-riscv64":"rv64","windows-x86_64":"amd64_win","windows-arm64":"arm64_win","macos-x86_64":"amd64_apple","macos-arm64":"arm64_apple"}

# Textový stub libSystem pro linker LuxIR (macOS).
function library_stub():
    path = host.resource_path("compiler/qbe/libSystem.tbd")
    if not exists(path):
        Error(CompileError: "macOS library stub is missing: " + path + " (reinstall the LSL package)")
    end
    return path
end

# Soubory .def importů Win32 pro linker LuxIR.
function windows_imports(name):
    result = []
    for library in WINDOWS_IMPORTS:
        path = host.resource_path("compiler/qbe/" + name + "/" + library + ".def")
        if not exists(path):
            Error(CompileError: "Windows import definitions are missing: " + path + " (reinstall the LSL package)")
        end
        result.append(path)
    end
    return result
end

# Backend není napevno zadaný: LSL_BACKEND je absolutní cesta k programu
# kompatibilnímu s LuxIR, jinak se použije luxir vedle compileru nebo
# vývojový build v repozitáři.
function native_backend_path():
    configured = __lsl_getenv("LSL_BACKEND")
    if configured != None and String(configured) != "":
        path = String(configured)
        if not path.startswith("/"):
            Error(CompileError: "LSL_BACKEND must be an absolute path: " + path)
        end
        if not exists(path):
            Error(CompileError: "LSL_BACKEND does not exist: " + path)
        end
        return path
    end
    repository_backend = host.resource_path("compiler/pure/luxir")
    if not exists(repository_backend):
        repository_backend = host.resource_path("build/luxir/luxir")
    end
    path = host.tool_path(repository_backend, "luxir")
    if not exists(path):
        Error(CompileError: "LuxIR backend is missing: " + path + " (install luxir or set LSL_BACKEND)")
    end
    return path
end

function runtime_path(selected):
    name = RUNTIME_OBJECTS[selected["name"]]
    path = host.resource_path("compiler/qbe/" + name)
    if not exists(path):
        path = host.resource_path("build/qbe/" + name)
    end
    if not exists(path):
        Error(CompileError: "native LSL runtime object is missing: " + path)
    end
    return path
end

function invoke(tool, arguments, stage):
    output = capture_clean(tool, arguments)
    status = capture_status()
    detail = capture_stderr()
    if status != 0:
        Error(CompileError: stage + " failed (status " + String(status) + "): " + detail + output)
    end
end

# Argumenty nástroje: pevné části a příznaky cíle z tabulky (seznamy
# se v kódu compileru skládají po prvcích, ne operátorem +).
function tool_arguments(prefix, flags, suffix):
    result = []
    for item in prefix:
        result.append(item)
    end
    for item in flags:
        result.append(item)
    end
    for item in suffix:
        result.append(item)
    end
    return result
end

function cleanup(path):
    call unlink(path + ".c")
    call unlink(path + ".c.body")
    call unlink(path + ".lir.phase")
    call unlink(path + ".lir")
    call unlink(path + ".s")
    call unlink(path + ".o")
    call host.cleanup_program(path)
end

# WebAssembly: runtime (LIR) a program se přeloží spolu do jednoho modulu
# (s vlákny -g), vrstva architektury je text WAT (s vlákny
# wasi_wasm32_threads.wat). Binární modul vyrobí LuxIR v jednom běhu
# (luxir -a -t wasm32 vrstva.wat program.lir): překlad LIR a vestavěný
# assembler WAT, bajtově shodný s wat2wasm. Linker se nepoužije.
function wasm_image(unit, selected, entry_source, backend):
    runtime = runtime_path(selected)
    layer = host.resource_path("runtime/arch/wasi_wasm32.wat")
    if selected["name"] == "wasm32-wasi-threads":
        layer = host.resource_path("runtime/arch/wasi_wasm32_threads.wat")
    end
    if not exists(layer):
        Error(CompileError: "WebAssembly architecture layer is missing: " + layer)
    end
    path = host.scratch_program_path()
    failure = None
    result = ByteArray()
    try:
        call qbe_emit.generate(unit, path + ".lir", entry_source)
        call writefile(path + ".all.lir", readfile(runtime) + chr(10) + readfile(path + ".lir"))
        call invoke(backend, tool_arguments(["-a", "-t", "wasm32"], BACKEND_FLAGS[selected["name"]], ["-o", path, layer, path + ".all.lir"]), "LuxIR backend")
        result = readbytes(path)
    else:
        failure = last_error()
    end
    call unlink(path + ".all.lir")
    call unlink(path + ".wat")
    call cleanup(path)
    if failure != None:
        Error(CompileError: failure)
    end
    return result
end

function image(unit, selected, entry_source="", backend_path=""):
    if selected["name"] not in BACKEND_TARGETS:
        Error(CompileError: "native runtime is not implemented for: " + selected["name"])
    end
    backend = backend_path
    if backend == "":
        backend = native_backend_path()
    end
    if selected["os"] == "wasi":
        return wasm_image(unit, selected, entry_source, backend)
    end
    name = selected["name"]
    if name not in BUILTIN_ASSEMBLER:
        Error(CompileError: "native image is not implemented for: " + name)
    end
    runtime = runtime_path(selected)
    path = host.scratch_program_path()
    failure = None
    result = ByteArray()
    try:
        call qbe_emit.generate(unit, path + ".lir", entry_source)
        # Překlad LIR, sestavení a slinkování v jednom běhu (-a -l) bez
        # dalších procesů. Jméno dočasného souboru se do obrazu nedostane
        # (LuxIR připojí .file "luxir").
        flags = ["-a", "-l", "-t", BUILTIN_ASSEMBLER[name]]
        inputs = ["-o", path, path + ".lir", runtime]
        if selected["os"] == "windows":
            # Konzolový program PE32+ s ASLR (high-entropy VA), DEP
            # a zásobníkem 8 MiB, importy Win32 ze souborů .def.
            inputs.extend(windows_imports(name))
        elif selected["os"] == "macos":
            # Mach-O (PIE, ad-hoc podpis) dynamicky linkovaný s libSystem:
            # macOS nepodporuje statické programy ani přímá systémová
            # volání. libSystem.tbd je textový stub (bez SDK); nepoužité
            # funkce se vypustí (atomy po symbolech).
            inputs.append(library_stub())
        elif selected["os"] == "baremetal":
            # Obraz bez OS v rozložení desky (-b místo linker skriptu
            # runtime/arch/baremetal_riscv64.ld): ET_EXEC od RAM, kód
            # s adresami relativně k PC (-p), zásobníky a konec obrazu
            # pro haldu.
            flags = ["-a", "-l", "-b", "-p", "-t", BUILTIN_ASSEMBLER[name]]
        elif name != "linux-x86" and name != "linux-arm":
            # Statický ELF bez tabulky symbolů, nepoužité sekce vypuštěné;
            # x86_64, arm64 a riscv64 jako PIE (-p) bez absolutních relokací
            # (jádro volí náhodnou bázi), i386 a arm bez PIE (kód adresuje
            # symboly absolutně, movw/movt).
            flags = ["-a", "-l", "-p", "-t", BUILTIN_ASSEMBLER[name]]
        end
        call invoke(backend, tool_arguments(flags, [], inputs), "LuxIR backend")
        result = readbytes(path)
    else:
        failure = last_error()
    end
    call cleanup(path)
    if failure != None:
        Error(CompileError: failure)
    end
    return result
end
