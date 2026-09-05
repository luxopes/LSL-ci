# Optional CUDA process backend. The bundled worker owns the NVIDIA CUDA
# Runtime; metadata uses lsl-cuda-v1 JSON and FloatArray kernels use raw binary
# stdin/stdout. Every operation retains a native FloatArray CPU fallback.

load env
load plugin
load json
load fd
load time

MAX_CUDA_BINARY_ELEMENTS = 2000000
MAX_CUDA_CPU_ELEMENTS = 67108864

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
    elif rows > MAX_CUDA_CPU_ELEMENTS or inner > MAX_CUDA_CPU_ELEMENTS or columns > MAX_CUDA_CPU_ELEMENTS:
        Error(CudaShapeError: "CUDA dimensions exceed the element limit")
    elif inner > 0 and rows > MAX_CUDA_CPU_ELEMENTS // inner:
        Error(CudaShapeError: "CUDA left matrix exceeds the secure element limit")
    elif columns > 0 and inner > MAX_CUDA_CPU_ELEMENTS // columns:
        Error(CudaShapeError: "CUDA right matrix exceeds the secure element limit")
    elif columns > 0 and rows > MAX_CUDA_CPU_ELEMENTS // columns:
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
        self.probe_device = None
        self.device = None
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

function device():
    value = settings.device
    if value == None:
        value = env.get("LSL_CUDA_DEVICE", "0")
    end
    index = Int(value)
    if index < 0 or index > 255:
        Error(CudaConfigurationError: "CUDA device must be between 0 and 255")
    end
    return index
end

function set_device(index):
    value = Int(index)
    if value < 0 or value > 255:
        Error(CudaConfigurationError: "CUDA device must be between 0 and 255")
    end
    settings.device = value
    settings.probe_worker = None
    settings.probe_value = None
end

function worker_capture(arguments, payload):
    # The isolated process environment is empty; pass device selection explicitly.
    args = ["--device", String(device())]
    for argument in arguments:
        args.append(argument)
    end
    return plugin.capture_with_timeout(worker_path(), args, payload, 120)
end

function worker_request(operation, payload):
    encoded = String(json.encode({"abi": 1, "operation": operation, "device": device(), "payload": payload}))
    if __lsl_text_byte_length(encoded) > 4194304:
        Error(CudaProtocolError: "CUDA JSON request exceeds 4 MiB")
    end
    output = plugin.capture_with_timeout(worker_path(), [], encoded, 120)
    return plugin.checked_response(output)
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
    if settings.probe_worker != None and String(settings.probe_worker) == worker and settings.probe_device == device():
        return settings.probe_value
    end
    result = None
    try:
        value = worker_request("cuda.probe", {})
        if value.get("verified", False) and value.get("backend", "") == "nvidia-cuda-runtime":
            result = value
        end
    else:
        result = None
    end
    settings.probe_worker = worker
    settings.probe_value = result
    settings.probe_device = device()
    return result
end

function available():
    return probe() != None
end

function devices():
    worker = worker_path()
    if policy() == "off" or worker == None or not exists(worker):
        if policy() == "required":
            Error(CudaUnavailableError: "CUDA worker executable was not found")
        end
        return []
    end
    result = []
    try:
        result = worker_request("cuda.devices", {})
        if type(result) != "List":
            Error(CudaProtocolError: "CUDA devices response must be a List")
        end
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

function accelerated_work(size, elements):
    amount = Int(size)
    if amount < 0:
        Error(CudaShapeError: "CUDA work size cannot be negative")
    elif Int(elements) > MAX_CUDA_BINARY_ELEMENTS:
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

function accelerated(size):
    return accelerated_work(size, size)
end

