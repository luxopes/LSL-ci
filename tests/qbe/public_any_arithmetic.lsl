# Collection reads cross public Any boundaries. Native integer fast paths must
# preserve boxing, Float fallback, concatenation, errors and Int64 wrapping.
values = [7, True, -9223372036854775808, 9223372036854775807, 2.5, "ab", [1, 2]]
for index in rang(5):
    left = values[index]
    print left + 3, 3 + left, left * -2, -2 * left, left - 3, 3 - left
end
print values[5] + "cd", values[5] * 3, 3 * values[5]
print values[6] + [3]
print values[0] == 7, values[0] != 8, values[0] == 8, values[0] != 7
checks = [values[0] == 7, values[0] != 7]
print checks, type(checks[0]), type(checks[1])
for index in [5, 6]:
    try:
        print values[index] + 2
    else:
        print last_error()
    end
end
try:
    print values[6] * 2
else:
    print last_error()
end
call gc()
print values[0] + values[1], values[0] * values[1]
