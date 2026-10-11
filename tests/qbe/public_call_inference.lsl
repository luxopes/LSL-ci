# Caller conversions must not disable safe numeric parameter inference.
function mix(value):
    return (value * 1664525 + 1013904223) & 2147483647
end
limit = Int("12")
value = 1
for index in rang(limit):
    value = mix(value)
end
print value

# Escaped functions and flows through conversion-using bodies retain generic
# argument ABI; specializing only the visible Int call would corrupt Floats.
function identity(value):
    return value
end
function opaque():
    return identity(Float("2.5"))
end
callback = identity
print identity(7), opaque(), callback("value"), callback(3.5)
print type(callback(True)), type(callback(7)), type(callback(3.5))
