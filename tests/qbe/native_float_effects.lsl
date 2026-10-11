# Loading an operand's payload must respect evaluation and aliasing order.
events = []
function left_value():
    events.append("left")
    return 1.25
end
function right_value():
    events.append("right")
    call gc()
    return 2.5
end
print left_value() + right_value(), ",".join(events)
function mutate(value):
    return __lsl_float_accumulate(value, 5)
end
anchor = 1.0
print anchor + mutate(anchor), anchor
anchor = 1.0
print (anchor + 0.5) + mutate(anchor), anchor
try:
    print 1.0 + (1 / 0)
else:
    print last_error()
end
try:
    print (7 / False) * 0.5
else:
    print last_error()
end
print __lsl_float_bits(1.0 / -0.0) == -4503599627370496