function request(operation, payload):
    result = None
    caught = ""
    try:
        result = worker_request(operation, payload)
        if operation == "cuda.sum" or operation == "cuda.dot":
            if type(result) != "Int" and type(result) != "Float":
                Error(CudaProtocolError: "CUDA reduction must return a number")
            end
            result = Float(result)
        elif operation == "cuda.axpy" or operation == "cuda.matmul":
            expected = 0
            if operation == "cuda.axpy":
                expected = len(payload["y"])
            else:
                expected = Int(payload["m"]) * Int(payload["n"])
            end
            if type(result) != "List" or len(result) != expected:
                Error(CudaProtocolError: "CUDA response has the wrong element count")
            end
            # Validate every element before exposing or mutating caller data.
            converted = FloatArray()
            for item in result:
                if type(item) != "Int" and type(item) != "Float":
                    Error(CudaProtocolError: "CUDA result contains a non-number")
                end
                converted.append(Float(item))
            end
            result = converted
        end
    else:
        caught = last_error()
        result = None
    end
    if result == None and policy() == "required":
        Error(CudaExecutionError: caught)
    end
    return result
end

function binary_request(arguments, payload):
    value = probe()
    if value == None or not value.get("binary", False):
        return None
    end
    try:
        output = worker_capture(arguments, payload)
        if capture_status() == 0:
            return output
        end
        if policy() == "required":
            Error(CudaExecutionError: capture_stderr())
        end
    else:
        if policy() == "required":
            Error(CudaExecutionError: last_error())
        end
    end
    return None
end

function legacy_available(count):
    value = probe()
    if value != None and value.get("binary", False):
        if policy() == "required":
            Error(CudaProtocolError: "CUDA binary response has the wrong byte count")
        end
        return False
    end
    if Int(count) > 131072:
        if policy() == "required":
            Error(CudaProtocolError: "legacy CUDA worker exceeds the JSON element limit")
        end
        return False
    end
    return True
end

function sum_data(data):
    source = FloatArray(data)
    if accelerated(len(source)):
        output = binary_request(["--binary", "sum", String(len(source))], __lsl_floatarray_bytes(source))
        if output != None and __lsl_text_byte_length(output) == 8:
            values = __lsl_floatarray_from_bytes(output)
            return values[0]
        end
        value = None
        if legacy_available(len(source)):
            value = request("cuda.sum", {"values": to_values(source)})
        end
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
        value = None
        if legacy_available(len(left_data)):
            value = request("cuda.dot", {"left": to_values(left_data), "right": to_values(right_data)})
        end
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
        values = None
        if legacy_available(len(x_data)):
            values = request("cuda.axpy", {"alpha": Float(alpha), "x": to_values(x_data), "y": to_values(y_data)})
        end
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
    if accelerated_work(rows * inner * columns, max(max(rows * inner, inner * columns), rows * columns)):
        payload = __lsl_floatarray_bytes(left_data) + __lsl_floatarray_bytes(right_data)
        arguments = ["--binary", "matmul", String(rows), String(inner), String(columns)]
        output = binary_request(arguments, payload)
        if output != None and __lsl_text_byte_length(output) == rows * columns * 8:
            binary_values = __lsl_floatarray_from_bytes(output)
            return binary_values
        end
        values = None
        if legacy_available(max(max(len(left_data), len(right_data)), rows * columns)):
            values = request("cuda.matmul", {"left": to_values(left_data), "right": to_values(right_data), "m": rows, "k": inner, "n": columns})
        end
        if values != None:
            if len(values) != rows * columns:
                Error(CudaProtocolError: "cuda.matmul returned the wrong element count")
            end
            return to_float_array(values)
        end
    end
    return float_matmul(left_data, right_data, rows, inner, columns)
end

# Persistent ABI 2. One session belongs to one host thread. Explicit close/free
# is deterministic; process exit closes the socket and frees every device buffer.
function session_count(value):
    count = Int(value)
    if count < 0 or count > MAX_CUDA_BINARY_ELEMENTS:
        Error(CudaShapeError: "CUDA buffer must contain 0..2000000 elements")
    end
    return count
end

