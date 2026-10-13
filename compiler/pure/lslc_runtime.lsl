# lsl: internal-abi
# Překlad runtime jazyka napsaného v LSL (# lsl: runtime) do LuxIR:
# lslc-runtime [--target CÍL] ZDROJ VÝSTUP.lir
load frontend
load host
load qbe_emit
load target

index = 1
target_name = host.target_name()
if arg(1) == "--target":
    target_name = arg(2)
    index = 3
end
source_path = arg(index)
output_path = arg(index + 1)
if target_name == None or source_path == None or output_path == None or arg(index + 2) != None:
    print "usage: lslc-runtime [--target NAME] SOURCE OUTPUT.lir"
    exit(2)
end
source = readfile(source_path)
if not source.startswith("# lsl: runtime" + chr(10)):
    print "runtime source must start with: # lsl: runtime"
    exit(2)
end
selected = target.resolve(target_name)
unit = frontend.prepare(source_path, source, "", 0, True, selected["platform_module"], False)
call qbe_emit.generate_runtime(unit, output_path)
