# Optional CUDA process backend. The bundled worker owns the NVIDIA CUDA
# Runtime; metadata uses lsl-cuda-v1 JSON and FloatArray kernels use raw binary
# stdin/stdout. Every operation retains a native FloatArray CPU fallback.

load env
load plugin

MAX_CUDA_BINARY_ELEMENTS = 2000000

function checked_worker(worker):
    if worker == None:
        return None
    end
    path = String(worker)
    if len(path) == 0:
        return ""
    elif __lsl_text_byte_length(path) > 4095 or chr(0) in path:
        Error(CudaConfigurationError: "CUDA worker path is invalid")
    end
    return path
end

function checked_dimensions(m, k, n):
    rows = Int(m)
    inner = Int(k)
    columns = Int(n)
    if rows < 0 or inner < 0 or columns < 0:
        Error(CudaShapeError: "CUDA dimensions cannot be negative")
    elif inner > 0 and rows > MAX_CUDA_BINARY_ELEMENTS // inner:
        Error(CudaShapeError: "CUDA left matrix exceeds the secure element limit")
    elif columns > 0 and inner > MAX_CUDA_BINARY_ELEMENTS // columns:
        Error(CudaShapeError: "CUDA right matrix exceeds the secure element limit")
    elif columns > 0 and rows > MAX_CUDA_BINARY_ELEMENTS // columns:
        Error(CudaShapeError: "CUDA result exceeds the secure element limit")
    end
    return [rows, inner, columns]
end

class Settings(True):
    ctype Private
    function init(self):
        self.worker = None
        self.policy = None
        self.min_elements = None
        self.probe_worker = None
        self.probe_value = None
    end
end

settings = Settings()

function configure(worker, policy, min_elements):
    checked_policy = String(policy).lower()
    threshold = Int(min_elements)
    if checked_policy != "auto" and checked_policy != "required" and checked_policy != "off":
        Error(CudaConfigurationError: "CUDA policy must be auto, required or off")
    elif threshold < 0:
        Error(CudaConfigurationError: "CUDA minimum element count cannot be negative")
    end
    settings.worker = checked_worker(worker)
    settings.policy = checked_policy
    settings.min_elements = threshold
    settings.probe_worker = None
    settings.probe_value = None
end

function dirname(path):
    slash = -1
    index = 0
    while index < len(path):
        if path[index] == "/":
            slash = index
        end
        index += 1
    end
    if slash < 0:
        return "."
    elif slash == 0:
        return "/"
    end
    return path[0:slash]
end

function worker_path():
    if settings.worker != None:
        if String(settings.worker) == "":
            return None
        end
        return checked_worker(settings.worker)
    end
    worker = env.get("LSL_CUDA_WORKER", "")
    if worker != "":
        return checked_worker(worker)
    end
    executable_directory = dirname(executable_path())
    if exists(executable_directory + "/lsl-cuda-worker"):
        return executable_directory + "/lsl-cuda-worker"
    elif exists(executable_directory + "/cuda/lsl-cuda-worker"):
        return executable_directory + "/cuda/lsl-cuda-worker"
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
    # The worker creates a fresh CUDA context for each operation. Treat this
    # value as work units (elements for vector kernels, m*k*n for matmul) so
    # auto mode only dispatches work large enough to amortize process startup.
    text = env.get("LSL_CUDA_MIN_ELEMENTS", "400000000")
    value = 400000000
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

function probe():
    worker = worker_path()
    if policy() == "off" or worker == None or not exists(worker):
        return None
    end
    if settings.probe_worker != None and String(settings.probe_worker) == worker:
        return settings.probe_value
    end
    result = None
    try:
        value = plugin.request_input(worker, "cuda.probe", {})
        if value.get("verified", False) and value.get("backend", "") == "nvidia-cuda-runtime":
            result = value
        end
    else:
        result = None
    end
    settings.probe_worker = worker
    settings.probe_value = result
    return result
end

function available():
    return probe() != None
end

function devices():
    worker = worker_path()
    if policy() == "off" or worker == None or not exists(worker):
        return []
    end
    result = []
    try:
        result = plugin.request_input(worker, "cuda.devices", {})
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
    if probe() != None:
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
    amount = Int(size)
    if amount < 0:
        Error(CudaShapeError: "CUDA work size cannot be negative")
    elif amount > MAX_CUDA_BINARY_ELEMENTS:
        if policy() == "required":
            Error(CudaShapeError: "CUDA request exceeds the secure binary transport limit")
        end
        return False
    end
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
    if policy() == "required":
        if probe() == None:
            Error(CudaUnavailableError: "CUDA worker did not verify an NVIDIA device")
        end
        return True
    end
    return amount >= minimum_elements() and probe() != None
end

function request(operation, payload):
    result = None
    caught = ""
    try:
        result = plugin.request_input(worker_path(), operation, payload)
    else:
        caught = last_error()
    end
    if result == None and policy() == "required":
        Error(CudaExecutionError: caught)
    end
    return result
end

function binary_request(arguments, payload):
    output = plugin.capture_with_timeout(worker_path(), arguments, payload, 120)
    if capture_status() == 0:
        return output
    end
    return None
end

function sum_data(data):
    source = FloatArray(data)
    if accelerated(len(source)):
        output = binary_request(["--binary", "sum", String(len(source))], __lsl_floatarray_bytes(source))
        if output != None and __lsl_text_byte_length(output) == 8:
            values = __lsl_floatarray_from_bytes(output)
            return values[0]
        end
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
        payload = __lsl_floatarray_bytes(left_data) + __lsl_floatarray_bytes(right_data)
        output = binary_request(["--binary", "dot", String(len(left_data))], payload)
        if output != None and __lsl_text_byte_length(output) == 8:
            values = __lsl_floatarray_from_bytes(output)
            return values[0]
        end
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
        payload = __lsl_floatarray_bytes(x_data) + __lsl_floatarray_bytes(y_data)
        output = binary_request(["--binary", "axpy", String(alpha), String(len(x_data))], payload)
        if output != None and __lsl_text_byte_length(output) == len(y_data) * 8:
            binary_values = __lsl_floatarray_from_bytes(output)
            index = 0
            while index < len(y_data):
                y_data[index] = binary_values[index]
                index += 1
            end
            return
        end
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
    dimensions = checked_dimensions(m, k, n)
    rows = Int(dimensions[0])
    inner = Int(dimensions[1])
    columns = Int(dimensions[2])
    if len(left_data) != rows * inner or len(right_data) != inner * columns:
        Error(CudaShapeError: "matmul array lengths do not match dimensions")
    end
    if accelerated(rows * inner * columns):
        payload = __lsl_floatarray_bytes(left_data) + __lsl_floatarray_bytes(right_data)
        arguments = ["--binary", "matmul", String(rows), String(inner), String(columns)]
        output = binary_request(arguments, payload)
        if output != None and __lsl_text_byte_length(output) == rows * columns * 8:
            binary_values = __lsl_floatarray_from_bytes(output)
            return binary_values
        end
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
