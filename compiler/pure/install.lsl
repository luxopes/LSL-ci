# Pure-LSL installer. No shell, cp, libc, or foreign build tool.

function dirname(path):
    slash = -1
    index = 0
    while index < len(path):
        if path[index] == "/":
            slash = index
        end
        index += 1
    end
    if slash < 0:
        return "."
    elif slash == 0:
        return "/"
    end
    return path[0:slash]
end

function source_root():
    executable = executable_path()
    binary_directory = dirname(executable)
    repository = dirname(dirname(dirname(executable)))
    if exists(repository + "/compiler/pure/install.lsl"):
        return repository
    end
    prefix = dirname(binary_directory)
    prefix_bin = prefix + "/bin"
    if prefix == "/":
        prefix_bin = "/bin"
    end
    if binary_directory == prefix_bin:
        # Preserve the trusted prefix even if the installation is incomplete;
        # subsequent reads fail instead of falling back to the caller's cwd.
        return prefix + "/lib/lsl"
    end
    # Development-only fallback for an installer freshly compiled outside the
    # repository. Real repository and installed binaries always resolve above.
    return "."
end

SOURCE_ROOT = source_root()

function source_path(relative):
    return SOURCE_ROOT + "/" + relative
end

function executable_source(relative, installed_name):
    repository = source_path(relative)
    if exists(repository):
        return repository
    end
    adjacent = dirname(executable_path()) + "/" + installed_name
    if exists(adjacent):
        return adjacent
    end
    return repository
end

function copy_text(source, destination):
    call writefile(destination, readfile(source))
end

function copy_executable(source, destination):
    call writebytes(destination, readbytes(source))
end

prefix = arg(1)
if prefix == None:
    prefix = "/usr/local"
end
if type(prefix) != "String" or len(prefix) == 0 or __lsl_text_byte_length(String(prefix)) > 4095 or not prefix.startswith("/") or chr(0) in prefix:
    Error(InstallError: "installation prefix must be an absolute path without NUL")
end
for component in prefix.split("/"):
    if component == "..":
        Error(InstallError: "installation prefix must not contain parent traversal")
    end
end

call mkdir(prefix)
call mkdir(prefix + "/bin")
call mkdir(prefix + "/lib")
call mkdir(prefix + "/lib/lsl")
call mkdir(prefix + "/lib/lsl/compiler")
call mkdir(prefix + "/lib/lsl/compiler/pure")
call mkdir(prefix + "/lib/lsl/stdlib")

call copy_executable(executable_source("compiler/pure/lsl-cli", "lsl"), prefix + "/bin/lsl")
call copy_executable(executable_source("compiler/pure/lslc-direct", "lslc"), prefix + "/bin/lslc")
call copy_executable(executable_source("compiler/pure/lsl-configure", "lsl-configure"), prefix + "/bin/lsl-configure")
call copy_executable(executable_source("tests/lsl-test", "lsl-test"), prefix + "/bin/lsl-test")
call copy_executable(executable_source("compiler/pure/lsl-install", "lsl-install"), prefix + "/bin/lsl-install")
cuda_worker = executable_source("cuda/lsl-cuda-worker", "lsl-cuda-worker")
if exists(cuda_worker):
    call copy_executable(cuda_worker, prefix + "/bin/lsl-cuda-worker")
end

sources = [
    "assembler.lsl",
    "bytes.lsl",
    "cli.lsl",
    "codegen.lsl",
    "diagnostics.lsl",
    "dynamic_stdlib.lsl",
    "elf_image.lsl",
    "heap_runtime.lsl",
    "install.lsl",
    "io_runtime.lsl",
    "lexer.lsl",
    "linker.lsl",
    "lslc_direct.lsl",
    "native_runtime.lsl",
    "native_plugin_runtime.lsl",
    "package.lsl",
    "parser.lsl",
    "process_runtime.lsl",
    "thread_runtime.lsl",
    "update.lsl",
    "update_install.lsl",
    "x86_64.lsl"
]
for name in sources:
    call copy_text(source_path("compiler/pure/" + name), prefix + "/lib/lsl/compiler/pure/" + name)
end

standard_modules = ["ai.lsl", "bigint.lsl", "config.lsl", "configure.lsl", "css.lsl", "cuda.lsl", "display.lsl", "env.lsl", "fd.lsl", "gfx.lsl", "http.lsl", "httpserver.lsl", "input.lsl", "json.lsl", "lconf.lsl", "lux.lsl", "luxos.lsl", "math.lsl", "native.lsl", "os.lsl", "plugin.lsl", "process.lsl", "sandbox.lsl", "system.lsl", "tensor.lsl", "time.lsl", "tui.lsl", "ui.lsl", "unixsock.lsl", "wayland.lsl", "x11.lsl"]
for name in standard_modules:
    call copy_text(source_path("stdlib/" + name), prefix + "/lib/lsl/stdlib/" + name)
end

print "installed pure LSL into", prefix
