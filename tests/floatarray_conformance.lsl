values = FloatArray()
values.append(1.5)
values.append(-2.25)
values.append(3.0)
print type(values), len(values), String(values), values[0], values[-1]
values[1] = 7.5
values[2] += 0.5
print String(values), float_sum(values), float_dot(values, values)
part = values[1:3]
print type(part), String(part)
zeros = float_zeros(3)
call float_fill(zeros, 2.0)
call float_axpy(0.5, zeros, values)
print String(values), float_sum(values)
a = FloatArray()
b = FloatArray()
for value in [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]:
    a.append(Float(value))
end
for value in [7.0, 8.0, 9.0, 10.0, 11.0, 12.0]:
    b.append(Float(value))
end
product = float_matmul(a, b, 2, 3, 2)
print type(product), String(product), float_sum(product)
print values == FloatArray(values)
try:
    bad = FloatArray([])
else:
    print last_error()
end
try:
    bad = float_zeros(-1)
else:
    print last_error()
end
short = float_zeros(2)
try:
    bad = float_dot(values, short)
else:
    print last_error()
end
