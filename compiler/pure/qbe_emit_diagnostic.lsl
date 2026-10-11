# lsl: internal-abi
# Explicit diagnostic tool; production image construction keeps no artifacts.
load frontend
load qbe_emit
load host
source_path = arg(1)
output_path = arg(2)
source = readfile(source_path)
stdlib = readfile(host.resource_path("compiler/pure/dynamic_stdlib.lsl"))
unit = frontend.prepare(source_path, source, stdlib, 0, source.startswith("# lsl: internal-abi" + chr(10)))
call qbe_emit.generate(unit, output_path)
