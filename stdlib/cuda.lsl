# Optional CUDA process backend. A worker owns the CUDA Driver/Runtime API and
# speaks the documented lsl-cuda-v1 JSON protocol; every operation has a native
# FloatArray CPU fallback, so CUDA is never a mandatory runtime dependency.

load env
load plugin

class Settings(True):
    ctype Private
    function init(self):
        self.worker = None
        self.policy = None
        self.min_elements = None
    end
end

settings = Settings()

function configure(worker, policy, min_elements):
    settings.worker = worker
    settings.policy = policy
    settings.min_elements = Int(min_elements)
end

function worker_path():
    if settings.worker != None:
        if String(settings.worker) == "":
            return None
        end
        return String(settings.worker)
    end
    worker = env.get("LSL_CUDA_WORKER", "")
    if worker != "":
        return worker
    elif exists("/usr/local/bin/lsl-cuda-worker"):
        return "/usr/local/bin/lsl-cuda-worker"
    elif exists("/usr/bin/lsl-cuda-worker"):
        return "/usr/bin/lsl-cuda-worker"
    end
    return None
end

function policy():
    value = settings.policy
    if value == None:
        value = env.get("LSL_CUDA", "auto")
    end
    value = String(value).lower()
    if value != "auto" and value != "required" and value != "off":
        Error(CudaConfigurationError: "LSL_CUDA must be auto, required, or off")
    end
    return value
end

function minimum_elements():
    if settings.min_elements != None:
        return Int(settings.min_elements)
    end
    text = env.get("LSL_CUDA_MIN_ELEMENTS", "4096")
    value = 4096
    try:
        value = Int(text)
    else:
        Error(CudaConfigurationError: "LSL_CUDA_MIN_ELEMENTS must be an Int")
    end
    if value < 0:
        Error(CudaConfigurationError: "LSL_CUDA_MIN_ELEMENTS cannot be negative")
    end
    return value
end

function available():
    worker = worker_path()
    if policy() == "off" or worker == None or not exists(worker):
        return False
    end
    result = False
    try:
        devices = plugin.request(worker, "cuda.devices", {})
        result = len(devices) > 0
    else:
        result = False
    end
    return result
end

function devices():
    worker = worker_path()
    if policy() == "off" or worker == None or not exists(worker):
        return []
    end
    result = []
    try:
        result = plugin.request(worker, "cuda.devices", {})
    else:
        if policy() == "required":
            Error(CudaUnavailableError: last_error())
        end
    end
    return result
end

function device_count():
    return len(devices())
end

function backend():
    if available():
        return "cuda"
    end
    return "cpu"
end

function to_values(data):
    source = FloatArray(data)
    values = []
    index = 0
    while index < len(source):
        values.append(source[index])
        index += 1
    end
    return values
end

function to_float_array(values):
    result = FloatArray()
    for value in values:
        result.append(Float(value))
    end
    return result
end

function accelerated(size):
    if policy() == "off":
        return False
    end
    worker = worker_path()
    if worker == None or not exists(worker):
        if policy() == "required":
            Error(CudaUnavailableError: "CUDA worker executable was not found")
        end
        return False
    end
    return policy() == "required" or size >= minimum_elements()
end

function request(operation, payload):
    result = None
    caught = ""
    try:
        result = plugin.request(worker_path(), operation, payload)
    else:
        caught = last_error()
    end
    if result == None and policy() == "required":
        Error(CudaExecutionError: caught)
    end
    return result
end

function sum_data(data):
    source = FloatArray(data)
    if accelerated(len(source)):
        value = request("cuda.sum", {"values": to_values(source)})
        if value != None:
            return Float(value)
        end
    end
    return float_sum(source)
end

function dot_data(left, right):
    left_data = FloatArray(left)
    right_data = FloatArray(right)
    if len(left_data) != len(right_data):
        Error(CudaShapeError: "dot arrays have different lengths")
    end
    if accelerated(len(left_data)):
        value = request("cuda.dot", {"left": to_values(left_data), "right": to_values(right_data)})
        if value != None:
            return Float(value)
        end
    end
    return float_dot(left_data, right_data)
end

function axpy_data(alpha, x, y):
    x_data = FloatArray(x)
    y_data = FloatArray(y)
    if len(x_data) != len(y_data):
        Error(CudaShapeError: "axpy arrays have different lengths")
    end
    if accelerated(len(x_data)):
        values = request("cuda.axpy", {"alpha": Float(alpha), "x": to_values(x_data), "y": to_values(y_data)})
        if values != None:
            if len(values) != len(y_data):
                Error(CudaProtocolError: "cuda.axpy returned the wrong element count")
            end
            index = 0
            while index < len(y_data):
                y_data[index] = Float(values[index])
                index += 1
            end
            return
        end
    end
    call float_axpy(Float(alpha), x_data, y_data)
end

function matmul_data(left, right, m, k, n):
    left_data = FloatArray(left)
    right_data = FloatArray(right)
    rows = Int(m)
    inner = Int(k)
    columns = Int(n)
    if len(left_data) != rows * inner or len(right_data) != inner * columns:
        Error(CudaShapeError: "matmul array lengths do not match dimensions")
    end
    if accelerated(rows * inner * columns):
        values = request("cuda.matmul", {"left": to_values(left_data), "right": to_values(right_data), "m": rows, "k": inner, "n": columns})
        if values != None:
            if len(values) != rows * columns:
                Error(CudaProtocolError: "cuda.matmul returned the wrong element count")
            end
            return to_float_array(values)
        end
    end
    return float_matmul(left_data, right_data, rows, inner, columns)
end
