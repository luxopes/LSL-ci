values = IntArray()
print type(values), len(values), Bool(values), String(values)
values.append(1)
values.append(-2)
values.append(3)
print type(values), len(values), Bool(values), String(values)
print values[0], values[-1]
values[1] = 7
values[2] += 5
print String(values)
part = values[1:3]
print type(part), String(part)
other = IntArray()
other.append(7)
other.append(8)
print part == other
collision_owner = []
collision = __lsl_address(collision_owner)
values.append(collision)
print values[-1] == collision
sum = 0
for value in values[0:3]:
    sum += value
end
print sum, List(values[0:3])
del(values[0])
print String(values[0:2])
values.clear()
print len(values), Bool(values), String(values)
