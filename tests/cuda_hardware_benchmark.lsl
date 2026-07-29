load cuda
load time

call cuda.configure("cuda/lsl-cuda-worker", "required", 0)

size = 128
if arg(1) != None:
    size = Int(arg(1))
end
count = size * size
left = float_zeros(count)
right = float_zeros(count)
call float_fill(left, 1.0)
call float_fill(right, 1.0)

cpu_start = time.perf_counter()
cpu_result = float_matmul(left, right, size, size, size)
cpu_seconds = time.perf_counter() - cpu_start

gpu_start = time.perf_counter()
gpu_result = cuda.matmul_data(left, right, size, size, size)
gpu_seconds = time.perf_counter() - gpu_start

if cpu_result[0] != Float(size) or gpu_result[0] != Float(size):
    Error(TestFailure: "CUDA benchmark checksum differs")
end

print "matrix", size, "cpu_seconds", cpu_seconds, "cuda_end_to_end_seconds", gpu_seconds
