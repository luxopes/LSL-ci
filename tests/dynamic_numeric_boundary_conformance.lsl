# Arithmetic through escaped functions uses the public tagged Any ABI. Numeric
# values must retain their value (including Bool), Strings are accepted only by
# +, and every receiver/type mismatch must be a catchable LSL error.

function dynamic_add(left, right):
    return left + right
end

function dynamic_sub(left, right):
    return left - right
end

function dynamic_mul(left, right):
    return left * right
end

function dynamic_div(left, right):
    return left / right
end

function dynamic_floordiv(left, right):
    return left // right
end

function dynamic_mod(left, right):
    return left % right
end

function dynamic_power(left, right):
    return left ^ right
end

function dynamic_negate(value):
    return -value
end

function dynamic_absolute(value):
    return abs(value)
end

function dynamic_less(left, right):
    return left < right
end

function dynamic_min(left, right):
    return min(left, right)
end

function dynamic_max(left, right):
    return max(left, right)
end

function dynamic_float(value):
    return Float(value)
end

function dynamic_sum_values(values):
    return sum(values)
end

function dynamic_min_values(values):
    return min(values)
end

function dynamic_max_values(values):
    return max(values)
end

escaped = [dynamic_add, dynamic_sub, dynamic_mul, dynamic_div, dynamic_floordiv, dynamic_mod, dynamic_power, dynamic_negate, dynamic_absolute, dynamic_less, dynamic_min, dynamic_max, dynamic_float, dynamic_sum_values, dynamic_min_values, dynamic_max_values]

print dynamic_add(7, 5), dynamic_add(1.5, 2), dynamic_add("LS", "L"), dynamic_add(True, 2), dynamic_add([1], [2, 3])
print dynamic_sub(7, 2), dynamic_sub(5.5, 2), dynamic_mul(3, 4), dynamic_mul(1.5, 2), dynamic_mul(False, 9), dynamic_mul("ab", 3), dynamic_mul(2, "x")
print dynamic_div(7, 2), dynamic_div(True, 2)
print dynamic_floordiv(-7, 3), dynamic_floordiv(7.5, 2), dynamic_floordiv(True, 2), dynamic_mod(-7, 3), dynamic_mod(7.5, 2), dynamic_mod(True, 2)
print dynamic_power(2, 3), dynamic_power(2.0, 3), dynamic_power(2, True), dynamic_power(2.0, True), dynamic_float(True)
print dynamic_negate(-4), dynamic_negate(1.5), dynamic_absolute(-8), dynamic_absolute(-2.5)
print dynamic_less(1.5, 2), dynamic_min(3.5, 2), dynamic_max(True, 0)
print dynamic_sum_values([1, 2.5, True]), dynamic_min_values([3, 1.5, 2]), dynamic_max_values([3, 1.5, 2])
print dynamic_add(dynamic_add(2, 3), 4), dynamic_mul(dynamic_mul(2, 3), 4)
typed_ints = IntArray()
typed_ints.append(8)
typed_ints.append(2)
typed_bytes = ByteArray()
typed_bytes.append(3)
typed_bytes.append(7)
print dynamic_add(dynamic_min_values(typed_ints), 3), dynamic_mul(dynamic_max_values(typed_bytes), 2)

try:
    print dynamic_add([], 1)
else:
    print last_error()
end
try:
    print dynamic_sub("x", 1)
else:
    print last_error()
end
try:
    print dynamic_mul("x", 1.5)
else:
    print last_error()
end
try:
    print dynamic_div({}, 1)
else:
    print last_error()
end
try:
    print dynamic_floordiv("x", 1)
else:
    print last_error()
end
try:
    print dynamic_mod([], 1)
else:
    print last_error()
end
try:
    print dynamic_power(2, 1.5)
else:
    print last_error()
end
try:
    print dynamic_negate("x")
else:
    print last_error()
end
try:
    print dynamic_absolute(None)
else:
    print last_error()
end
try:
    print dynamic_less("a", "b")
else:
    print last_error()
end
try:
    print dynamic_min([], 1)
else:
    print last_error()
end
try:
    print dynamic_sum_values([1, "x"])
else:
    print last_error()
end
try:
    print dynamic_min_values([1, "x"])
else:
    print last_error()
end
