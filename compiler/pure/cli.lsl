# Public pure-LSL command frontend.

load codegen
load linker
load parser

function compile_file(source_path, output_path):
    source = readfile(source_path)
    stdlib_path = resource_path("compiler/pure/dynamic_stdlib.lsl")
    stdlib_source = readfile(stdlib_path)
    program = parser.parse(stdlib_path, stdlib_source)
    call linker.annotate_statements(program, stdlib_path)
    program.extend(linker.link(source_path, source))
    call writebytes(output_path, codegen.generate(source_path, source, program))
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

command = arg(1)
if command == None:
    print "usage: lsl SOURCE [ARGS...] | lsl compile SOURCE OUTPUT | lsl config ENTRY"
    exit(2)
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
end

call compile_file(command, "/tmp/lsl-program")
arguments = []
index = 2
while index < arg_count():
    arguments.append(arg(index))
    index += 1
end
exit(run("/tmp/lsl-program", arguments))
