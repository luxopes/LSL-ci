values = [1, 2, 3, 4]
call values.reverse()
print values, values.pop(1), values
print values.pop(-1), values
try:
    call values.remove(99)
else:
    print last_error()
end

mapping = {"a": 1, "b": 2}
print mapping.values()
print mapping.items()
copy = mapping.copy()
print copy.pop("a"), copy.pop("missing", "fallback"), copy
try:
    call copy.pop("missing")
else:
    print last_error()
end
call copy.clear()
copy["z"] = 3
print copy, mapping
converted = Dictionary([("x", 7), ("y", 8)])
print converted, Dictionary(converted)
try:
    call Dictionary([(1, 2, 3)])
else:
    print last_error()
end

print "hELLO WORLD".capitalize()
print "žLUŤOUČKÝ".capitalize()
