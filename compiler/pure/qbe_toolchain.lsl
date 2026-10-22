# Sestavení nativního obrazu přes backend LuxIR. Program nemá C runtime.
load qbe_emit
load host

# Cíl backendu podle platformy LSL.
BACKEND_TARGETS = {"linux-x86_64":"amd64_sysv","linux-arm64":"arm64","linux-riscv64":"rv64","windows-x86_64":"amd64_win","windows-arm64":"arm64_win","macos-x86_64":"amd64_apple","macos-arm64":"arm64_apple","wasm32-wasi":"wasm32","wasm32-wasi-threads":"wasm32","baremetal-riscv64":"rv64","linux-arm":"arm","linux-x86":"i386"}
# Nástroje a příznaky cíle: cross assembler a linker, jinak nativní. rv64:
# adresy symbolů relativně k PC (-p) a bez relaxace linkeru (runtime
# nenastavuje gp).
BACKEND_FLAGS = {"linux-x86_64":[],"linux-arm64":[],"linux-riscv64":["-p"],"windows-x86_64":[],"windows-arm64":[],"macos-x86_64":[],"macos-arm64":[],"wasm32-wasi":[],"wasm32-wasi-threads":["-g"],"baremetal-riscv64":["-p"],"linux-arm":[],"linux-x86":[]}
ASSEMBLERS = {"linux-x86_64":["/usr/bin/as","/bin/as",["--64"]],"linux-x86":["/usr/bin/as","/bin/as",["--32"]],"linux-arm":["/usr/bin/arm-linux-gnueabihf-as","/usr/bin/as",["-march=armv7-a","-mfpu=vfpv3-d16","-mfloat-abi=hard"]],"linux-arm64":["/usr/bin/aarch64-linux-gnu-as","/usr/bin/as",[]],"linux-riscv64":["/usr/bin/riscv64-linux-gnu-as","/usr/bin/as",["-march=rv64gc"]],"windows-x86_64":["/usr/bin/x86_64-w64-mingw32-as","/usr/bin/x86_64-w64-mingw32-as",[]],"windows-arm64":["/usr/bin/clang","/usr/local/bin/clang",["--target=aarch64-windows-gnu","-c","-x","assembler"]],"macos-x86_64":["/usr/bin/clang","/usr/local/bin/clang",["-target","x86_64-apple-macos11","-c","-x","assembler"]],"macos-arm64":["/usr/bin/clang","/usr/local/bin/clang",["-target","arm64-apple-macos11","-c","-x","assembler"]]}
LINKERS = {"linux-x86_64":["/usr/bin/ld","/bin/ld",[]],"linux-arm64":["/usr/bin/aarch64-linux-gnu-ld","/usr/bin/ld",[]],"linux-riscv64":["/usr/bin/riscv64-linux-gnu-ld","/usr/bin/ld",["--no-relax"]],"windows-x86_64":["/usr/bin/x86_64-w64-mingw32-ld","/usr/bin/x86_64-w64-mingw32-ld",["-nostdlib"]],"windows-arm64":["/usr/bin/ld.lld","/usr/local/bin/ld.lld",["-m","arm64pe"]],"macos-x86_64":["/usr/bin/ld64.lld","/usr/local/bin/ld64.lld",["-arch","x86_64","-platform_version","macos","11.0","11.0"]],"macos-arm64":["/usr/bin/ld64.lld","/usr/local/bin/ld64.lld",["-arch","arm64","-platform_version","macos","11.0","11.0"]],"linux-arm":["/usr/bin/arm-linux-gnueabihf-ld","/usr/bin/ld",["-m","armelf_linux_eabi"]],"linux-x86":["/usr/bin/ld","/bin/ld",["-m","elf_i386"]]}
RUNTIME_OBJECTS = {"linux-x86_64":"runtime.o","linux-arm64":"runtime-linux-arm64.o","linux-riscv64":"runtime-linux-riscv64.o","windows-x86_64":"runtime-windows-x86_64.o","windows-arm64":"runtime-windows-arm64.o","macos-x86_64":"runtime-macos-x86_64.o","macos-arm64":"runtime-macos-arm64.o","wasm32-wasi":"runtime-wasm32-wasi.lir","wasm32-wasi-threads":"runtime-wasm32-wasi.lir","baremetal-riscv64":"runtime-baremetal-riscv64.o","linux-arm":"runtime-linux-arm.o","linux-x86":"runtime-linux-x86.o"}
# Windows: importní knihovny Win32 (kernel32, WaitOnAddress, BCryptGenRandom,
# Winsock): x86_64 z mingw-w64, arm64 vyrobené při sestavení runtime
# (tools/runtime/build.py) vedle objektu runtime.
WINDOWS_LIBRARIES = "/usr/x86_64-w64-mingw32/lib"

