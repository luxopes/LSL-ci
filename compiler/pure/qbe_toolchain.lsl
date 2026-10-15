# Sestavení nativního obrazu přes backend LuxIR. Program nemá C runtime.
load qbe_emit
load host

# Cíl backendu podle platformy LSL.
BACKEND_TARGETS = {"linux-x86_64":"amd64_sysv","linux-arm64":"arm64","linux-riscv64":"rv64","windows-x86_64":"amd64_win","windows-arm64":"arm64_win","macos-x86_64":"amd64_apple","macos-arm64":"arm64_apple","wasm32-wasi":"wasm32","wasm32-wasi-threads":"wasm32","baremetal-riscv64":"rv64"}
# Nástroje a příznaky cíle: cross assembler a linker, jinak nativní. rv64:
# adresy symbolů relativně k PC (-p) a bez relaxace linkeru (runtime
# nenastavuje gp).
BACKEND_FLAGS = {"linux-x86_64":[],"linux-arm64":[],"linux-riscv64":["-p"],"windows-x86_64":[],"windows-arm64":[],"macos-x86_64":[],"macos-arm64":[],"wasm32-wasi":[],"wasm32-wasi-threads":["-g"],"baremetal-riscv64":["-p"]}
ASSEMBLERS = {"linux-x86_64":["/usr/bin/as","/bin/as",["--64"]],"linux-arm64":["/usr/bin/aarch64-linux-gnu-as","/usr/bin/as",[]],"linux-riscv64":["/usr/bin/riscv64-linux-gnu-as","/usr/bin/as",["-march=rv64gc"]],"windows-x86_64":["/usr/bin/x86_64-w64-mingw32-as","/usr/bin/x86_64-w64-mingw32-as",[]],"windows-arm64":["/usr/bin/clang","/usr/local/bin/clang",["--target=aarch64-windows-gnu","-c","-x","assembler"]],"macos-x86_64":["/usr/bin/clang","/usr/local/bin/clang",["-target","x86_64-apple-macos11","-c","-x","assembler"]],"macos-arm64":["/usr/bin/clang","/usr/local/bin/clang",["-target","arm64-apple-macos11","-c","-x","assembler"]],"baremetal-riscv64":["/usr/bin/riscv64-linux-gnu-as","/usr/bin/riscv64-unknown-elf-as",["-march=rv64gc"]]}
LINKERS = {"linux-x86_64":["/usr/bin/ld","/bin/ld",[]],"linux-arm64":["/usr/bin/aarch64-linux-gnu-ld","/usr/bin/ld",[]],"linux-riscv64":["/usr/bin/riscv64-linux-gnu-ld","/usr/bin/ld",["--no-relax"]],"windows-x86_64":["/usr/bin/x86_64-w64-mingw32-ld","/usr/bin/x86_64-w64-mingw32-ld",["-nostdlib"]],"windows-arm64":["/usr/bin/ld.lld","/usr/local/bin/ld.lld",["-m","arm64pe"]],"macos-x86_64":["/usr/bin/ld64.lld","/usr/local/bin/ld64.lld",["-arch","x86_64","-platform_version","macos","11.0","11.0"]],"macos-arm64":["/usr/bin/ld64.lld","/usr/local/bin/ld64.lld",["-arch","arm64","-platform_version","macos","11.0","11.0"]],"baremetal-riscv64":["/usr/bin/riscv64-linux-gnu-ld","/usr/bin/riscv64-unknown-elf-ld",["--no-relax"]]}
RUNTIME_OBJECTS = {"linux-x86_64":"runtime.o","linux-arm64":"runtime-linux-arm64.o","linux-riscv64":"runtime-linux-riscv64.o","windows-x86_64":"runtime-windows-x86_64.o","windows-arm64":"runtime-windows-arm64.o","macos-x86_64":"runtime-macos-x86_64.o","macos-arm64":"runtime-macos-arm64.o","wasm32-wasi":"runtime-wasm32-wasi.lir","wasm32-wasi-threads":"runtime-wasm32-wasi.lir","baremetal-riscv64":"runtime-baremetal-riscv64.o"}
# Windows: importní knihovny Win32 (kernel32, WaitOnAddress, BCryptGenRandom,
# Winsock): x86_64 z mingw-w64, arm64 vyrobené při sestavení runtime
# (tools/runtime/build.py) vedle objektu runtime.
WINDOWS_LIBRARIES = "/usr/x86_64-w64-mingw32/lib"

