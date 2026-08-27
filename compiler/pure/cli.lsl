# Public pure-LSL command frontend.

load codegen
load linker
load package
load parser

VERSION = "0.6.9"

function print_help():
    print "Lux Simple Lang (LSL) " + VERSION
    print ""
    print "Usage:"
    print "  lsl [SOURCE [ARG...]]"
    print "  lsl compile SOURCE OUTPUT"
    print "  lsl config ENTRY"
    print "  lsl install NAME"
    print "  lsl install --config FILE"
    print "  lsl update NAME"
    print "  lsl server"
    print "  lsl version"
    print ""
    print "Options:"
    print "  -h, --help     Show this help"
    print "  --version      Show version"
end

function compile_source(source_path, source, output_path):
    stdlib_name = "compiler/pure/dynamic_stdlib.lsl"
    stdlib_path = resource_path(stdlib_name)
    stdlib_source = readfile(stdlib_path)
    program = parser.parse(stdlib_name, stdlib_source)
    call linker.annotate_statements(program, stdlib_name)
    program.extend(linker.link(source_path, source))
    call writebytes(output_path, codegen.generate(source_path, source, program))
end

function compile_file(source_path, output_path):
    call compile_source(source_path, readfile(source_path), output_path)
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

function resource_path(path):
    executable = executable_path()
    binary_directory = dirname(executable)
    root_candidate = binary_directory + "/" + path
    if exists(root_candidate):
        return root_candidate
    end
    root_candidate = dirname(dirname(dirname(executable))) + "/" + path
    if exists(root_candidate):
        return root_candidate
    end
    prefix = dirname(binary_directory)
    prefix_bin = prefix + "/bin"
    if prefix == "/":
        prefix_bin = "/bin"
    end
    if binary_directory == prefix_bin:
        return prefix + "/lib/lsl/" + path
    end
    # Repository fallback is last so an attacker-controlled working directory
    # cannot shadow resources beside an installed executable.
    return path
end

function tool_path(repository_path, installed_name):
    binary_directory = dirname(executable_path())
    adjacent = binary_directory + "/" + installed_name
    if exists(adjacent):
        return adjacent
    end
    prefix = dirname(binary_directory)
    prefix_bin = prefix + "/bin"
    if prefix == "/":
        prefix_bin = "/bin"
    end
    if binary_directory == prefix_bin:
        # An incomplete installation must not execute a same-named tool from
        # the caller's working directory.
        return adjacent
    end
    return repository_path
end

function required_system_tool(primary, fallback, label):
    if exists(primary):
        return primary
    elif exists(fallback):
        return fallback
    end
    Error(ProcessError: "trusted " + label + " executable is required")
end

function registry_server():
    server = __lsl_getenv("LSL_REGISTRY")
    if server == None or server == "":
        server = "https://luxos-registry-temp-2026.netlify.app/lsl"
    end
    return package.normalize_server(server)
end

function user_home():
    home = __lsl_getenv("HOME")
    if home == None or home == "":
        Error(PackageError: "HOME is required for per-user library installation")
    end
    return home
end

# Scratch path for a compiled program. Atomic 0700 mkdir prevents other users
# from replacing the ELF between compilation and execution.
function scratch_program_path():
    process = String(__lsl_syscall(39, 0, 0, 0, 0))
    attempt = 0
    directory = "/tmp/lsl-program-" + process
    while __lsl_mkdir_private(directory) != 0:
        attempt += 1
        if attempt > 100:
            Error(FileError: "cannot create a private CLI scratch directory")
        end
        directory = "/tmp/lsl-program-" + process + "-" + String(attempt)
    end
    return directory + "/program"
end

function cleanup_program(path):
    call unlink(path)
    call rmdir(dirname(path))
end

function cleanup_config_snapshots(directory):
    index = 0
    while index < 256:
        call unlink(directory + "/lsl_config_snapshot_" + String(index) + ".lsl")
        index += 1
    end
end