# Křížové binutils pro cíle ELF (prefix GNU triple).
CROSS_PREFIXES = {"linux-x86_64":"x86_64-linux-gnu-","linux-x86":"i686-linux-gnu-","linux-arm":"arm-linux-gnueabihf-","linux-arm64":"aarch64-linux-gnu-","linux-riscv64":"riscv64-linux-gnu-"}
# Systémový prefix Termuxu (Android); tam jsou nativní binutils místo /usr/bin.
TERMUX_BIN = "/data/data/com.termux/files/usr/bin/"

# Assembler nebo linker pro cíl. Cíl ELF stejné architektury jako hostitel
# používá nativní binutils (/usr/bin, /bin, Termux); jiná architektura jen
# křížové binutils s prefixem, nikdy nativní nástroj jiné architektury.
# Ostatní cíle mají nástroje nezávislé na hostiteli (tabulka).
function binutils_tool(name, tool, table, label):
    if name in CROSS_PREFIXES:
        prefix = CROSS_PREFIXES[name]
        # binutils x86_64 sestaví i 32bitový x86 (--32, -m elf_i386)
        native = name == host.target_name() or (name == "linux-x86" and host.target_name() == "linux-x86_64")
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
        if native:
            Error(ProcessError: "trusted " + label + " executable is required (GNU binutils: " + tool + ")")
        end
        Error(ProcessError: "trusted " + label + " executable is required for target " + name + " (cross binutils: " + prefix + tool + ")")
    end
    return host.required_system_tool(table[name][0], table[name][1], label)
end

# Triple pro llvm-mc a clang (assembler na Windows a macOS).
TRIPLES = {"linux-x86_64":"x86_64-linux-gnu","linux-x86":"i686-linux-gnu","linux-arm":"armv7a-linux-gnueabihf","linux-arm64":"aarch64-linux-gnu","linux-riscv64":"riscv64-linux-gnu","windows-x86_64":"x86_64-w64-windows-gnu","windows-arm64":"aarch64-w64-windows-gnu","macos-x86_64":"x86_64-apple-macos11","macos-arm64":"arm64-apple-macos11"}
# Hostitel Windows: assembler a linker LLVM dodané v balíku vedle překladače.
WINDOWS_TOOLS = ["llvm-mc.exe", "lld.exe"]
# Hostitel macOS: LLVM z Homebrew pro cíle mimo macOS (volitelné).
HOMEBREW_LLVM = ["/opt/homebrew/opt/llvm/bin/", "/usr/local/opt/llvm/bin/"]

function host_os():
    name = host.target_name()
    if name.startswith("windows-"):
        return "windows"
    elif name.startswith("macos-"):
        return "macos"
    end
    return "linux"
end

# Nástroj LLVM dodaný vedle překladače (hostitel Windows).
function bundled_tool(name):
    path = host.tool_path(host.resource_path("bin/" + name), name)
    if not exists(path):
        Error(ProcessError: "LLVM tool is missing beside the compiler: " + name + " (reinstall the LSL package)")
    end
    return path
end

function homebrew_tool(name, label):
    for directory in HOMEBREW_LLVM:
        if exists(directory + name):
            return directory + name
        end
    end
    Error(ProcessError: "trusted " + label + " executable is required (install LLVM: brew install llvm)")
end

# Příznaky linkeru LLVM lld (hostitel Windows nebo LLVM na macOS): flavor
# podle formátu obrazu a stroj PE.
function lld_flavor(name):
    if name.startswith("macos-"):
        return ["-flavor", "darwin"]
    elif name == "windows-x86_64":
        return ["-flavor", "gnu", "-m", "i386pep"]
    elif name == "windows-arm64":
        return ["-flavor", "gnu", "-m", "arm64pe"]
    end
    return ["-flavor", "gnu"]
