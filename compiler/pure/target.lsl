# Registry cílových komponent. Neimplementovaný port není dostupný cíl překladu.

# Poskytovatelé platformy: modul konstant je pro každou architekturu vlastní,
# ostatní poskytovatelé daného OS jsou na architektuře nezávislí (konstanty
# berou z _platform), proto zůstávají společné.
function provider_modules(os, architecture="x86_64"):
    suffix = os + "_x86_64"
    result = {"_platform": "_platform_" + os + "_" + architecture}
    for name in ["fd", "unixsock", "random", "tui", "system", "os", "sandbox", "luxos", "plugin", "native"]:
        result["_" + name + "_platform"] = "_" + name + "_" + suffix
    end
    result["_httpserver_transport"] = "_httpserver_" + suffix
    result["_cuda_transport"] = "_cuda_" + suffix
    result["_ai_platform"] = "_ai_" + suffix
    # Vrstvy OS runtime (runtime/os_<os>.lsl, runtime/ffi_<os>.lsl).
    result["_runtime_os"] = "os_" + os
    result["_runtime_ffi"] = "ffi_" + os
    result["_compiler_host_platform"] = "host_" + suffix
    result["_host_platform"] = "_host_" + suffix
    for name in ["update", "update_install", "catalog", "package", "install"]:
        result["_" + name + "_platform"] = name + "_" + suffix
    end
    return result
end

function describe(name):
    os = ""
    format = ""
    available = False
    architecture = "x86_64"
    backend = "x86_64"
    if name == "linux-x86_64":
        os = "linux"
        format = "elf64-linux"
        available = True
    elif name == "linux-arm64":
        os = "linux"
        format = "elf64-linux"
        architecture = "arm64"
        backend = "arm64"
        available = True
    elif name == "linux-riscv64":
        os = "linux"
        format = "elf64-linux"
        architecture = "riscv64"
        backend = "rv64"
        available = True
    elif name == "windows-x86_64":
        os = "windows"
        format = "pe32plus-windows"
        available = True
    elif name == "macos-x86_64":
        os = "macos"
        format = "mach64-macos"
        available = True
    elif name == "macos-arm64":
        os = "macos"
        format = "mach64-macos"
        architecture = "arm64"
        backend = "arm64"
        available = True
    else:
        Error(CompileError: "unsupported compilation target: " + String(name))
    end
    selected = {"name": name, "abi": "lsl-" + architecture + "-v1", "backend": backend, "runtime": "lsl-runtime-" + name + "-v1", "platform_module": "_platform_" + os + "_" + architecture, "os": os, "architecture": architecture, "pointer_bytes": 8, "byte_order": "little", "image_format": format, "available": available, "modules": provider_modules(os, architecture)}
    if os == "linux":
        selected["elf_machine"] = {"x86_64": 62, "arm64": 183, "riscv64": 243}[architecture]
        selected["segment_alignment"] = 4096
    end
    return selected
end

function resolve(name):
    selected = describe(name)
    if not selected["available"]:
        Error(CompileError: "compilation target is not implemented: " + String(name) + " (runtime, image writer and platform providers)")
    end
    return selected
end

function modules_for_platform(platform_module):
    for name in ["linux-x86_64", "linux-arm64", "linux-riscv64", "windows-x86_64", "macos-x86_64", "macos-arm64"]:
        selected = describe(name)
        if selected["platform_module"] == platform_module:
            return selected["modules"]
        end
    end
    Error(CompileError: "unsupported target platform module: " + String(platform_module))
end

function builtin_provider(name):
    for os in ["linux", "windows", "macos"]:
        for architecture in ["x86_64", "arm64", "riscv64"]:
            modules = provider_modules(os, architecture)
            for alias in modules:
                module = modules[alias]
                if module.startswith("_") and name == alias:
                    return True
                end
                # Nástroje compileru mají vlastní provenance a nejsou veřejné stdlib.
                if module.startswith("_") and name == module:
                    return True
                end
            end
        end
    end
    return False
end