function session_send(handle, text, deadline):
    data = String(text)
    count = __lsl_text_byte_length(data)
    offset = 0
    # String payload is inline at +16. Keep data rooted for the entire syscall.
    while offset < count:
        sent = __lsl_syscall6(44, Int(handle), __lsl_address(data) + 16 + offset, count - offset, 16448, 0, 0)
        if sent > 0:
            offset += sent
        elif sent == -11 or sent == -4:
            if clock() >= Float(deadline):
                Error(CudaTimeoutError: "CUDA session write timed out")
            end
            call time.sleep(0.001)
        else:
            Error(CudaProtocolError: "CUDA session connection closed while writing")
        end
    end
end

function session_read(handle, size, deadline):
    count = Int(size)
    if count < 0 or count > MAX_CUDA_BINARY_ELEMENTS * 8:
        Error(CudaProtocolError: "CUDA session response exceeds its byte limit")
    end
    bytes = __lsl_byte_zeros(count)
    offset = 0
    while offset < count:
        received = __lsl_syscall6(45, Int(handle), __lsl_data_address(bytes) + offset, count - offset, 64, 0, 0)
        if received > 0:
            offset += received
        elif received == -11 or received == -4:
            if clock() >= Float(deadline):
                Error(CudaTimeoutError: "CUDA session read timed out")
            end
            call time.sleep(0.001)
        else:
            Error(CudaProtocolError: "CUDA session connection closed while reading")
        end
    end
    return __lsl_text_from_bytes(bytes, 0, count)
end

function scalar_bytes(value):
    values = FloatArray()
    values.append(Float(value))
    return __lsl_floatarray_bytes(values)
end

class Session(True):
    ctype Public
    function init(self):
        self.handle = -1
        self.closed = False
        self.backend = "cpu"
        self.device = device()
        self.thread = __lsl_syscall(186, 0, 0, 0, 0)
        self.buffers = 0
        self.elements = 0
        self.next_id = 1
        if policy() != "off":
            caught = ""
            try:
                if worker_path() == None:
                    Error(CudaUnavailableError: "CUDA worker executable was not found")
                end
                output = worker_capture(["--session"], "")
                path = plugin.checked_response(output)
                self.handle = fd.connect_unix(String(path))
                # Do not leak the live session into programs launched outside
                # the clean process helpers either (F_SETFD, FD_CLOEXEC).
                if __lsl_syscall(72, self.handle, 2, 1, 0) < 0:
                    Error(CudaUnavailableError: "cannot protect CUDA session descriptor")
                end
                self.backend = "cuda"
                call self.request({"operation": "info"}, "")
            else:
                caught = last_error()
            end
            if caught != "":
                if self.handle >= 0:
                    call fd.close(self.handle)
                end
                self.handle = -1
                self.closed = False
                self.backend = "cpu"
                if policy() == "required":
                    self.closed = True
                    Error(CudaUnavailableError: caught)
                end
            end
        end
    end

    function check(self):
        return session_check(self)
    end

    function request(self, fields, payload):
        return session_request(self, fields, payload)
    end

    function make_buffer(self, fields, payload, data, count):
        return session_make_buffer(self, fields, payload, data, count)
    end

    function upload(self, values):
        return upload_to(self, values)
    end

    function zeros(self, count):
        call self.check()
        size = session_count(count)
        data = FloatArray()
        if self.backend == "cpu":
            data = float_zeros(size)
        end
        return self.make_buffer({"operation": "zeros", "count": size}, "", data, size)
    end

    function synchronize(self):
        call self.check()
        if self.backend == "cuda":
            call self.request({"operation": "synchronize"}, "")
        end
    end

    function info(self):
        call self.check()
        if self.backend == "cuda":
            return self.request({"operation": "info"}, "")
        end
        return {"backend": "cpu", "device": self.device, "buffers": self.buffers, "elements": self.elements}
    end

    function close(self):
        return session_close(self)
    end
end