end

# Cíle, které LuxIR sestaví i slinkuje sám (luxir -a, luxir -l): ELF
# x86-64, i386, arm, arm64, riscv64 a obraz bare metal RISC-V. Nepotřebují
# binutils.
BUILTIN_ASSEMBLER = {"linux-x86_64":"amd64_sysv","linux-x86":"i386","linux-arm64":"arm64","linux-riscv64":"rv64","linux-arm":"arm","baremetal-riscv64":"rv64"}

# [assembler, příznaky před -o]: vestavěný assembler LuxIR pro ELF x86,
# jinak podle hostitele (viz binutils_tool).
function assembler_command(name, backend):
    if name in BUILTIN_ASSEMBLER:
        return [backend, ["-a", "-t", BUILTIN_ASSEMBLER[name]]]
    end
    system = host_os()
    riscv = name == "linux-riscv64"
    if system == "windows":
        flags = ["-filetype=obj", "-triple=" + TRIPLES[name]]
        if riscv:
            # RV64GC s ABI lp64d jako runtime (GNU as -march=rv64gc).
            flags = ["-filetype=obj", "-triple=" + TRIPLES[name], "-mattr=+m,+a,+f,+d,+c,+zicsr,+zifencei", "-target-abi=lp64d"]
        end
        return [bundled_tool("llvm-mc.exe"), flags]
    elif system == "macos":
        flags = ["-target", TRIPLES[name], "-c", "-x", "assembler"]
        if riscv:
            flags = ["-target", TRIPLES[name], "-march=rv64gc", "-mabi=lp64d", "-c", "-x", "assembler"]
        end
        return [host.required_system_tool("/usr/bin/clang", "/Library/Developer/CommandLineTools/usr/bin/clang", "assembler (xcode-select --install)"), flags]
    end
    return [binutils_tool(name, "as", ASSEMBLERS, "assembler"), ASSEMBLERS[name][2]]
end

# [linker, příznaky cíle]: Linux binutils/lld podle tabulky, Windows lld
# z balíku, macOS ld (Xcode) pro macOS, jinak lld z Homebrew. Příznaky jdou
# na začátek příkazu (lld vyžaduje -flavor jako první argument).
function linker_command(name):
    system = host_os()
    if system == "windows":
        return [bundled_tool("lld.exe"), tool_arguments(lld_flavor(name), linker_target_flags(name), [])]
    elif system == "macos":
        if name.startswith("macos-"):
            return [host.required_system_tool("/usr/bin/ld", "/Library/Developer/CommandLineTools/usr/bin/ld", "linker (xcode-select --install)"), LINKERS[name][2]]
        end
        lld = homebrew_tool("lld", "linker")
        return [lld, tool_arguments(lld_flavor(name), linker_target_flags(name), [])]
    end
    return [binutils_tool(name, "ld", LINKERS, "linker"), LINKERS[name][2]]
end

# Příznaky cíle bez příznaků, které patří jen GNU ld nebo ld.lld v tabulce
# (stroj PE dodá lld_flavor).
function linker_target_flags(name):
    if name.startswith("windows-"):
        return []
    end
    return LINKERS[name][2]
end

