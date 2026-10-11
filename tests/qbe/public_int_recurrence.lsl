# Ordinary public-ABI calls and temporary boxed operands, with enough churn
# to trigger automatic GC. The test runner computes an independent oracle.
function mix(value):
    return (value * 1664525 + 1013904223) & 2147483647
end

limit = Int(arg(1))
value = 1
for index in rang(limit):
    value = mix(value)
end
print value
