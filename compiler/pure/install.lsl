# Pure-LSL installer. No shell, cp, libc, or foreign build tool.
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
        call update_install.install_stage(executable_path(), generation, "0.8.3", work)
        call update_install.prepare(prefix, prefix + "/bin/lsl", previous_version, work)
        call update_install.activate(store, generation, "0.8.3", work)
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
    print "Installed LSL 0.8.3 atomically; previous version retained for rollback."
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
    "browser.lsl",
    "catalog.lsl",
    "cli.lsl",
    "codegen.lsl",
    "console.lsl",
    "diagnostics.lsl",
    "dynamic_stdlib.lsl",
    "elf_image.lsl",
    "flow.lsl",
    "declarations.lsl",
    "heap_runtime.lsl",
    "install.lsl",
    "io_runtime.lsl",
    "lexer.lsl",
    "linker.lsl",
    "lslc_direct.lsl",
    "manual.lsl",
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

standard_modules = ["_random_hash.lsl", "ai.lsl", "bigint.lsl", "config.lsl", "configure.lsl", "cuda.lsl", "env.lsl", "fd.lsl", "http.lsl", "httpserver.lsl", "json.lsl", "lconf.lsl", "lux.lsl", "luxos.lsl", "math.lsl", "native.lsl", "os.lsl", "plugin.lsl", "process.lsl", "random.lsl", "sandbox.lsl", "system.lsl", "tensor.lsl", "time.lsl", "tui.lsl", "unixsock.lsl"]
for name in standard_modules:
    call copy_text(source_path("stdlib/" + name), prefix + "/lib/lsl/stdlib/" + name)
end

call mkdir(prefix + "/lib/lsl/docs")
call mkdir(prefix + "/lib/lsl/docs/developer_guides")
manual_pages = ["README", "01-getting-started", "02-language-basics", "03-functions-and-classes", "04-collections", "05-error-handling", "06-modules-and-imports", "07-files-io-and-processes", "08-configuration-system", "09-gui-programming", "10-ai-applications", "11-performance-and-optimization", "12-compiler-internals", "13-server-and-origin", "14-sandbox-and-safety", "15-cuda", "16-random", "17-cli-and-packages", "reference", "security", "CHANGELOG"]
for name in manual_pages:
    call copy_text(source_path("docs/developer_guides/" + name + ".md"), prefix + "/lib/lsl/docs/developer_guides/" + name + ".md")
end

print "installed pure LSL into", prefix
