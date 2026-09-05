load cuda
load tensor

# Set LSL_CUDA_WORKER to an absolute worker path outside an installed prefix.
# LSL_CUDA=required makes a real GPU mandatory; auto also runs on CPU hosts.
s = cuda.session()
print "backend", s.backend
a = tensor.from_values([1, 2, 3, 4], [2, 2])
b = tensor.from_values([5, 6, 7, 8], [2, 2])
try:
    da = a.to_device(s)
    db = b.to_device(s)
    product = da.matmul(db)
    result = product.to_host()
    print result.data
    call product.free()
    call da.free()
    call db.free()
else:
    detail = last_error()
    call s.close()
    Error(CudaExampleError: detail)
end
call s.close()
