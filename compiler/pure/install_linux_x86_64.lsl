# Pure-LSL installer. Copies trusted native tools/resources using syscalls.
load fd
load install_files
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
        call update_install.install_stage(executable_path(), generation, "0.10.7", work)
        call update_install.prepare(prefix, prefix + "/bin/lsl", previous_version, work)
        call update_install.activate(store, generation, "0.10.7", work)
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
    print "Installed LSL 0.10.7 atomically; previous version retained for rollback."
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

sources = install_files.SOURCES
standard_modules = install_files.STANDARD_MODULES
target_files = install_files.TARGET_FILES
manual_pages = install_files.MANUAL_PAGES
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
# Runtime a vrstvy architektury dalších cílů (lsl compile --target):
# zkopíruje se, co balík obsahuje.
call mkdir(prefix + "/lib/lsl/compiler/qbe/windows-x86_64")
call mkdir(prefix + "/lib/lsl/compiler/qbe/windows-arm64")
call mkdir(prefix + "/lib/lsl/runtime")
call mkdir(prefix + "/lib/lsl/runtime/arch")
call mkdir(prefix + "/lib/lsl/tools")
for name in target_files:
    if exists(source_path(name)):
        call copy_executable(source_path(name), prefix + "/lib/lsl/" + name)
    end
end
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
print "installed LSL 0.10.7 into", prefix
