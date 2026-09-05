# Pure-LSL dense CPU/CUDA tensor with zero-copy views over shared RealArray or
# native-performance FloatArray storage and optional CUDA worker dispatch.

load cuda

MAX_TENSOR_RANK = 32
MAX_TENSOR_ELEMENTS = 67108864

function element_count(shape):
    if type(shape) != "List" or len(shape) > MAX_TENSOR_RANK:
        Error(TensorShapeError: "tensor shape must be a List with at most 32 dimensions")
    end
    count = 1
    for dimension in shape:
        size = Int(dimension)
        if size < 0:
            Error(TensorShapeError: "negative tensor dimension")
        elif size > MAX_TENSOR_ELEMENTS:
            Error(TensorShapeError: "tensor dimension exceeds 67108864 elements")
        end
        if size > 0 and count > MAX_TENSOR_ELEMENTS // size:
            Error(TensorShapeError: "tensor exceeds 67108864 elements")
        end
        count *= size
    end
    return count
end

function contiguous_strides(shape):
    count = element_count(shape)
    strides = []
    if count == 0:
        for dimension in shape:
            strides.append(0)
        end
        return strides
    end
    stride = 1
    index = len(shape) - 1
    while index >= 0:
        strides.insert(0, stride)
        stride *= Int(shape[index])
        index -= 1
    end
    return strides
end

class Tensor(True):
    ctype Public
    function init(self, data, shape, strides, offset, dtype):
        dimensions = List(shape)
        layout = List(strides)
        if len(dimensions) != len(layout):
            Error(TensorLayoutError: "tensor shape and stride ranks differ")
        end
        count = element_count(dimensions)
        start = Int(offset)
        if start < 0 or start > len(data):
            Error(TensorLayoutError: "tensor offset is out of range")
        end
        maximum = start
        axis = 0
        while axis < len(dimensions):
            stride = Int(layout[axis])
            dimension = Int(dimensions[axis])
            if stride < 0:
                Error(TensorLayoutError: "negative tensor strides are not supported")
            end
            if count > 0 and dimension > 0:
                steps = dimension - 1
                if steps > 0 and stride > (len(data) - maximum) // steps:
                    Error(TensorLayoutError: "tensor view exceeds its data")
                end
                distance = steps * stride
                maximum += distance
            end
            axis += 1
        end
        if count > 0 and maximum >= len(data):
            Error(TensorLayoutError: "tensor view exceeds its data")
        end
        self.data = data
        self.shape = dimensions
        self.strides = layout
        self.offset = start
        self.dtype = dtype
    end

    function rank(self):
        return len(self.shape)
    end

    function size(self):
        return element_count(self.shape)
    end

    function position(self, indices):
        if type(indices) != "List" or len(indices) != len(self.shape):
            Error(TensorIndexError: "tensor index rank mismatch")
        end
        position = self.offset
        axis = 0
        while axis < len(indices):
            index = Int(indices[axis])
            dimension = Int(self.shape[axis])
            if index < 0:
                index += dimension
            end
            if index < 0 or index >= dimension:
                Error(TensorIndexError: "tensor index out of range")
            end
            position += index * Int(self.strides[axis])
            axis += 1
        end
        return position
    end

    function get(self, indices):
        position = self.position(indices)
        if __lsl_type_code(self.data) == 14:
            data = FloatArray(self.data)
            return data[position]
        end
        return self.data[position]
    end

    function set(self, indices, value):
        position = self.position(indices)
        if __lsl_type_code(self.data) == 14:
            data = FloatArray(self.data)
            data[position] = Float(value)
        else:
            self.data[position] = value
        end
    end

    function reshape(self, shape):
        call self.require_contiguous()
        if element_count(shape) != self.size():
            Error(TensorShapeError: "reshape changes tensor element count")
        end
        return Tensor(self.data, List(shape), contiguous_strides(shape), self.offset, self.dtype)
    end

    function view(self, shape, strides, offset):
        return Tensor(self.data, List(shape), List(strides), self.offset + Int(offset), self.dtype)
    end

    function require_contiguous(self):
        if self.offset != 0 or self.size() != len(self.data):
            Error(TensorLayoutError: "native kernel requires a full contiguous Tensor")
        end
        expected = contiguous_strides(List(self.shape))
        axis = 0
        while axis < len(self.shape):
            if Int(self.shape[axis]) > 1 and self.strides[axis] != expected[axis]:
                Error(TensorLayoutError: "native kernel requires contiguous Tensor strides")
            end
            axis += 1
        end
    end

    function flat_position(self, index):
        remaining = Int(index)
        position = Int(self.offset)
        axis = len(self.shape) - 1
        while axis >= 0:
            dimension = Int(self.shape[axis])
            position += (remaining % dimension) * Int(self.strides[axis])
            remaining = remaining // dimension
            axis -= 1
        end
        return position
    end

    function contiguous_data(self):
        count = self.size()
        expected = contiguous_strides(List(self.shape))
        if self.offset == 0 and count == len(self.data) and self.strides == expected and __lsl_type_code(self.data) == 14:
            return FloatArray(self.data)
        end
        result = float_zeros(count)
        index = 0
        while index < count:
            position = self.flat_position(index)
            result[index] = Float(self.data[position])
            index += 1
        end
        return result
    end

    function to_device(self, session):
        buffer = cuda.upload_to(session, self.contiguous_data())
        return DeviceTensor(buffer, List(self.shape))
    end

    function sum(self):
        return cuda.sum_data(self.contiguous_data())
    end

    function dot(self, other_data):
        if self.rank() != 1:
            Error(TensorShapeError: "dot requires a one-dimensional Tensor")
        end
        return cuda.dot_data(self.contiguous_data(), FloatArray(other_data))
    end

    function axpy(self, alpha, x_data):
        data = self.contiguous_data()
        call cuda.axpy_data(Float(alpha), FloatArray(x_data), data)
        index = 0
        while index < len(data):
            self.data[self.flat_position(index)] = data[index]
            index += 1
        end
    end

    function matmul(self, other_data, other_shape):
        shape = List(other_shape)
        if self.rank() != 2 or len(shape) != 2:
            Error(TensorShapeError: "matmul requires rank-2 Tensors")
        end
        m = Int(self.shape[0])
        k = Int(self.shape[1])
        if k != Int(shape[0]):
            Error(TensorShapeError: "matmul inner dimensions differ")
        end
        n = Int(shape[1])
        data = cuda.matmul_data(self.contiguous_data(), FloatArray(other_data), m, k, n)
        return Tensor(data, [m, n], [n, 1], 0, "Float64")
    end
