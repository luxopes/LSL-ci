print min(3.5, 2.1), max(3.5, 2.1)
print min(3, 2.5), max(3, 2.5)
print min(5, 3), max(5, 3)
print min([3.5, 1.2, 2.8]), max([3.5, 1.2, 2.8])
print min([4, 1, 7]), max([4, 1, 7])
print sum([1.5, 2.5, 3.0])
print sum([1, 2.5, 3])
print sum([1, 2, 3])
print -3.5
y = 2.5
print -y
reals = ![2.5, -3.0]
print -reals[0], -reals[1]
ints = [5, -7]
print -ints[0], -ints[1]
function reduce(vals):
    total = 0
    for v in vals:
        total = total + v
    end
    return total
end
print reduce([1.5, 2.5, 3.0])
print reduce([1, 2, 3])
acc = 0.0
for x in [1.0, 2.0, 3.0]:
    acc = acc + x
end
print acc
pows = ![2.0, 3.0]
print pows[0] ** 3, pows[1] ** 2, pows[0] ** -1
ipows = [2, 3]
print ipows[0] ** 3, ipows[1] ** 2
function square(v):
    return v ** 2
end
print square(2.5), square(3)
