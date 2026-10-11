# lsl: internal-abi
# Final direct compiler driver: LSL source -> cílový obraz in one process.
# No decimal byte specification and no external materializer.

load pipeline
load host

function dirname(path):
    return host.dirname(path)
end

function resource_path(path):
    return host.resource_path(path)
end

target_name = ""
source_index = 1
if arg(1) == "--target":
    target_name = arg(2)
    source_index = 3
end
source_path = arg(source_index)
output_path = arg(source_index + 1)
if target_name == None or source_path == None or output_path == None or arg(source_index + 2) != None:
    print "usage: lslc [--target NAME] SOURCE OUTPUT"
    exit(2)
end
source = readfile(source_path)
stdlib_name = "compiler/pure/dynamic_stdlib.lsl"
stdlib_path = resource_path(stdlib_name)
stdlib_source = readfile(stdlib_path)
internal_abi = source.startswith("# lsl: internal-abi" + chr(10))
image = pipeline.compile_mode(source_path, source, stdlib_source, 0, internal_abi, "", target_name)
call writebytes(output_path, image)
