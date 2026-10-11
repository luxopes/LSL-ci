function affine(value):
    return (value + 0.5) * 1.25
end
function identity(value):
    call gc()
    return value
end
function mixed(flag):
    if flag:
        return 2.5
    end
    return 2
end
callbacks = [identity]
direct = affine(3.5)
callback = callbacks[0]
through_any = callback(direct)
values = [direct, through_any, -0.0]
mapping = {"value": through_any}
call gc()
print direct, through_any, values[0], mapping["value"]
print type(direct), type(through_any), type(values[0]), type(mapping["value"])
print mixed(True) + 0.25, mixed(False) * 1.5
print type(mixed(True) + 0.25), type(mixed(False) * 1.5)
print __lsl_float_bits(Float(values[2])) == -9223372036854775808
array = FloatArray()
array.append(1.5)
array.append(2.5)
print array[0] + array[1], type(array[0] * 2.0)
array.append((1.5 + 0.5) * 2.0)
print array[2]

function churn(value):
    for index in rang(100000):
        temporary = __lsl_box_int(index)
    end
    return value
end
function retain(a, b, c, d, e, f, g, h):
    call gc()
    return Float(a) + Float(b) + Float(c) + Float(d) + Float(e) + Float(f) + Float(g) + Float(h)
end
print retain(1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5, churn(8.5))
print Int(identity(-3.75)), Bool(identity(0.0)), Bool(identity(1.5))
try:
    print mixed(True) + []
else:
    print last_error().startswith("TypeError:")
end
