function add_noise(value):
    return value + ((2 + 3) * (4 + 5)) + 0
    print "unreachable"
end

function escaped_increment(value):
    return value + 1
end

function apply(callback, value):
    return callback(value)
end

function small_powers(value):
    return value ^ 0 + value ^ 1 + value ^ 2 + value ^ 3 + value ^ 4
end

i = 0
total = 0
while i != 10000:
    total = add_noise(total)
    i = i + 1
end

if False:
    total = "wrong dead type"
elif (8 * 8) - (3 * 6) == 46:
    print total
else:
    print "bad constant branch"
end

print apply(escaped_increment, 9)
print ((7 + 5) * (9 - 4)) // 3, ((7 + 5) * (9 - 4)) % 7
print small_powers(3)
print ("constant " + "String " + "fold")
