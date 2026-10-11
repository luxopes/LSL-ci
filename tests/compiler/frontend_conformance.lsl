# Sémantická analýza funguje bez načtení strojového backendu.
load frontend

source = "global = 4\nfunction bump(value):\n    local = value + global\n    return local\nend\nresult = bump(3)\nfor n in rang(2):\n    result += n\nend\n"
unit = frontend.prepare("frontend-probe.lsl", source, "", 0, False)
check(unit["function_parameters"]["bump"] == ["Int"], "direct-call parameter inference failed")
check(unit["function_returns"]["bump"] == "Int", "return inference lost a global type")
scope = unit["function_scopes"]["bump"]
check(scope["types"]["local"] == "Int", "function-local type inference failed")
check(scope["variables"]["value"] == 1 and scope["variables"]["local"] == 2, "local bindings contain machine offsets")
check("global" in scope["global_reads"], "global-read analysis missing")
index = 1
for name in unit["variables"].keys():
    check(unit["variables"][name] == index, "global binding IDs are not stable ordinals")
    index += 1
end

shadow = frontend.prepare("shadow.lsl", "item = 1\nfunction select(item):\n    return item\nend\nchosen = select(\"text\")\n", "", 0, False)
check(shadow["types"]["item"] == "Int", "global type changed through lexical shadowing")
check(shadow["function_scopes"]["select"]["types"]["item"] == "String", "parameter inherited the shadowed global type")
check(shadow["function_returns"]["select"] == "String", "shadowed parameter return type is wrong")

escaped = frontend.prepare("callback.lsl", "function increment(value):\n    return value + 1\nend\ncallback = increment\nresult = callback(4)\n", "", 0, False)
check(escaped["function_parameters"]["increment"] == ["Any"], "escaping callback gained a specialized ABI")
check(not escaped["functions"]["increment"]["internal_abi"], "public callback gained internal ABI")

marked = "# lsl: internal-abi\nfunction identity(value):\n    return value\nend\n"
public = frontend.prepare("public.lsl", marked, "", 0, False)
internal = frontend.prepare("compiler.lsl", marked, "", 0, True)
check(not public["functions"]["identity"]["internal_abi"], "frontend trusted an unapproved source marker")
check(internal["functions"]["identity"]["internal_abi"], "compiler trust mode lost provenance")
rejected = False
try:
    call frontend.prepare("compiler.lsl", marked, "", 1, True)
else:
    rejected = "internal ABI" in last_error()
end
check(rejected, "checked compilation accepted internal ABI")
print "frontend bindings, inference, shadowing, callbacks and ABI provenance passed"
