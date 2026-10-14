# Pure-LSL installer. Copies trusted native tools/resources using syscalls.
load fd
load update_install

# A downloaded installer can repair an older self-updater without writing
# through prefix/bin symlinks into the active generation. Retain rollback.
function reinstall_managed(prefix):
    call update_install.installation(prefix + "/bin/lsl", __lsl_getenv("HOME"), prefix == "/usr/local")
    store = prefix + "/lib/lsl-updates"
    call update_install.directory(store)
    call update_install.directory(store + "/generations")
    call update_install.public_directory(store)
    call update_install.public_directory(store + "/generations")
    handle = update_install.lock(store)
    work = update_install.private_work(store)
    failure = None
    try:
        call update_install.recover(store, work)
        if update_install.metadata(store + "/current") == None:
            previous_version = update_install.bounded(prefix + "/bin/lsl", ["version"], 1048576, 30).strip()
            call update_install.health(prefix, previous_version, work)
        else:
            active = update_install.target(store, "current")
            previous_version = fd.read_text_limit(active + "/version", 64).strip()
            call update_install.health(active, previous_version, work)
        end
        generation = update_install.private_work(store + "/generations")
        call update_install.install_stage(executable_path(), generation, "0.9.2", work)
        call update_install.prepare(prefix, prefix + "/bin/lsl", previous_version, work)
        call update_install.activate(store, generation, "0.9.2", work)
    else:
        failure = last_error()
    end
    cleanup_failure = None
    try:
        call update_install.cleanup_scratch(work)
    else:
        cleanup_failure = last_error()
    end
    call fd.close(handle)
    if failure != None:
        Error(InstallError: String(failure))
    elif cleanup_failure != None:
        Error(InstallError: String(cleanup_failure))
    end
    print "Installed LSL 0.9.2 atomically; previous version retained for rollback."
end

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
    candidate_prefix = dirname(binary_directory)
    candidate_bin = candidate_prefix + "/bin"
    if candidate_prefix == "/":
        candidate_bin = "/bin"
    end
    if binary_directory == candidate_bin:
        # Preserve the trusted prefix even if the installation is incomplete;
        # subsequent reads fail instead of falling back to the caller's cwd.
        return candidate_prefix + "/lib/lsl"
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