# Křížové binutils pro cíle ELF (prefix GNU triple).
CROSS_PREFIXES = {"linux-x86_64":"x86_64-linux-gnu-","linux-arm64":"aarch64-linux-gnu-","linux-riscv64":"riscv64-linux-gnu-","baremetal-riscv64":"riscv64-linux-gnu-"}
# Systémový prefix Termuxu (Android); tam jsou nativní binutils místo /usr/bin.
TERMUX_BIN = "/data/data/com.termux/files/usr/bin/"

# Assembler nebo linker pro cíl. Cíl ELF stejné architektury jako hostitel
# používá nativní binutils (/usr/bin, /bin, Termux); jiná architektura jen
# křížové binutils s prefixem, nikdy nativní nástroj jiné architektury.
# Ostatní cíle mají nástroje nezávislé na hostiteli (tabulka).
function binutils_tool(name, tool, table, label):
    if name in CROSS_PREFIXES:
        prefix = CROSS_PREFIXES[name]
        native = name == host.target_name() or (name == "baremetal-riscv64" and host.target_name() == "linux-riscv64")
        if native:
            for candidate in ["/usr/bin/" + tool, "/bin/" + tool, TERMUX_BIN + tool]:
                if exists(candidate):
                    return candidate
                end
            end
        end
        for candidate in ["/usr/bin/" + prefix + tool, "/usr/local/bin/" + prefix + tool]:
            if exists(candidate):
                return candidate
            end
        end
        if name == "baremetal-riscv64":
            for candidate in ["/usr/bin/riscv64-unknown-elf-" + tool, "/usr/local/bin/riscv64-unknown-elf-" + tool]:
                if exists(candidate):
                    return candidate
                end
            end
        end
        if native:
            Error(ProcessError: "trusted " + label + " executable is required (GNU binutils: " + tool + ")")
        end
        Error(ProcessError: "trusted " + label + " executable is required for target " + name + " (cross binutils: " + prefix + tool + ")")
    end
    return host.required_system_tool(table[name][0], table[name][1], label)
end

function windows_libraries(name):
    if name == "windows-arm64":
        return host.resource_path("compiler/qbe/windows-arm64")
    end
    return WINDOWS_LIBRARIES
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
    call unlink(path + ".lir.phase")
    call unlink(path + ".lir")
    call unlink(path + ".s")
    call unlink(path + ".o")
    call host.cleanup_program(path)
end

