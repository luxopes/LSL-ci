load assembler
load codegen
load parser

function state():
    return {"path":"probe.lsl", "lines":"", "internal_abi":False, "variables":{}, "global_variables":{"i":1280,"total":1288,"text":1296}, "types":{"i":"Int","total":"Int","text":"String"}, "global_types":{}, "functions":{}, "classes":{}, "function_returns":{}, "function_parameters":{}, "builder":assembler.builder(), "error_label":"", "counter":0, "data":[], "string_offsets":{}, "relocations":[], "frame_size":16, "error_handlers":[]}
end

function polls(generator):
    count = 0
    for fixup in generator["builder"]["fixups"]:
        if fixup[1] == "runtime_maybe_gc":
            count += 1
        end
    end
    return count
end

numeric = state()
call codegen.emit_statements(numeric, parser.parse("probe.lsl", "i = 0\ntotal = 0\nwhile i < 1000:\n    total += i * 3\n    i += 1\nend\n"), "", "", "")
check(polls(numeric) == 0, "allocation-free Int loop gained a GC poll")
typed_literal = {"kind":"call", "target":{"kind":"name","name":"__lsl_declared_Int"}, "arguments":[{"kind":"literal","literal_kind":"number","value":"0","integer_value":0}]}
check(not codegen.expression_may_allocate(numeric, typed_literal), "proved type declaration gained a GC poll")
allocating = state()
call codegen.emit_statements(allocating, parser.parse("probe.lsl", "text = \"\"\nwhile i < 1000:\n    text = String(i)\n    i += 1\n    continue\nend\n"), "", "", "")
check(polls(allocating) >= 2, "allocating loop lost its safepoint")
raw = state()
call codegen.emit_statements(raw, parser.parse("probe.lsl", "unsafe:\n    text = String(i)\nend\n"), "", "", "")
check(polls(raw) == 0, "automatic GC inserted inside raw construction")
print "allocation-free loops have no GC polls; allocating paths have safepoints"