class Buffer(True):
    ctype Public
    function init(self, owner, id, count, data):
        self.owner = owner
        self.id = Int(id)
        self.count = Int(count)
        self.data = FloatArray(data)
        self.freed = False
    end

    function check(self):
        call session_check(self.owner)
        if self.freed:
            Error(CudaResourceError: "CUDA buffer is freed")
        end
    end

    function compatible(self, other):
        return buffer_compatible(self, other)
    end

    function download(self):
        return buffer_download(self)
    end

    function free(self):
        return buffer_free(self)
    end

    function reduce(self, operation, other):
        return buffer_reduce(self, operation, other)
    end

    function sum(self):
        return self.reduce("sum", None)
    end

    function dot(self, other):
        return self.reduce("dot", other)
    end

    function elementwise(self, operation, other, alpha):
        return buffer_elementwise(self, operation, other, alpha)
    end

    function add(self, other):
        return self.elementwise("add", other, 0.0)
    end
    function subtract(self, other):
        return self.elementwise("subtract", other, 0.0)
    end
    function multiply(self, other):
        return self.elementwise("multiply", other, 0.0)
    end
    function divide(self, other):
        return self.elementwise("divide", other, 0.0)
    end
    function scale(self, alpha):
        return self.elementwise("scale", None, alpha)
    end
    function relu(self):
        return self.elementwise("relu", None, 0.0)
    end
    function fill(self, value):
        call self.elementwise("fill", None, value)
        return self
    end
    function axpy(self, alpha, other):
        call self.elementwise("axpy", other, alpha)
        return self
    end

    function matmul(self, other, m, k, n):
        return buffer_matmul(self, other, m, k, n)
    end

    function transpose(self, m, n):
        return buffer_transpose(self, m, n)
    end
end

function session_check(self):
    if self["closed"]:
        Error(CudaResourceError: "CUDA session is closed")
    elif self["thread"] != __lsl_syscall(186, 0, 0, 0, 0):
        Error(CudaResourceError: "use a separate CUDA session for each thread")
    end
end

function session_request(self, fields, payload):
    call session_check(self)
    if self["backend"] != "cuda":
        Error(CudaResourceError: "CPU session has no worker connection")
    end
    header = Dictionary(fields)
    header["abi"] = 2
    header["bytes"] = __lsl_text_byte_length(String(payload))
    encoded = String(json.encode(header))
    length = __lsl_text_byte_length(encoded)
    if length > 4096 or Int(header["bytes"]) > MAX_CUDA_BINARY_ELEMENTS * 8:
        Error(CudaProtocolError: "CUDA session request exceeds its frame limit")
    end
    prefix = __lsl_byte_zeros(4)
    index = 0
    while index < 4:
        prefix[index] = length % 256
        length = length // 256
        index += 1
    end
    result = None
    caught = ""
    try:
        deadline = clock() + 120.0
        call session_send(self["handle"], __lsl_text_from_bytes(prefix, 0, 4), deadline)
        call session_send(self["handle"], encoded, deadline)
        call session_send(self["handle"], String(payload), deadline)
        raw = String(session_read(self["handle"], 4, deadline))
        size = __lsl_text_byte(raw, 0) + __lsl_text_byte(raw, 1) * 256 + __lsl_text_byte(raw, 2) * 65536 + __lsl_text_byte(raw, 3) * 16777216
        if size < 1 or size > 4096:
            Error(CudaProtocolError: "invalid CUDA session response header")
        end
        result = json.decode(session_read(self["handle"], size, deadline))
        if type(result) != "Dictionary" or result.get("abi", 0) != 2:
            Error(CudaProtocolError: "CUDA session response ABI mismatch")
        end
        size = Int(result.get("bytes", -1))
        if size < 0 or size % 8 != 0:
            Error(CudaProtocolError: "invalid CUDA session response payload")
        end
        result["data"] = session_read(self["handle"], size, deadline)
    else:
        caught = last_error()
    end
    if caught != "":
        call fd.close(self["handle"])
        self["handle"] = -1
        self["closed"] = True
        Error(CudaProtocolError: caught)
    end
    if not result.get("ok", False):
        Error(CudaExecutionError: String(result.get("error", "CUDA session failed")))
    end
    return result
