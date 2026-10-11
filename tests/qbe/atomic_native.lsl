# Atomic slot operations retain native lock-free RMW and operand effect order.
values = IntArray()
values.append(10)
check(atomic_add(values, -1, 5) == 10 and values[0] == 15, "negative add")
check(atomic_xchg(values, -1, 20) == 15 and values[0] == 20, "exchange")
check(atomic_cas(values, -1, 20, 30) == 20 and values[0] == 30, "CAS success")
check(atomic_cas(values, 0, 20, 99) == 30 and values[0] == 30, "CAS mismatch")
call atomic_xchg(values, 0, 9223372036854775807)
check(atomic_add(values, 0, 1) == 9223372036854775807, "old value on overflow")
check(values[0] == -9223372036854775808, "wrapped slot")
call atomic_xchg(values, 0, 30)
order = []
function selected_target():
    order.append("target")
    return values
end
function selected_index():
    order.append("index")
    return 0
end
function growing_value():
    order.append("value")
    for item in rang(100):
        values.append(item)
    end
    call gc()
    return 2
end
check(atomic_add(selected_target(), selected_index(), growing_value()) == 30, "old slot after growth")
check(values[0] == 32 and order == ["target", "index", "value"], "evaluation order and storage reload")
order = []
try:
    call atomic_add(values, 999, growing_value())
else:
    check(last_error().startswith("IndexError: index out of range at "), "bounds diagnostic")
end
check(order == [], "bounds checked before value effects")
rejected = False
try:
    call atomic_add(values, True, 1)
else:
    rejected = last_error().startswith("TypeError: atomic RMW index requires an Int at ")
end
check(rejected, "Bool index rejected")
rejected = False
try:
    call atomic_cas(values, 0, 32, 1.5)
else:
    rejected = last_error().startswith("TypeError: atomic_cas desired value requires an Int at ")
end
check(rejected, "Float desired value rejected")
call atomic_pause()
print "native atomic operations passed"