function windows_libraries(name):
    if name == "windows-arm64":
        return host.resource_path("compiler/qbe/windows-arm64")
    end
    # Importní knihovny z balíku (vždy na Windows; na Linuxu bez MinGW).
    bundled = host.resource_path("compiler/qbe/windows-x86_64")
    if host_os() != "linux" or not exists(WINDOWS_LIBRARIES + "/libkernel32.a"):
        return bundled
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
    call unlink(path + ".c")
    call unlink(path + ".c.body")
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
    assembling = assembler_command(name, backend)
    assembler = assembling[0]
    linking = ["", []]
    if name not in BUILTIN_ASSEMBLER:
        linking = linker_command(name)
    end
    linker = linking[0]
    path = host.scratch_program_path()
    failure = None
    result = ByteArray()
    try:
        call qbe_emit.generate(unit, path + ".lir", entry_source)
        if name in BUILTIN_ASSEMBLER:
            # Vestavěný assembler a linker LuxIR v jednom běhu (-a -l):
            # překlad LIR, sestavení a slinkování bez dalších procesů.
            # Statický ELF bez tabulky symbolů, nepoužité sekce vypuštěné;
            # x86_64, arm64 a riscv64 jako PIE (-p) bez absolutních relokací
            # (jádro volí náhodnou bázi), i386 a arm bez PIE (kód adresuje
            # symboly absolutně, movw/movt). Jméno dočasného souboru se do
            # obrazu nedostane (LuxIR připojí .file "luxir").
            flags = ["-a", "-l", "-t", BUILTIN_ASSEMBLER[name]]
            if selected["os"] == "baremetal":
                # Obraz bez OS v rozložení desky (-b místo linker skriptu
                # runtime/arch/baremetal_riscv64.ld): ET_EXEC od RAM, kód
                # s adresami relativně k PC (-p), zásobníky a konec obrazu
                # pro haldu.
                flags = ["-a", "-l", "-b", "-p", "-t", BUILTIN_ASSEMBLER[name]]
            elif name != "linux-x86" and name != "linux-arm":
                flags = ["-a", "-l", "-p", "-t", BUILTIN_ASSEMBLER[name]]
            end
            call invoke(backend, tool_arguments(flags, [], ["-o", path, path + ".lir", runtime]), "LuxIR backend")
        else:
            call invoke(backend, tool_arguments(["-t", BACKEND_TARGETS[name]], BACKEND_FLAGS[name], ["-o", path + ".s", path + ".lir"]), "LuxIR backend")
            # No private scratch filename is embedded in the resulting image.
            call appendfile(path + ".s", chr(10) + ".file \"luxir\"" + chr(10))
            if selected["os"] == "macos":
                # Každý symbol ve vlastní podsekci: -dead_strip zahodí nepoužité.
                call appendfile(path + ".s", ".subsections_via_symbols" + chr(10))
            end
            call invoke(assembler, tool_arguments([], assembling[1], ["-o", path + ".o", path + ".s"]), "assembler")
            if selected["os"] == "macos":
                # Mach-O spustitelný soubor (PIE, na arm64 s ad-hoc podpisem od
                # ld64.lld) dynamicky linkovaný s libSystem: macOS nepodporuje
                # statické programy ani přímá systémová volání. libSystem.tbd je
                # textový stub, takže se linkuje bez SDK.
                call invoke(linker, tool_arguments(linking[1], [], ["-dead_strip", "-x", "-o", path, path + ".o", runtime, host.resource_path("compiler/qbe/libSystem.tbd")]), "linker")
            elif selected["os"] == "windows":
                # PE konzolový program s ASLR a DEP. Zásobník hlavního vlákna je
                # celý zpřístupněný (8 MiB jako na Linuxu): LuxIR na Windows
                # nesonduje zásobník po stránkách. Bez časového razítka, aby
                # obraz byl reprodukovatelný.
                call invoke(linker, tool_arguments(linking[1], ["-e", "_start", "--subsystem", "console", "--dynamicbase", "--high-entropy-va", "--nxcompat", "--stack", "8388608,8388608", "--no-insert-timestamp", "--gc-sections", "-s"], ["-o", path, path + ".o", runtime, "-L" + windows_libraries(name), "-lkernel32", "-lsynchronization", "-lbcrypt", "-lws2_32"]), "linker")
            elif selected["image_format"] == "elf32-linux":
                # 32bitový cíl: statický obraz ELF bez PIE (arm adresuje
                # symboly absolutně, movw/movt).
                call invoke(linker, tool_arguments(linking[1], ["-nostdlib", "-static", "-z", "noexecstack", "--build-id=none", "--gc-sections", "-s"], ["-o", path, path + ".o", runtime]), "linker")
            else:
                # All runtime/code references are PC relative. -z text makes absolute
                # relocations in executable pages a hard error instead of weakening PIE.
                call invoke(linker, tool_arguments(linking[1], ["-nostdlib", "-static", "-pie", "--no-dynamic-linker", "-z", "text", "-z", "noexecstack", "--build-id=none", "--gc-sections", "-s"], ["-o", path, path + ".o", runtime]), "linker")
            end
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