end

# Dense Float64 tensors whose storage belongs to a CUDA session. A CPU session
# implements the same API. Reshape aliases storage; free invalidates all aliases.
class DeviceTensor(True):
    ctype Public
    function init(self, buffer, shape):
        call cuda.buffer_check(buffer)
        dimensions = List(shape)
        if element_count(dimensions) != buffer["count"]:
            Error(TensorShapeError: "device tensor shape differs from buffer size")
        end
        self.buffer = buffer
        self.shape = dimensions
        self.dtype = "Float64"
        self.backend = buffer["owner"]["backend"]
    end

    function rank(self):
        return len(self.shape)
    end
    function size(self):
        call cuda.buffer_check(self.buffer)
        return element_count(List(self.shape))
    end
    function to_host(self):
        data = cuda.buffer_download(self.buffer)
        return Tensor(data, List(self.shape), contiguous_strides(List(self.shape)), 0, "Float64")
    end
    function reshape(self, shape):
        return DeviceTensor(self.buffer, List(shape))
    end
    function free(self):
        call cuda.buffer_free(self.buffer)
    end
    function sum(self):
        return cuda.buffer_reduce(self.buffer, "sum", None)
    end
    function dot(self, other):
        if self.rank() != 1 or len(other["shape"]) != 1:
            Error(TensorShapeError: "dot requires rank-1 device tensors")
        end
        return cuda.buffer_reduce(self.buffer, "dot", other["buffer"])
    end
    function add(self, other):
        return device_elementwise(self, "add", other, 0.0)
    end
    function subtract(self, other):
        return device_elementwise(self, "subtract", other, 0.0)
    end
    function multiply(self, other):
        return device_elementwise(self, "multiply", other, 0.0)
    end
    function divide(self, other):
        return device_elementwise(self, "divide", other, 0.0)
    end
    function scale(self, value):
        return device_elementwise(self, "scale", None, value)
    end
    function relu(self):
        return device_elementwise(self, "relu", None, 0.0)
    end
    function fill(self, value):
        call cuda.buffer_elementwise(self.buffer, "fill", None, value)
        return self
    end
    function axpy(self, alpha, other):
        if self.shape != other["shape"]:
            Error(TensorShapeError: "device tensor shapes differ")
        end
        call cuda.buffer_elementwise(self.buffer, "axpy", other["buffer"], alpha)
        return self
    end
    function matmul(self, other):
        shape = List(other["shape"])
        if self.rank() != 2 or len(shape) != 2:
            Error(TensorShapeError: "matmul requires rank-2 device tensors")
        elif self.shape[1] != shape[0]:
            Error(TensorShapeError: "matmul inner dimensions differ")
        end
        buffer = cuda.buffer_matmul(self.buffer, other["buffer"], self.shape[0], self.shape[1], shape[1])
        return DeviceTensor(buffer, [self.shape[0], shape[1]])
    end
    function transpose(self):
        if self.rank() != 2:
            Error(TensorShapeError: "transpose requires a rank-2 device tensor")
        end
        buffer = cuda.buffer_transpose(self.buffer, self.shape[0], self.shape[1])
        return DeviceTensor(buffer, [self.shape[1], self.shape[0]])
    end
end

function device_elementwise(tensor, operation, other, alpha):
    right = None
    if other != None:
        if tensor["shape"] != other["shape"]:
            Error(TensorShapeError: "device tensor shapes differ")
        end
        right = other["buffer"]
    end
    buffer = cuda.buffer_elementwise(tensor["buffer"], operation, right, alpha)
    return DeviceTensor(buffer, List(tensor["shape"]))
end

function from_values(values, shape):
    if type(values) != "List" and type(values) != "FloatArray" and type(values) != "RealArray":
        Error(TypeError: "tensor values must be an array or List")
    end
    if len(values) != element_count(shape):
        Error(TensorShapeError: "tensor data length does not match shape")
    end
    data = FloatArray()
    for value in values:
        data.append(Float(value))
    end
    return Tensor(data, List(shape), contiguous_strides(shape), 0, "Float64")
end

function zeros(shape):
    data = float_zeros(element_count(shape))
    return Tensor(data, List(shape), contiguous_strides(shape), 0, "Float64")
end

# Raw contiguous kernels are also exported directly so performance-sensitive
# code does not pay class/member dispatch and can retain static FloatArray types.
function sum_data(data):
    return cuda.sum_data(FloatArray(data))
end

function dot_data(left, right):
    return cuda.dot_data(FloatArray(left), FloatArray(right))
end

function axpy_data(alpha, x, y):
    call cuda.axpy_data(Float(alpha), FloatArray(x), FloatArray(y))
end

function matmul_data(left, right, m, k, n):
    return cuda.matmul_data(FloatArray(left), FloatArray(right), Int(m), Int(k), Int(n))
end
