load cuda

worker = arg(1)
call cuda.configure(worker, "required", 0)
probe = cuda.probe()
if probe == None or not probe.get("verified", False):
    Error(TestFailure: "real CUDA device probe did not execute")
end
if probe.get("backend", "") != "nvidia-cuda-runtime":
    Error(TestFailure: "CUDA worker did not report the NVIDIA runtime backend")
end
devices = cuda.devices()
if len(devices) == 0 or devices[0].get("name", "") != probe.get("name", ""):
    Error(TestFailure: "CUDA device enumeration differs from verified probe")
end

left = FloatArray()
right = FloatArray()
for value in [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]:
    left.append(Float(value))
end
for value in [7.0, 8.0, 9.0, 10.0, 11.0, 12.0]:
    right.append(Float(value))
end
if cuda.sum_data(left) != 21.0:
    Error(TestFailure: "CUDA sum result differs")
end
if cuda.dot_data(left, left) != 91.0:
    Error(TestFailure: "CUDA dot result differs")
end
large = float_zeros(4097)
call float_fill(large, 1.0)
if cuda.sum_data(large) != 4097.0 or cuda.dot_data(large, large) != 4097.0:
    Error(TestFailure: "recursive CUDA reduction result differs")
end

x = float_zeros(3)
y = float_zeros(3)
call float_fill(x, 2.0)
call float_fill(y, 1.0)
call cuda.axpy_data(3.0, x, y)
if y[0] != 7.0 or y[1] != 7.0 or y[2] != 7.0:
    Error(TestFailure: "CUDA axpy result differs")
end

product = cuda.matmul_data(left, right, 2, 3, 2)
if product[0] != 58.0 or product[1] != 64.0 or product[2] != 139.0 or product[3] != 154.0:
    Error(TestFailure: "CUDA matmul result differs")
end

print "cuda-hardware-ok", probe["name"], probe["compute_capability"]
