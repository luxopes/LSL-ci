# Collection operations through an escaped Function use the public Any ABI.
# They must dispatch by the runtime receiver type without losing Dictionary
# keys, corrupting typed arrays, or bypassing bounds/type checks.

function dynamic_get(target, key):
    return target[key]
end

function dynamic_set(target, key, value):
    target[key] = value
    return target[key]
end

function dynamic_delete(target, key):
    del(target[key])
    return target
end

function dynamic_length(value):
    return len(value)
end

function dynamic_sum(values):
    result = 0
    for value in values:
        result += Int(value)
    end
    return result
end

function dynamic_contains(target, value):
    return value in target
end

function dynamic_slice(target, start, stop):
    return target[start:stop]
end

# Taking the functions as values deliberately disables direct-call parameter
# specialization and exercises the same ABI used by callbacks and plugins.
escaped = [dynamic_get, dynamic_set, dynamic_delete, dynamic_length, dynamic_sum, dynamic_contains, dynamic_slice]

mapping = {"name": "LSL"}
print dynamic_get(mapping, "name")
print dynamic_set(mapping, "count", 3), mapping
print dynamic_delete(mapping, "name"), mapping

values = [10, 20, 30]
print dynamic_get(values, -1)
print dynamic_set(values, 1, 25), values
print dynamic_delete(values, 0), values
print dynamic_length(values), dynamic_sum(values)

integers = IntArray()
integers.append(4)
integers.append(5)
print dynamic_get(integers, 1), dynamic_set(integers, 0, 7), integers

floats = FloatArray()
floats.append(1.5)
floats.append(2.5)
print dynamic_get(floats, 0), dynamic_set(floats, 1, 3.5), floats

bytes = ByteArray()
bytes.append(65)
bytes.append(66)
print dynamic_get(bytes, 0), dynamic_set(bytes, 1, 67), bytes
print dynamic_contains(mapping, "count"), dynamic_contains(values, 25), dynamic_contains("hello", "ell")
print 7 in integers, 3.5 in floats, 67 in bytes
print dynamic_slice("hello", 1, 4), dynamic_slice(values, 0, 2)
print type(dynamic_slice(integers, 0, 1)), type(dynamic_slice(floats, 0, 1)), type(dynamic_slice(bytes, 0, 1))

try:
    print dynamic_get(values, 99)
else:
    print last_error()
end
try:
    print dynamic_set(values, -99, 1)
else:
    print last_error()
end
try:
    print dynamic_length(42)
else:
    print last_error()
end
try:
    print dynamic_sum(42)
else:
    print last_error()
end
try:
    print dynamic_contains(42, 1)
else:
    print last_error()
end
try:
    print dynamic_slice(42, 0, 1)
else:
    print last_error()
end
try:
    print dynamic_slice(values, "0", 1)
else:
    print last_error()
end
