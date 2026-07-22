# Final direct compiler driver: LSL source -> executable ELF in one process.
# No decimal byte specification and no external materializer.

load codegen
load linker
load parser

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

source_path = arg(1)
output_path = arg(2)
if source_path == None or output_path == None:
    print "usage: lslc SOURCE OUTPUT"
    exit(2)
end
source = readfile(source_path)
stdlib_path = resource_path("compiler/pure/dynamic_stdlib.lsl")
stdlib_source = readfile(stdlib_path)
program = parser.parse(stdlib_path, stdlib_source)
call linker.annotate_statements(program, stdlib_path)
program.extend(linker.link(source_path, source))
image = codegen.generate(source_path, source, program)
call writebytes(output_path, image)
