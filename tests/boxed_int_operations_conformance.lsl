load json

a = __lsl_box_int(-7)
b = __lsl_box_int(3)
z = __lsl_box_int(0)
two = __lsl_box_int(2)
print a, b, z
print String(a), Int(a), Float(a), Bool(a), Bool(z)
print a + b, a - b, a * b, a / b, a // b, a % b, b ^ two
print abs(a), -a
print a < b, a <= -7, a == -7, a != b, b > z
print a + 2.5, 2.5 + a, b * 2.5, 2.0 ^ b
values = [a, b, z]
print values, values[two], values.index(b), values.count(z)
values[__lsl_box_int(1)] = __lsl_box_int(8)
print values, sum(values), min(values), max(values)
print json.encode(values)
reals = RealArray([a, b, 2.5])
print reals, reals[__lsl_box_int(1)] + 0.5
print chr(__lsl_box_int(65))
for number in rang(z, __lsl_box_int(6), two):
    print number
end
