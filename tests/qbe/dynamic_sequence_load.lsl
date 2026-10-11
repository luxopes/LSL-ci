# Escaped receivers retain the public Any ABI while literal indices are native.
function first(target):
    return target[0]
end
function last(target):
    return target[-1]
end
function second(target):
    return target[True]
end
function past(target):
    return target[99]
end
escaped = [first, last, second, past]
for value in [[10, 20], (10, 20), ![10, 20]]:
    check(first(value) == 10, "first boxed slot")
    check(last(value) == 20, "negative boxed slot")
    check(second(value) == 20, "Bool index")
    rejected = False
    try:
        call past(value)
    else:
        rejected = last_error().startswith("IndexError: index out of range")
    end
    check(rejected, "guarded bounds")
end
integers = IntArray()
integers.append(7)
floats = FloatArray()
floats.append(2.5)
bytes = ByteArray()
bytes.append(65)
check(first(integers) == 7, "IntArray fallback")
check(first(floats) == 2.5, "FloatArray fallback")
check(first(bytes) == 65, "ByteArray fallback")
check(first("žluť") == "ž" and last("žluť") == "ť", "Unicode fallback")
check(first({0: "zero"}) == "zero", "Dictionary fallback")
for value in [42, None, 2.5, set([1, 2])]:
    rejected = False
    try:
        call first(value)
    else:
        rejected = last_error().startswith("TypeError:")
    end
    check(rejected, "invalid receiver checked before payload access")
end
print "dynamic sequence load passed"