end

function session_make_buffer(self, fields, payload, data, count):
    call session_check(self)
    size = session_count(count)
    if self["buffers"] >= 256 or size > 32000000 - self["elements"]:
        Error(CudaResourceError: "CUDA session allocation limit exceeded")
    end
    id = self["next_id"]
    if self["backend"] == "cuda":
        result = session_request(self, fields, payload)
        id = Int(result.get("id", 0))
        if id <= 0 or Int(result.get("count", -1)) != size:
            call session_close(self)
            Error(CudaProtocolError: "invalid CUDA buffer allocation response")
        end
    end
    self["next_id"] += 1
    self["buffers"] += 1
    self["elements"] += size
    return Buffer(self, id, size, data)
end

function session_close(self):
    if not self["closed"]:
        call session_check(self)
        # EOF is the ownership boundary; no allocation or round trip is
        # needed to close, including after a failed kernel or broken peer.
        if self["handle"] >= 0:
            call fd.close(self["handle"])
        end
        self["handle"] = -1
        self["closed"] = True
        self["buffers"] = 0
        self["elements"] = 0
    end
end

function buffer_check(buffer):
    call session_check(buffer["owner"])
    if buffer["freed"]:
        Error(CudaResourceError: "CUDA buffer is freed")
    end
end

function buffer_download(self):
    call buffer_check(self)
    if self["owner"]["backend"] == "cuda":
        result = session_request(self["owner"], {"operation": "download", "id": self["id"]}, "")
        payload = String(result["data"])
        if __lsl_text_byte_length(payload) != self["count"] * 8:
            Error(CudaProtocolError: "CUDA download count differs")
        end
        return __lsl_floatarray_from_bytes(payload)
    end
    return __lsl_floatarray_from_bytes(__lsl_floatarray_bytes(FloatArray(self["data"])))
end

function buffer_free(self):
    if not self["freed"]:
        if not self["owner"]["closed"]:
            call buffer_check(self)
            if self["owner"]["backend"] == "cuda":
                call session_request(self["owner"], {"operation": "free", "id": self["id"]}, "")
            end
            self["owner"]["buffers"] -= 1
            self["owner"]["elements"] -= self["count"]
        end
        self["freed"] = True
        self["data"] = FloatArray()
    end
end

function buffer_compatible(self, other):
    call buffer_check(self)
    call buffer_check(other)
    if __lsl_address(self["owner"]) != __lsl_address(other["owner"]):
        Error(CudaResourceError: "CUDA buffers belong to different sessions")
    end
end

function buffer_reduce(self, operation, other):
    call buffer_check(self)
    if operation != "sum" and operation != "dot":
        Error(CudaConfigurationError: "unknown CUDA reduction")
    end
    fields = {"operation": operation, "id": self["id"]}
    if operation == "dot":
        call buffer_compatible(self, other)
        if self["count"] != other["count"]:
            Error(CudaShapeError: "dot arrays have different lengths")
        end
        fields["other"] = other["id"]
    end
    if self["owner"]["backend"] == "cuda":
        result = session_request(self["owner"], fields, "")
        payload = String(result["data"])
        if __lsl_text_byte_length(payload) != 8:
            Error(CudaProtocolError: "CUDA reduction must return one Float64")
        end
        data = __lsl_floatarray_from_bytes(payload)
        return data[0]
    end
    if operation == "dot":
        return float_dot(FloatArray(self["data"]), FloatArray(other["data"]))
    end
    return float_sum(FloatArray(self["data"]))
end

