load cuda

call cuda.configure("/tmp/lsl-cuda-worker", "required", 0)
print cuda.available(), cuda.device_count(), cuda.backend()

left = FloatArray()
right = FloatArray()
for value in [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]:
    left.append(Float(value))
end
for value in [7.0, 8.0, 9.0, 10.0, 11.0, 12.0]:
    right.append(Float(value))
end
print cuda.sum_data(left), cuda.dot_data(left, left)
x = float_zeros(3)
y = float_zeros(3)
call float_fill(x, 2.0)
call float_fill(y, 1.0)
call cuda.axpy_data(3.0, x, y)
print String(y)
print String(cuda.matmul_data(left, right, 2, 3, 2))

call cuda.configure("", "off", 0)
fallback = FloatArray()
fallback.append(2.0)
fallback.append(3.0)
print cuda.backend(), cuda.sum_data(fallback)
