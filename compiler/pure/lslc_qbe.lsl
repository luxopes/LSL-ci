# lsl: internal-abi
# Native LSL frontend + LSL QBE backend. Public source is safe by default.
load frontend
load host
load qbe_toolchain
load target

source_index = 1
safety_mode = -1
target_name = host.target_name()
while arg(source_index) != None and String(arg(source_index)).startswith("--"):
    option = arg(source_index)
    if option == "--":
        source_index += 1
        break
    elif option == "--safe":
        safety_mode = 1
    elif option == "--unsafe":
        safety_mode = 0
    elif option == "--sandbox":
        safety_mode = 2
    elif option == "--target":
        target_name = arg(source_index + 1)
        source_index += 1
    else:
        print "unknown compiler option: " + String(option)
        exit(2)
    end
    source_index += 1
end
source_path = arg(source_index)
output_path = arg(source_index + 1)
backend_path = arg(source_index + 2)
if target_name == None or source_path == None or output_path == None or arg(source_index + 3) != None:
    print "usage: lslc [--safe | --unsafe | --sandbox] [--target NAME] SOURCE OUTPUT [LSL-QBE]"
    exit(2)
end
if backend_path == None:
    backend_path = ""
end
source = readfile(source_path)
internal_abi = source.startswith("# lsl: internal-abi" + chr(10))
if safety_mode == -1:
    safety_mode = 1
    if internal_abi:
        safety_mode = 0
    end
end
selected = target.resolve(target_name)
stdlib = readfile(host.resource_path("compiler/pure/dynamic_stdlib.lsl"))
unit = frontend.prepare(source_path, source, stdlib, safety_mode, internal_abi, selected["platform_module"], True)
image = qbe_toolchain.image(unit, selected, "", backend_path)
call writebytes(output_path, image)
