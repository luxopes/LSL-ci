# Public pure-LSL command frontend.

load codegen
load linker
load package
load parser

function compile_source(source_path, source, output_path):
    stdlib_path = resource_path("compiler/pure/dynamic_stdlib.lsl")
    stdlib_source = readfile(stdlib_path)
    program = parser.parse(stdlib_path, stdlib_source)
    call linker.annotate_statements(program, stdlib_path)
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
    if exists(path):
        return path
    end
    executable = executable_path()
    root_candidate = dirname(executable) + "/" + path
    if exists(root_candidate):
        return root_candidate
    end
    root_candidate = dirname(dirname(dirname(executable))) + "/" + path
    if exists(root_candidate):
        return root_candidate
    end
    prefix = dirname(dirname(executable))
    return prefix + "/lib/lsl/" + path
end

function tool_path(repository_path, installed_name):
    if exists(repository_path):
        return repository_path
    end
    return dirname(executable_path()) + "/" + installed_name
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

function read_stdin_source():
    lines = []
    terminal = __lsl_isatty(0)
    if terminal:
        print "Lux Simple Lang 0.7 interactive source mode"
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
    call compile_source("<stdin>", source, "/tmp/lsl-stdin-program")
    exit(run("/tmp/lsl-stdin-program", []))
end

if command == "compile":
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
    wrapper = dirname(entry) + "/.lsl-config-evaluator.lsl"
    status = run(tool_path("./compiler/pure/lsl-configure", "lsl-configure"), [entry, wrapper])
    if status != 0:
        exit(status)
    end
    call compile_file(wrapper, "/tmp/lsl-config-evaluator")
    call unlink(wrapper)
    status = run("/tmp/lsl-config-evaluator", [])
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

call compile_file(command, "/tmp/lsl-program")
arguments = []
index = 2
while index < arg_count():
    arguments.append(arg(index))
    index += 1
end
exit(run("/tmp/lsl-program", arguments))
