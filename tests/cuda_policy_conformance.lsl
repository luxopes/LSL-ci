load cuda
load tensor

values = cuda.to_float_array([2.0, 3.0])
call cuda.configure(arg(1) + "/cuda-bad-worker", "auto", 0)
print "malformed-auto", cuda.sum_data(values)
call cuda.configure(arg(1) + "/cuda-bad-worker", "required", 0)
caught = False
try:
    call cuda.axpy_data(2.0, values, values)
else:
    caught = True
end
print "malformed-required", caught, String(values)
call cuda.configure("/missing/lsl-cuda-worker", "auto", 0)
print "missing-auto", cuda.sum_data(values), cuda.available()
session = cuda.session()
print "missing-session", session.backend
call session.close()
call cuda.configure("/missing/lsl-cuda-worker", "required", 0)
caught = False
try:
    call cuda.devices()
else:
    caught = True
end
print "missing-required", caught
call cuda.configure("", "off", 0)
empty = float_zeros(0)
matrix = cuda.matmul_data(empty, empty, 2000001, 0, 1)
print "cpu-limit", len(matrix), float_sum(matrix)
zero = tensor.zeros([0, 3])
print "empty-tensor", zero.size(), zero.sum(), zero.strides
session = cuda.session()
device = zero.to_device(session)
transposed = device.transpose()
print "empty-device", transposed.shape, transposed.sum()
call session.close()
