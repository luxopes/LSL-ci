# lsl: internal-abi
# Diagnostic typed frontend/SSA dump; IDs are rendered as Strings for JSON.
load frontend
load qbe_emit
load host
load json
source_path = arg(1)
prefix = arg(2)
internal = arg(3) == "internal"
source = readfile(source_path)
stdlib = readfile(host.resource_path("compiler/pure/dynamic_stdlib.lsl"))
unit = frontend.prepare(source_path, source, stdlib, 0, internal)
scopes = {}
for name in unit["function_scopes"].keys():
    scope = unit["function_scopes"][name]
    ids = {}
    for variable in scope["variables"].keys():
        ids[variable] = String(scope["variables"][variable])
    end
    scopes[name] = [ids, scope["types"]]
end
globals = {}
for name in unit["variables"].keys():
    globals[name] = String(unit["variables"][name])
end
summary = [unit["types"], globals, unit["function_returns"], unit["function_parameters"], scopes]
call writefile(prefix + ".typed.json", json.encode(summary))
call qbe_emit.generate(unit, prefix + ".ssa")
