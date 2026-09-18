load assembler
load codegen
load parser
load x86_64

function state():
    declaration = parser.parse("probe.lsl", "function probe(value):" + chr(10) + "    return value" + chr(10) + "end" + chr(10))[0]
    return {"path":"probe.lsl", "lines":"", "internal_abi":False, "variables":{}, "global_variables":{}, "types":{}, "global_types":{}, "functions":{"probe":declaration}, "classes":{}, "function_returns":{"probe":"Int"}, "function_parameters":{"probe":["Int"]}, "builder":assembler.builder(), "error_label":"caller_return", "counter":0, "data":[], "string_offsets":{}, "relocations":[], "frame_size":16, "error_handlers":[]}
end

plain = state()
guarded = state()
call codegen.emit_statements(plain, parser.parse("probe.lsl", "call probe(42)" + chr(10)), "", "", "")
call codegen.emit_statements(guarded, parser.parse("probe.lsl", "safe:" + chr(10) + "    call probe(42)" + chr(10) + "end" + chr(10)), "", "", "")
expected = List(plain["builder"]["code"])
call expected.extend(x86_64.store_fs_imm32(8, 0))
check(expected == guarded["builder"]["code"], "safe added success-path instructions beyond the existing flag clear")
check(len(guarded["error_handlers"]) == 1, "missing out-of-line error recovery")
print "safe direct-call success path has no added checks or instructions"
