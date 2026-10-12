# Volání funkce kvůli účinku vyžaduje call; metody objektů a vestavěné
# příkazy call nepotřebují (chybové případy: tests/compiler/language_091_negative.lsl).
load json

call_log = []

function call_note(text):
    call call_log.append(text)
    return len(call_log)
end

call call_note("call")
call_count = call_note("assigned")
call json.decode("[1]")
call_items = [3, 1, 2]
call_items.append(4)
call_items.sort()
call_dict = {"a": 1, "b": 2}
del(call_dict["a"])
check(len(call_items) == 4, "check without call")
writefile("/dev/null", "builtin without call")
print "call statements", call_log, call_count, call_items, call_dict
