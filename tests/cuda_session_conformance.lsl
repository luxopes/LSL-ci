load cuda
load tensor

worker = arg(2)
if worker == None:
    call cuda.configure("", "off", 0)
else:
    call cuda.configure(worker, "required", 0)
end
s = cuda.session()
a = s.upload(cuda.to_float_array([1.0, -2.0, 3.0, 4.0, 5.0, 6.0]))
b = s.upload(cuda.to_float_array([7.0, 8.0, 9.0, 10.0, 11.0, 12.0]))
print a.sum(), a.dot(a)
c = a.matmul(b, 2, 3, 2)
print String(c.download())
d = a.add(b)
print String(d.download())
call d.free()
d = a.multiply(b)
print String(d.download())
call d.free()
d = a.relu()
print String(d.download())
call d.free()
d = a.scale(2.0)
print String(d.download())
call d.free()
d = a.transpose(2, 3)
print String(d.download())
call d.free()
call a.axpy(2.0, b)
print String(a.download())
call a.fill(3.0)
print a.sum()
call a.free()
call a.free()
caught = False
try:
    call a.sum()
else:
    caught = True
end
print "freed", caught
z = s.zeros(0)
print z.sum(), z.dot(z), String(z.download())
call z.free()
call b.free()
call c.free()
print s.info()["buffers"], s.info()["elements"]
call s.synchronize()
call s.close()
call s.close()
caught = False
try:
    call s.zeros(1)
else:
    caught = True
end
print "closed", caught

s = cuda.session()
another = cuda.session()
a = s.upload(cuda.to_float_array([2.0, 4.0]))
b = another.upload(cuda.to_float_array([1.0, 2.0]))
caught = False
try:
    call a.dot(b)
else:
    caught = True
end
print "ownership", caught
call another.close()
call b.free()
snapshot = a.download()
snapshot[0] = 999.0
print "snapshot", a.sum()
b = s.upload(cuda.to_float_array([1.0, 2.0]))
d = a.subtract(b)
print String(d.download())
call d.free()
d = a.divide(b)
print String(d.download())
call d.free()
z = s.zeros(0)
d = z.matmul(z, 2, 0, 3)
print "empty-inner", String(d.download())
call d.free()
call z.free()
special = s.upload(cuda.to_float_array([-0.0, 1.0 / 0.0, 0.0 / 0.0]))
downloaded = special.download()
print "ieee", __lsl_float_bits(downloaded[0]) == __lsl_float_bits(-0.0), downloaded[1] > 1e300, downloaded[2] != downloaded[2]
call special.free()
if s.backend == "cuda":
    caught = False
    try:
        call s.request({"operation": "download", "id": 2147483647}, "")
    else:
        caught = True
    end
    if not caught or a.sum() != 6.0:
        Error(TestFailure: "invalid device handle broke the session")
    end
end
host = tensor.from_values([1, 2, 3, 4, 5, 6], [2, 3])
view = host.view([3, 2], [1, 3], 0)
print "view", String(view.contiguous_data()), view.sum()
caught = False
try:
    call view.reshape([6])
else:
    caught = True
end
print "strides", caught
device = view.to_device(s)
transposed = device.transpose()
restored = transposed.to_host()
print "tensor", restored.shape, String(restored.contiguous_data())
product = device.matmul(transposed)
product_host = product.to_host()
print "device-matmul", product_host.shape, String(product_host.contiguous_data())
scaled = device.scale(2.0)
added = scaled.add(device)
print "device-elementwise", added.sum()
call scaled.free()
call added.free()
call product.free()
call transposed.free()
call device.free()
call a.free()
call b.free()
print "released", s.info()["buffers"], s.info()["elements"]
large = float_zeros(2000000)
call float_fill(large, 1.0)
boundary = s.upload(large)
call gc()
print "boundary", boundary.sum(), len(boundary.download())
call boundary.free()
caught = False
try:
    call s.zeros(2000001)
else:
    caught = True
end
print "buffer-limit", caught
call s.close()
