load tensor

t = tensor.Tensor(RealArray([1, 2, 3, 4, 5, 6]), [2, 3], [3, 1], 0, "Float64")
print t.rank(), t.size(), t.dtype, t.shape, t.strides
print t.get([0, 0]), t.get([1, 2]), t.get([-1, -2])
t.set([0, 1], 20.5)
print t.get([0, 1]), t.data
flat = tensor.Tensor(t.data, [6], [1], 0, "Float64")
flat.set([2], 30)
print flat.shape, flat.strides, flat.data, t.get([1, 0])
column = tensor.Tensor(t.data, [2], [3], 1, "Float64")
print column.get([0]), column.get([1])
column.set([1], 50)
print t.get([1, 1]), flat.get([4])
zero = tensor.Tensor(RealArray([0.0, 0.0, 0.0, 0.0]), [2, 2], [2, 1], 0, "Float64")
print zero.shape, zero.data

caught = ""
try:
    call t.reshape([5])
else:
    caught = last_error()
end
print caught

left = FloatArray()
right = FloatArray()
for value in [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]:
    left.append(Float(value))
end
for value in [7.0, 8.0, 9.0, 10.0, 11.0, 12.0]:
    right.append(Float(value))
end
product = tensor.matmul_data(left, right, 2, 3, 2)
print type(product), String(product), tensor.dot_data(product, product)
x = float_zeros(3)
y = float_zeros(3)
call float_fill(x, 2.0)
call float_fill(y, 1.0)
call tensor.axpy_data(3.0, x, y)
print String(y)
left_tensor = tensor.Tensor(left, [2, 3], [3, 1], 0, "Float64")
right_tensor = tensor.Tensor(right, [3, 2], [2, 1], 0, "Float64")
native_product = left_tensor.matmul(right_tensor.data, right_tensor.shape)
print native_product.get([0, 0]), native_product.get([1, 1]), native_product.sum()
native_zero = tensor.zeros([2, 2])
print native_zero.get([1, 1]), native_zero.sum()