function buffer_elementwise(self, operation, other, alpha):
    call buffer_check(self)
    if operation != "add" and operation != "subtract" and operation != "multiply" and operation != "divide" and operation != "scale" and operation != "relu" and operation != "fill" and operation != "axpy":
        Error(CudaConfigurationError: "unknown elementwise operation")
    end
    if (operation == "add" or operation == "subtract" or operation == "multiply" or operation == "divide" or operation == "axpy") and other == None:
        Error(CudaShapeError: "binary CUDA operation requires another buffer")
    end
    fields = {"operation": operation, "id": self["id"]}
    if other != None:
        call buffer_compatible(self, other)
        if self["count"] != other["count"]:
            Error(CudaShapeError: "elementwise arrays have different lengths")
        end
        fields["other"] = other["id"]
    end
    payload = ""
    if operation == "scale" or operation == "fill" or operation == "axpy":
        payload = scalar_bytes(alpha)
    end
    inplace = operation == "fill" or operation == "axpy"
    data = FloatArray()
    if self["owner"]["backend"] == "cpu":
        source = FloatArray(self["data"])
        right = FloatArray()
        if other != None:
            right = FloatArray(other["data"])
        end
        if inplace:
            data = source
        else:
            data = float_zeros(Int(self["count"]))
        end
        index = 0
        while index < self["count"]:
            value = source[index]
            if operation == "add":
                value += right[index]
            elif operation == "subtract":
                value -= right[index]
            elif operation == "multiply":
                value *= right[index]
            elif operation == "divide":
                value = value / right[index]
            elif operation == "scale":
                value *= Float(alpha)
            elif operation == "relu":
                if value < 0.0:
                    value = 0.0
                end
            elif operation == "fill":
                value = Float(alpha)
            elif operation == "axpy":
                value += Float(alpha) * right[index]
            else:
                Error(CudaConfigurationError: "unknown elementwise operation")
            end
            data[index] = value
            index += 1
        end
    end
    if inplace:
        if self["owner"]["backend"] == "cuda":
            call session_request(self["owner"], fields, payload)
        end
        return None
    end
    return session_make_buffer(self["owner"], fields, payload, data, self["count"])
end

function buffer_matmul(self, other, m, k, n):
    call buffer_compatible(self, other)
    dimensions = checked_dimensions(m, k, n)
    rows = Int(dimensions[0])
    inner = Int(dimensions[1])
    columns = Int(dimensions[2])
    count = session_count(rows * columns)
    if self["count"] != rows * inner or other["count"] != inner * columns:
        Error(CudaShapeError: "matmul array lengths do not match dimensions")
    end
    data = FloatArray()
    if self["owner"]["backend"] == "cpu":
        data = float_matmul(FloatArray(self["data"]), FloatArray(other["data"]), rows, inner, columns)
    end
    return session_make_buffer(self["owner"], {"operation": "matmul", "id": self["id"], "other": other["id"], "m": rows, "k": inner, "n": columns}, "", data, count)
end

function buffer_transpose(self, m, n):
    call buffer_check(self)
    rows = session_count(m)
    columns = session_count(n)
    if rows * columns != self["count"]:
        Error(CudaShapeError: "transpose dimensions differ from buffer size")
    end
    data = FloatArray()
    if self["owner"]["backend"] == "cpu":
        data = float_zeros(Int(self["count"]))
        source = FloatArray(self["data"])
        index = 0
        while index < self["count"]:
            data[(index % columns) * rows + index // columns] = source[index]
            index += 1
        end
    end
    return session_make_buffer(self["owner"], {"operation": "transpose", "id": self["id"], "m": rows, "n": columns}, "", data, self["count"])
end

function session():
    return Session()
end

function upload_to(owner, values):
    call session_check(owner)
    source = FloatArray(values)
    count = session_count(len(source))
    payload = __lsl_floatarray_bytes(source)
    data = FloatArray()
    if owner["backend"] == "cpu":
        data = __lsl_floatarray_from_bytes(payload)
    end
    return session_make_buffer(owner, {"operation": "upload", "count": count}, payload, data, count)
end