function read_stdin_source():
    lines = []
    total = 0
    terminal = __lsl_isatty(0)
    if terminal:
        print "Lux Simple Lang " + VERSION + " interactive source mode"
        print "Enter code; type exit on its own line to compile and run."
    end
    loop:
        prompt = ""
        if terminal:
            prompt = ">>> "
        end
        line = input(prompt)
        eof = __lsl_stdin_eof()
        if line == "exit":
            break
        elif eof and line == "":
            break
        end
        total += __lsl_text_byte_length(String(line)) + 1
        if total > 4194304:
            Error(CompileError: "stdin source exceeds the 4 MiB compiler limit")
        end
        lines.append(line)
        if eof:
            break
        end
    end
    if len(lines) == 0:
        return ""
    end
    return chr(10).join(lines) + chr(10)
end

command = arg(1)
if command == None:
    source = read_stdin_source()
    if source == "":
        exit(0)
    end
    scratch = scratch_program_path()
    call compile_source("<stdin>", source, scratch)
    status = run(scratch, [])
    call cleanup_program(scratch)
    exit(status)
end

if command == "--help" or command == "-h" or command == "help":
    call print_help()
    exit(0)
elif command == "version" or command == "--version":
    print VERSION
    exit(0)
elif command == "compile":
    source_path = arg(2)
    output_path = arg(3)
    if source_path == None or output_path == None:
        print "usage: lsl compile SOURCE OUTPUT"
        exit(2)
    end
    call compile_file(source_path, output_path)
    exit(0)
elif command == "config":
    entry = arg(2)
    if entry == None:
        print "usage: lsl config ENTRY"
        exit(2)
    end
    evaluator = scratch_program_path()
    snapshot_directory = dirname(evaluator)
    wrapper = capture_clean(tool_path("./compiler/pure/lsl-configure", "lsl-configure"), [entry, "-", snapshot_directory])
    status = capture_status()
    if status != 0:
        if wrapper != "":
            print wrapper
        end
        detail = capture_stderr()
        if detail != "":
            print detail
        end
        call cleanup_config_snapshots(snapshot_directory)
        call cleanup_program(evaluator)
        exit(status)
    end
    synthetic_path = snapshot_directory + "/lsl_config_wrapper.lsl"
    call compile_source(synthetic_path, wrapper, evaluator)
    # Even lexically pure configuration may contain an infinite loop or an
    # allocation bomb. Evaluate it in a clean subprocess with wall-clock, CPU,
    # address-space, file-size and descriptor limits.
    timeout = required_system_tool("/usr/bin/timeout", "/bin/timeout", "timeout")
    prlimit = required_system_tool("/usr/bin/prlimit", "/bin/prlimit", "prlimit")
    limits = [
        "--signal=TERM", "--kill-after=1s", "--", "30s", prlimit,
        "--as=1073741824", "--cpu=30", "--fsize=16777216",
        "--nofile=64", "--nproc=32", "--", evaluator
    ]
    status = run_clean(timeout, limits)
    call cleanup_config_snapshots(snapshot_directory)
    call cleanup_program(evaluator)
    exit(status)
elif command == "install":
    name = arg(2)
    if name == "--config" and arg(3) != None and arg(4) == None:
        call package.install_config(arg(3), user_home(), registry_server(), "/usr/bin/curl", "/usr/bin/sha256sum", "/usr/bin/mv", "/usr/bin/chmod", executable_path())
    elif name != None and arg(3) == None:
        call package.install(name, user_home(), registry_server(), "/usr/bin/curl", "/usr/bin/sha256sum", "/usr/bin/mv", "/usr/bin/chmod", executable_path())
    else:
        print "usage: lsl install NAME | lsl install --config FILE"
        exit(2)
    end
    exit(0)
elif command == "update":
    name = arg(2)
    if name == None or arg(3) != None:
        print "usage: lsl update NAME"
        exit(2)
    end
    call package.update(name, user_home(), registry_server(), "/usr/bin/curl", "/usr/bin/sha256sum", "/usr/bin/mv", "/usr/bin/chmod", executable_path())
    exit(0)
elif command == "server":
    if arg(2) != None:
        print "usage: lsl server"
        exit(2)
    end
    print registry_server()
    exit(0)
end

scratch = scratch_program_path()
call compile_file(command, scratch)
arguments = []
index = 2
while index < arg_count():
    arguments.append(arg(index))
    index += 1
end
status = run(scratch, arguments)
call cleanup_program(scratch)
exit(status)
