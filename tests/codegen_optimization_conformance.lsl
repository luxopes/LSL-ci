# lsl: unchecked-intarray

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

function recursive_array_sum(values, index):
    if index == 0:
        return values[0]
    end
    values[index] += index
    return values[index] + recursive_array_sum(values, index - 1)
end

function bool_result(value):
    return value != 0
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
hot_values = IntArray()
hot_values.append(3)
hot_values.append(5)
hot_values.append(7)
print recursive_array_sum(hot_values, 2), String(hot_values)
hot_values[0] |= 8
hot_values[1] &= 6
hot_values[2] ~= 1
print String(hot_values)
if bool_result(1) and not bool_result(0):
    print "typed Bool branch"
else:
    print "bad Bool branch"
end
print ("constant " + "String " + "fold")
