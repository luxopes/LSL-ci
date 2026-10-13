# Sestavení nativního obrazu přes backend LuxIR. Program nemá C runtime.
load qbe_emit
load host

# Cíl backendu podle platformy LSL.
BACKEND_TARGETS = {"linux-x86_64":"amd64_sysv"}

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

function runtime_path():
    path = host.resource_path("compiler/qbe/runtime.o")
    if exists(path):
        return path
    end
    path = host.resource_path("build/qbe/runtime.o")
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

function cleanup(path):
    call unlink(path + ".lir.phase")
    call unlink(path + ".lir")
    call unlink(path + ".s")
    call unlink(path + ".o")
    call host.cleanup_program(path)
end

function image(unit, selected, entry_source="", backend_path=""):
    if selected["name"] not in BACKEND_TARGETS:
        Error(CompileError: "native runtime is not implemented for: " + selected["name"])
    end
    backend = backend_path
    if backend == "":
        backend = native_backend_path()
    end
    runtime = runtime_path()
    assembler = host.required_system_tool("/usr/bin/as", "/bin/as", "assembler")
    linker = host.required_system_tool("/usr/bin/ld", "/bin/ld", "linker")
    path = host.scratch_program_path()
    failure = None
    result = ByteArray()
    try:
        call qbe_emit.generate(unit, path + ".lir", entry_source)
        call invoke(backend, ["-t", BACKEND_TARGETS[selected["name"]], "-o", path + ".s", path + ".lir"], "LuxIR backend")
        # No private scratch filename is embedded in the resulting image.
        call appendfile(path + ".s", chr(10) + ".file \"luxir\"" + chr(10))
        call invoke(assembler, ["--64", "-o", path + ".o", path + ".s"], "assembler")
        # All runtime/code references are PC relative. -z text makes absolute
        # relocations in executable pages a hard error instead of weakening PIE.
        call invoke(linker, ["-nostdlib", "-static", "-pie", "--no-dynamic-linker", "-z", "text", "-z", "noexecstack", "--build-id=none", "--gc-sections", "-s", "-o", path, path + ".o", runtime], "linker")
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
