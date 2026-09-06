function require(condition, message):
    if not condition:
        Error(TestFailure: message)
    end
end

# Escaped functions retain the public Any ABI instead of specialization.
function dynamic_sorted(value):
    return sorted(value)
end
function dynamic_set(value):
    return set(value)
end
function dynamic_dedup(value):
    return dedup(value)
end
function dynamic_methods(value):
    call value.add(9)
    call value.remove(9)
    call value.discard(8)
    call value.update([7, 7])
    call require(value.issuperset([7]), "dynamic superset")
    call require(value.issubset([1, 2, 3, 7]), "dynamic subset")
    call require(value.isdisjoint([8]), "dynamic disjoint")
    call require(len(value) == 4 and 7 in value, "dynamic length/membership")
    call require(sorted(value.union([8])) == [1, 2, 3, 7, 8], "dynamic union")
    call require(sorted(value.intersection([1, 8])) == [1], "dynamic intersection")
    call require(sorted(value.difference([7])) == [1, 2, 3], "dynamic difference")
    call require(sorted(value.symmetric_difference([7, 8])) == [1, 2, 3, 8], "dynamic symmetric difference")
    copy = value.copy()
    call value.clear()
    call require(not value and len(value) == 0, "dynamic clear/truth")
    return copy
end
function dynamic_index(value):
    return value[0]
end
function dynamic_append(value):
    call value.append(4)
end
function dynamic_assign(value):
    value[0] = 4
end
function dynamic_slice(value):
    return value[:]
end
function dynamic_pop(value):
    return value.pop()
end
function dynamic_bad_pop(value):
    return value.pop(0)
end
function dynamic_key(value):
    return {value: 1}
end
callbacks = [dynamic_sorted, dynamic_set, dynamic_dedup, dynamic_methods, dynamic_index, dynamic_append, dynamic_assign, dynamic_slice, dynamic_pop, dynamic_bad_pop, dynamic_key]

values = [3, 1, 3, 2, 1]
print sorted(values), dedup(values), values
print sorted("žaba"), sorted(Tuple([4, 1, 2]))
print sorted({"z": 1, "a": 2})
unique = set(values)
print type(unique), len(unique), Bool(unique), sorted(unique)
print 3 in unique, 9 not in unique
print unique.add(4), unique.add(3), sorted(unique)
print unique.discard(9), unique.remove(3), sorted(unique)
print unique.copy() == set([4, 2, 1]), unique != set([1])
print sorted(unique.union([5, 1])), sorted(unique.intersection([4, 9]))
print sorted(unique.difference([1])), sorted(unique.symmetric_difference([1, 9]))
print unique.issubset([1, 2, 4, 8]), unique.issuperset([1, 4]), unique.isdisjoint([9])
print unique.update([9, 9]), sorted(unique)
print sorted([item * 2 for item in unique])
call gc()
print sorted(unique)
print unique.clear(), len(unique), Bool(unique), unique
print set(), set("aba"), List(set([3, 3, 1]))
print dedup([[1], [1], {"a": 2}, {"a": 2}, None, None])
print set([Tuple([1, 2]), Tuple([1, 2])])
call require(sorted(values) == [1, 1, 2, 3, 3] and values == [3, 1, 3, 2, 1], "sorted must copy")
call require(dedup(values) == [3, 1, 2] and values == [3, 1, 3, 2, 1], "dedup must copy")
call require(dynamic_methods(set(values)) == set([1, 2, 3, 7]), "dynamic methods")
call require(dynamic_pop(set([9])) == 9, "dynamic pop")
call require(Tuple(set([3, 3, 1])) == Tuple([3, 1]), "Tuple conversion")
call require(set({"a": 1, "b": 2}) == set(["b", "a"]), "dictionary keys")
call require(set([1]) != [1], "Set is not a List")
child = [1]
distinct = dedup([child, [1]])
call child.append(2)
call require(distinct == [[1, 2]], "dedup shallow first object")
cycle1 = []
cycle2 = []
call cycle1.append(cycle1)
call cycle2.append(cycle2)
call require(len(dynamic_dedup([cycle1, cycle2])) == 1, "cyclic dedup")
call require(dedup([set([1, 2]), set([2, 1])]) == [set([1, 2])], "Set structural dedup")
integers = IntArray()
floats = FloatArray()
bytes = ByteArray()
for value in [3, 0, 3, 1]:
    call integers.append(Int(value))
    call floats.append(Float(value))
    call bytes.append(Int(value))
end
call require(dynamic_sorted(integers) == [0, 1, 3, 3], "IntArray sorted/boxing")
call require(dynamic_sorted(floats) == [0.0, 1.0, 3.0, 3.0], "FloatArray sorted")
call require(dynamic_sorted(bytes) == [0, 1, 3, 3], "ByteArray sorted/boxing")
call require(set(integers) == set([0, 1, 3]), "IntArray set")
call require(set(floats) == set([0.0, 1.0, 3.0]), "FloatArray set")
call require(set(bytes) == set([0, 1, 3]), "ByteArray set")
call require(dynamic_sorted([3, 1.5, True, 2]) == [True, 1.5, 2, 3], "numeric sorted")
call require(sorted([]) == [] and dedup([]) == [] and len(set()) == 0, "empty inputs")
for invalid in [None, 1, True, 1.5]:
    for operation in [dynamic_sorted, dynamic_set]:
        caught = False
        try:
            call operation(invalid)
        else:
            caught = last_error().startswith("TypeError:")
        end
        call require(caught, "sorted/set invalid input")
    end
end
for invalid in [None, 1, "abc", Tuple([1]), {"a": 1}, set([1])]:
    caught = False
    try:
        call dynamic_dedup(invalid)
    else:
        caught = last_error().startswith("TypeError:")
    end
    call require(caught, "dedup requires List")
end
for invalid in [[], {}, set(), Tuple([[]]), integers, floats, bytes]:
    caught = False
    try:
        call set([invalid])
    else:
        caught = last_error().startswith("TypeError:")
    end
    call require(caught, "Set rejects mutable elements")
end
for invalid_operation in [dynamic_index, dynamic_append, dynamic_assign, dynamic_slice, dynamic_bad_pop, dynamic_key]:
    caught = False
    try:
        call invalid_operation(set([1, 2]))
    else:
        print last_error()
        caught = True
    end
    call require(caught, "Set forbids sequence mutations/indexing")
end
caught = False
try:
    call dynamic_pop(set())
else:
    caught = last_error().startswith("KeyError:")
end
call require(caught, "empty Set pop")
unique = set([1, 2])
caught = False
try:
    call unique.remove(9)
else:
    caught = last_error().startswith("KeyError:")
end
call require(caught and unique == set([1, 2]), "missing remove")
caught = False
try:
    call unique.update([3, []])
else:
    caught = last_error().startswith("TypeError:")
end
call require(caught and unique == set([1, 2]), "update validates before mutation")
caught = False
try:
    call sorted([1, "a"])
else:
    caught = last_error().startswith("TypeError:")
end
call require(caught, "incompatible sorted elements")
roots = [set([Tuple(["owned-" + String(i), i])]) for i in rang(200)]
call gc()
for i in rang(200):
    call require(Tuple(["owned-" + String(i), i]) in roots[i], "Set GC nested roots")
end
print "sorted/set/dedup conformance passed"
