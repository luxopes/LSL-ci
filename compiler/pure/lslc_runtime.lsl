# lsl: internal-abi
# Překlad runtime jazyka napsaného v LSL (# lsl: runtime) do LuxIR:
# lslc-runtime ZDROJ VÝSTUP.lir
load frontend
load host
load qbe_emit
load target

source_path = arg(1)
output_path = arg(2)
if source_path == None or output_path == None or arg(3) != None:
    print "usage: lslc-runtime SOURCE OUTPUT.lir"
    exit(2)
end
source = readfile(source_path)
if not source.startswith("# lsl: runtime" + chr(10)):
    print "runtime source must start with: # lsl: runtime"
    exit(2)
end
selected = target.resolve(host.target_name())
unit = frontend.prepare(source_path, source, "", 0, True, selected["platform_module"], False)
call qbe_emit.generate_runtime(unit, output_path)
