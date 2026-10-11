# lsl: internal-abi
function parity_even(raw_n):
    n = __lsl_qbe_raw_int(raw_n)
    if n == 0:
        return True
    end
    return parity_odd(n - 1)
end
function parity_odd(raw_n):
    n = __lsl_qbe_raw_int(raw_n)
    if n == 0:
        return False
    end
    return parity_even(n - 1)
end
function leaf_error():
    Error(Probe: "propagated")
end
function middle_error():
    call leaf_error()
    return 0
end
function recursive_error(raw_n):
    n = __lsl_qbe_raw_int(raw_n)
    if n > 0:
        return recursive_error(n - 1)
    end
    return middle_error()
end
function divide(raw_a, raw_b):
    return __lsl_qbe_raw_int(raw_a) // __lsl_qbe_raw_int(raw_b)
end
function allocate(raw_index):
    return "temporary:" + String(__lsl_qbe_raw_int(raw_index))
end
function allocation_caller():
    result = ""
    for index in rang(1500000):
        result = allocate(index)
    end
    return result
end
check(parity_even(40) and parity_odd(41), "pure recursive call graph")
caught = False
try:
    call recursive_error(4)
else:
    caught = last_error() == "Probe: propagated"
end
check(caught, "exception through direct and recursive calls")
caught = False
try:
    call divide(7, 0)
else:
    caught = True
end
check(caught, "implicit arithmetic exception")
check(allocation_caller() == "temporary:1499999", "callee safepoints bound caller loop")
call gc()
check(allocate(7) == "temporary:7", "pooled literal survives collection")
print "PASS QBE call effects"
