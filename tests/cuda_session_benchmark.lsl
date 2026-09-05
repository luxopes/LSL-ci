load cuda
load time

size = 512
if arg(1) != None:
    size = Int(arg(1))
end
worker = arg(2)
if worker == None:
    worker = "./cuda/lsl-cuda-worker"
end
call cuda.configure(worker, "required", 0)
left = float_zeros(size * size)
call float_fill(left, 1.0)
start = time.perf_counter()
s = cuda.session()
a = s.upload(left)
b = s.upload(left)
startup = time.perf_counter() - start
warm = a.matmul(b, size, size, size)
call warm.free()
cpu_times = []
gpu_times = []
for repeat in rang(5):
    start = time.perf_counter()
    cpu = float_matmul(left, left, size, size, size)
    cpu_times.append(time.perf_counter() - start)
    start = time.perf_counter()
    gpu = a.matmul(b, size, size, size)
    host = gpu.download()
    gpu_times.append(time.perf_counter() - start)
    if float_sum(cpu) != Float(size * size * size) or float_sum(host) != float_sum(cpu):
        Error(TestFailure: "persistent CUDA benchmark checksum differs")
    end
    call gpu.free()
    call gc()
end
call cpu_times.sort()
call gpu_times.sort()
print "matrix", size, "startup_upload_seconds", startup
print "median_cpu_seconds", cpu_times[2], "median_cuda_download_seconds", gpu_times[2]
print "speedup", Float(cpu_times[2]) / Float(gpu_times[2]), "checksum", size * size * size
call s.close()
