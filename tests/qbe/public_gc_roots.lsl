# Earlier arguments remain live while a later argument triggers automatic GC.
# Eight boxed arguments also exercise callee-saved registers and stack slots
# across an explicit collection in the called function.
function churn(value):
    for index in rang(100000):
        temporary = __lsl_box_int(index)
    end
    return value
end

function retain(a, b, c, d, e, f, g, h):
    call gc()
    return Int(a) + Int(b) + Int(c) + Int(d) + Int(e) + Int(f) + Int(g) + Int(h)
end

function caller(value):
    number = Int(value)
    return retain(__lsl_box_int(number + 1), __lsl_box_int(number + 2), __lsl_box_int(number + 3), __lsl_box_int(number + 4), __lsl_box_int(number + 5), __lsl_box_int(number + 6), __lsl_box_int(number + 7), churn(number + 8))
end

print caller(0), caller(1000), caller(-1000)
