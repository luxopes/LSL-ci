# Method calls through an escaped Function use a runtime-typed Any receiver.
# Every supported collection family must dispatch correctly, while a receiver
# mismatch must raise a catchable TypeError rather than touching another
# object's layout.

function dynamic_append(target, value):
    call target.append(value)
    return target
end

function dynamic_clear(target):
    call target.clear()
    return target
end

function dynamic_keys(target):
    return target.keys()
end

function dynamic_pop0(target):
    return target.pop()
end

function dynamic_pop1(target, key):
    return target.pop(key)
end

function dynamic_pop2(target, key, default_value):
    return target.pop(key, default_value)
end

function dynamic_count(target, value):
    return target.count(value)
end

function dynamic_index(target, value):
    return target.index(value)
end

function dynamic_copy(target):
    return target.copy()
end

function dynamic_get_method(target, key, default_value):
    return target.get(key, default_value)
end

function dynamic_setdefault(target, key, default_value):
    return target.setdefault(key, default_value)
end

function dynamic_upper(target):
    return target.upper()
end

function dynamic_startswith(target, prefix):
    return target.startswith(prefix)
end

function dynamic_join(target, values):
    return target.join(values)
end

function dynamic_extend(target, values):
    call target.extend(values)
    return target
end

function dynamic_update(target, values):
    call target.update(values)
    return target
end

function dynamic_insert(target, index, value):
    call target.insert(index, value)
    return target
end

function dynamic_sort(target):
    call target.sort()
    return target
end

escaped = [dynamic_append, dynamic_clear, dynamic_keys, dynamic_pop0, dynamic_pop1, dynamic_pop2, dynamic_count, dynamic_index, dynamic_copy, dynamic_get_method, dynamic_setdefault, dynamic_upper, dynamic_startswith, dynamic_join, dynamic_extend, dynamic_update, dynamic_insert, dynamic_sort]

values = [1, 2]
print dynamic_append(values, 3), dynamic_count(values, 2), dynamic_index(values, 3)
print dynamic_pop1(values, 0), dynamic_pop0(values), values

mapping = {"a": 1}
print dynamic_keys(mapping), dynamic_get_method(mapping, "missing", 9)
print dynamic_setdefault(mapping, "b", 2), mapping
print dynamic_pop1(mapping, "a"), dynamic_pop2(mapping, "missing", 7), mapping
print dynamic_copy(mapping), dynamic_upper("ahoj")
print dynamic_startswith("hello", "he"), dynamic_join("-", ["a", "b"])

extended = [1]
updated = {"a": 1}
inserted = [1, 3]
print dynamic_extend(extended, (2, 3))
print dynamic_update(updated, {"b": 2})
print dynamic_insert(inserted, 1, 2)
print dynamic_sort([3, 1.5, True, 2]), dynamic_sort(["ž", "a", "z"])

integers = IntArray()
floats = FloatArray()
bytes = ByteArray()
print dynamic_append(integers, 4), dynamic_append(floats, 1.5), dynamic_append(bytes, 65)
print dynamic_extend([], integers), dynamic_extend([], floats), dynamic_extend([], bytes)
print dynamic_clear(integers), dynamic_clear(floats), dynamic_clear(bytes)

try:
    call dynamic_clear("immutable")
else:
    print last_error()
end
try:
    print dynamic_keys([1])
else:
    print last_error()
end
try:
    call dynamic_append(ByteArray(), 256)
else:
    print last_error()
end
try:
    print dynamic_startswith("hello", 1)
else:
    print last_error()
end
try:
    print dynamic_join(",", ["a", 1])
else:
    print last_error()
end
try:
    call dynamic_extend([], 42)
else:
    print last_error()
end
try:
    call dynamic_update({}, [])
else:
    print last_error()
end
try:
    call dynamic_insert([], "0", 1)
else:
    print last_error()
end
try:
    print dynamic_pop1([1], "0")
else:
    print last_error()
end
try:
    call dynamic_sort([1, "a"])
else:
    print last_error()
end