# Installation progress: an in-place percentage on a terminal, or plain
# "progress NN" lines when captured (lsl update relays them).
function report_progress(done, total):
    percent = min(100, done * 100 // max(1, total))
    if __lsl_isatty(1):
        text = chr(13) + "Installing " + String(percent) + " %"
        if percent >= 100:
            text += chr(10)
        end
        bytes = __lsl_byte_zeros(__lsl_text_byte_length(text))
        for index in rang(len(bytes)):
            bytes[index] = __lsl_text_byte(text, index)
        end
        call __lsl_fd_write(1, bytes, len(bytes))
    elif percent % 10 == 0 or percent == 100:
        print "progress", percent
    end
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

supported_prefix = prefix == "/usr/local" or prefix == String(__lsl_getenv("HOME")) + "/.local"
if update_install.metadata(prefix + "/lib/lsl-updates/current") != None or (supported_prefix and exists(prefix + "/bin/lsl")):
    call reinstall_managed(prefix)
    exit(0)
end

call mkdir(prefix)
call mkdir(prefix + "/bin")
call mkdir(prefix + "/lib")
call mkdir(prefix + "/lib/lsl")
call mkdir(prefix + "/lib/lsl/compiler")
call mkdir(prefix + "/lib/lsl/compiler/pure")
call mkdir(prefix + "/lib/lsl/compiler/qbe")
call mkdir(prefix + "/lib/lsl/stdlib")

executables = [["compiler/pure/lsl-cli", "lsl", "lsl"], ["compiler/pure/lslc-qbe", "lslc", "lslc"], ["build/luxir/luxir", "luxir", "luxir"], ["compiler/pure/lsl-configure", "lsl-configure", "lsl-configure"], ["tests/lsl-test", "lsl-test", "lsl-test"], ["compiler/pure/lsl-install", "lsl-install", "lsl-install"]]
cuda_worker = executable_source("cuda/lsl-cuda-worker", "lsl-cuda-worker")
if exists(cuda_worker):
    executables.append(["cuda/lsl-cuda-worker", "lsl-cuda-worker", "lsl-cuda-worker"])
end

sources = [
    "_catalog_platform.lsl",
    "_compiler_host_platform.lsl",
    "_install_platform.lsl",
    "_package_platform.lsl",
    "_update_install_platform.lsl",
    "_update_platform.lsl",
    "abi_x86_64.lsl",
    "assembler.lsl",
    "assembler_x86_64.lsl",
    "backend_x86_64.lsl",
    "browser.lsl",
    "bytes.lsl",
    "catalog.lsl",
    "catalog_linux_x86_64.lsl",
    "cli.lsl",
    "codegen.lsl",
    "compiler_backend.lsl",
    "console.lsl",
    "declarations.lsl",
    "diagnostics.lsl",
    "dynamic_stdlib.lsl",
    "editor.lsl",
    "elf_image.lsl",
    "flow.lsl",
    "frontend.lsl",
    "heap_runtime.lsl",
    "heap_runtime_linux_x86_64.lsl",
    "highlight.lsl",
    "host.lsl",
    "host_linux_x86_64.lsl",
    "image_elf64_linux.lsl",
    "image_writer.lsl",
    "install.lsl",
    "install_linux_x86_64.lsl",
    "io_runtime.lsl",
    "io_runtime_linux_x86_64.lsl",
    "lexer.lsl",
    "linker.lsl",
    "lslc_qbe.lsl",
    "qbe_emit.lsl",
    "qbe_toolchain.lsl",
    "qbe_runtime_dump.lsl",
    "lslc_direct.lsl",
    "manual.lsl",
    "native_plugin_runtime.lsl",
    "native_plugin_runtime_linux_x86_64.lsl",
    "native_runtime.lsl",
    "native_runtime_linux_x86_64.lsl",
    "object_code.lsl",
    "package.lsl",
    "package_linux_x86_64.lsl",
    "parser.lsl",
    "pipeline.lsl",
    "process_runtime.lsl",
    "process_runtime_linux_x86_64.lsl",
    "relocations_x86_64.lsl",
    "runtime.lsl",
    "runtime_abi_linux_x86_64.lsl",
    "runtime_linux_x86_64.lsl",
    "semantic.lsl",
    "target.lsl",
    "thread_runtime.lsl",
    "thread_runtime_linux_x86_64.lsl",
    "update.lsl",
    "update_install.lsl",
    "update_install_linux_x86_64.lsl",
    "update_linux_x86_64.lsl",
    "validation.lsl",
    "value_abi.lsl",
    "x86_64.lsl"
]
standard_modules = ["_ai_linux_x86_64.lsl", "_ai_macos_x86_64.lsl", "_ai_platform.lsl", "_ai_windows_x86_64.lsl", "_cuda_linux_x86_64.lsl", "_cuda_macos_x86_64.lsl", "_cuda_transport.lsl", "_cuda_windows_x86_64.lsl", "_fd_linux_x86_64.lsl", "_fd_macos_x86_64.lsl", "_fd_platform.lsl", "_fd_windows_x86_64.lsl", "_host_linux_x86_64.lsl", "_host_macos_x86_64.lsl", "_host_platform.lsl", "_host_windows_x86_64.lsl", "_httpserver_linux_x86_64.lsl", "_httpserver_macos_x86_64.lsl", "_httpserver_transport.lsl", "_httpserver_windows_x86_64.lsl", "_luxos_linux_x86_64.lsl", "_luxos_macos_x86_64.lsl", "_luxos_platform.lsl", "_luxos_windows_x86_64.lsl", "_native_linux_x86_64.lsl", "_native_macos_x86_64.lsl", "_native_platform.lsl", "_native_windows_x86_64.lsl", "_os_linux_x86_64.lsl", "_os_macos_x86_64.lsl", "_os_platform.lsl", "_os_windows_x86_64.lsl", "_platform.lsl", "_platform_linux_arm64.lsl", "_platform_linux_riscv64.lsl", "_platform_linux_x86_64.lsl", "_platform_macos_arm64.lsl", "_platform_macos_x86_64.lsl", "_platform_windows_arm64.lsl", "_platform_windows_x86_64.lsl", "_plugin_linux_x86_64.lsl", "_plugin_macos_x86_64.lsl", "_plugin_platform.lsl", "_plugin_windows_x86_64.lsl", "_random_hash.lsl", "_random_linux_x86_64.lsl", "_random_macos_x86_64.lsl", "_random_platform.lsl", "_random_windows_x86_64.lsl", "_sandbox_linux_x86_64.lsl", "_sandbox_macos_x86_64.lsl", "_sandbox_platform.lsl", "_sandbox_windows_x86_64.lsl", "_system_linux_x86_64.lsl", "_system_macos_x86_64.lsl", "_system_platform.lsl", "_system_windows_x86_64.lsl", "_tui_linux_x86_64.lsl", "_tui_macos_x86_64.lsl", "_tui_platform.lsl", "_tui_windows_x86_64.lsl", "_unixsock_linux_x86_64.lsl", "_unixsock_macos_x86_64.lsl", "_unixsock_platform.lsl", "_unixsock_windows_x86_64.lsl", "ai.lsl", "bigint.lsl", "config.lsl", "configure.lsl", "cuda.lsl", "env.lsl", "fd.lsl", "http.lsl", "httpserver.lsl", "json.lsl", "lconf.lsl", "lux.lsl", "luxos.lsl", "math.lsl", "native.lsl", "os.lsl", "plugin.lsl", "process.lsl", "random.lsl", "requests.lsl", "sandbox.lsl", "system.lsl", "tensor.lsl", "time.lsl", "tui.lsl", "unixsock.lsl"]
manual_pages = ["README", "01-getting-started", "02-language-basics", "03-functions-and-classes", "04-collections", "05-error-handling", "06-modules-and-imports", "07-files-io-and-processes", "08-configuration-system", "09-gui-programming", "10-ai-applications", "11-performance-and-optimization", "12-compiler-internals", "13-server-and-origin", "14-sandbox-and-safety", "15-cuda", "16-random", "17-cli-and-packages", "env", "requests", "http", "httpserver", "json", "os", "process", "time", "math", "random", "system", "ai", "bigint", "config", "configure", "lconf", "lux", "luxos", "fd", "native", "plugin", "sandbox", "tensor", "tui", "unixsock", "cuda", "reference", "security", "CHANGELOG"]
call mkdir(prefix + "/lib/lsl/docs")
call mkdir(prefix + "/lib/lsl/docs/developer_guides")

total = len(executables) + len(sources) + len(standard_modules) + len(manual_pages) + 1 + 1
done = 0
call report_progress(done, total)
for entry in executables:
    call copy_executable(executable_source(entry[0], entry[1]), prefix + "/bin/" + entry[2])
    done += 1
    call report_progress(done, total)
end
runtime_source = source_path("compiler/qbe/runtime.o")
if not exists(runtime_source):
    runtime_source = source_path("build/qbe/runtime.o")
end
call copy_executable(runtime_source, prefix + "/lib/lsl/compiler/qbe/runtime.o")
done += 1
call report_progress(done, total)
for name in sources:
    call copy_text(source_path("compiler/pure/" + name), prefix + "/lib/lsl/compiler/pure/" + name)
    done += 1
    call report_progress(done, total)
end
for name in standard_modules:
    call copy_text(source_path("stdlib/" + name), prefix + "/lib/lsl/stdlib/" + name)
    done += 1
    call report_progress(done, total)
end
for name in manual_pages:
    call copy_text(source_path("docs/developer_guides/" + name + ".md"), prefix + "/lib/lsl/docs/developer_guides/" + name + ".md")
    done += 1
    call report_progress(done, total)
end


# Record the exact canonical web/manual source included in this release.
call copy_text(source_path("docs/developer_guides/SOURCE.json"), prefix + "/lib/lsl/docs/developer_guides/SOURCE.json")
done += 1
call report_progress(done, total)
print "installed LSL 0.9.2 into", prefix
