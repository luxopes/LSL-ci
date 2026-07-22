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
