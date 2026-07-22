step = 2
forward = []
for value in rang(1, 8, step):
    forward.append(value)
end
print forward

step = -3
backward = []
for value in rang(8, -2, step):
    backward.append(value)
end
print backward

function collect(step):
    result = []
    for value in rang(0, 7, step):
        result.append(value)
    end
    return result
end

print collect(3)

try:
    for value in rang(0, 3, 0):
        print value
    end
else:
    print last_error()
end

try:
    call collect(0)
else:
    print last_error()
end

try:
    call collect(1.5)
else:
    print last_error()
end