# WebAssembly: runtime (LIR) a program se přeloží spolu do jednoho modulu
# (luxir -t wasm32, s vlákny -g), vrstva architektury je text WAT (s vlákny
# wasi_wasm32_threads.wat) a binární modul vyrobí
# wat2wasm (WABT). Linker ani assembler se nepoužijí.
function wasm_image(unit, selected, entry_source, backend):
    converter = host.required_system_tool("/usr/bin/wat2wasm", "/usr/local/bin/wat2wasm", "WebAssembly text converter (wat2wasm)")
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
        call invoke(backend, tool_arguments(["-t", "wasm32"], BACKEND_FLAGS[selected["name"]], ["-o", path + ".body", path + ".all.lir"]), "LuxIR backend")
        call writefile(path + ".wat", "(module" + chr(10) + readfile(layer) + chr(10) + readfile(path + ".body") + ")" + chr(10))
        features = []
        if selected["name"] == "wasm32-wasi-threads":
            features = ["--enable-threads"]
        end
        call invoke(converter, tool_arguments(features, [], ["-o", path, path + ".wat"]), "wat2wasm")
        result = readbytes(path)
    else:
        failure = last_error()
    end
    call unlink(path + ".all.lir")
    call unlink(path + ".body")
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
    if selected["os"] == "wasi":
        backend = backend_path
        if backend == "":
            backend = native_backend_path()
        end
        return wasm_image(unit, selected, entry_source, backend)
    end
    backend = backend_path
    if backend == "":
        backend = native_backend_path()
    end
    name = selected["name"]
    runtime = runtime_path(selected)
    assembler = binutils_tool(name, "as", ASSEMBLERS, "assembler")
    linker = binutils_tool(name, "ld", LINKERS, "linker")
    path = host.scratch_program_path()
    failure = None
    result = ByteArray()
    try:
        call qbe_emit.generate(unit, path + ".lir", entry_source)
        call invoke(backend, tool_arguments(["-t", BACKEND_TARGETS[name]], BACKEND_FLAGS[name], ["-o", path + ".s", path + ".lir"]), "LuxIR backend")
        # No private scratch filename is embedded in the resulting image.
        call appendfile(path + ".s", chr(10) + ".file \"luxir\"" + chr(10))
        if selected["os"] == "macos":
            # Každý symbol ve vlastní podsekci: -dead_strip zahodí nepoužité.
            call appendfile(path + ".s", ".subsections_via_symbols" + chr(10))
        end
        call invoke(assembler, tool_arguments([], ASSEMBLERS[name][2], ["-o", path + ".o", path + ".s"]), "assembler")
        if selected["os"] == "macos":
            # Mach-O spustitelný soubor (PIE, na arm64 s ad-hoc podpisem od
            # ld64.lld) dynamicky linkovaný s libSystem: macOS nepodporuje
            # statické programy ani přímá systémová volání. libSystem.tbd je
            # textový stub, takže se linkuje bez SDK.
            call invoke(linker, tool_arguments([], LINKERS[name][2], ["-dead_strip", "-x", "-o", path, path + ".o", runtime, host.resource_path("compiler/qbe/libSystem.tbd")]), "linker")
        elif selected["os"] == "windows":
            # PE konzolový program s ASLR a DEP. Zásobník hlavního vlákna je
            # celý zpřístupněný (8 MiB jako na Linuxu): LuxIR na Windows
            # nesonduje zásobník po stránkách. Bez časového razítka, aby
            # obraz byl reprodukovatelný.
            call invoke(linker, tool_arguments(["-e", "_start", "--subsystem", "console", "--dynamicbase", "--high-entropy-va", "--nxcompat", "--stack", "8388608,8388608", "--no-insert-timestamp", "--gc-sections", "-s"], LINKERS[name][2], ["-o", path, path + ".o", runtime, "-L" + windows_libraries(name), "-lkernel32", "-lsynchronization", "-lbcrypt", "-lws2_32"]), "linker")
        elif selected["os"] == "baremetal":
            # Statický obraz ELF bez OS podle linker skriptu desky (adresy,
            # zásobník, konec obrazu pro haldu).
            call invoke(linker, tool_arguments(["-nostdlib", "-static", "-T", host.resource_path("runtime/arch/baremetal_riscv64.ld"), "--build-id=none", "--gc-sections", "-s"], LINKERS[name][2], ["-o", path, path + ".o", runtime]), "linker")
        else:
            # All runtime/code references are PC relative. -z text makes absolute
            # relocations in executable pages a hard error instead of weakening PIE.
            call invoke(linker, tool_arguments(["-nostdlib", "-static", "-pie", "--no-dynamic-linker", "-z", "text", "-z", "noexecstack", "--build-id=none", "--gc-sections", "-s"], LINKERS[name][2], ["-o", path, path + ".o", runtime]), "linker")
        end
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
