# Pure-LSL dense CPU/CUDA tensor with zero-copy views over shared RealArray or
# native-performance FloatArray storage and optional CUDA worker dispatch.

load cuda

function element_count(shape):
    count = 1
    for dimension in shape:
        size = Int(dimension)
        if size < 0:
            Error(TensorShapeError: "negative tensor dimension")
        end
        count *= size
    end
    return count
end

function contiguous_strides(shape):
    strides = []
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
        self.data = data
        self.shape = shape
        self.strides = strides
        self.offset = offset
        self.dtype = dtype
    end

    function rank(self):
        return len(self.shape)
    end

    function size(self):
        return element_count(self.shape)
    end

    function position(self, indices):
        if len(indices) != len(self.shape):
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
    end

    function sum(self):
        call self.require_contiguous()
        return cuda.sum_data(FloatArray(self.data))
    end

    function dot(self, other_data):
        call self.require_contiguous()
        if self.rank() != 1:
            Error(TensorShapeError: "dot requires a one-dimensional Tensor")
        end
        return cuda.dot_data(FloatArray(self.data), FloatArray(other_data))
    end

    function axpy(self, alpha, x_data):
        call self.require_contiguous()
        call cuda.axpy_data(Float(alpha), FloatArray(x_data), FloatArray(self.data))
    end

    function matmul(self, other_data, other_shape):
        call self.require_contiguous()
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
        data = cuda.matmul_data(FloatArray(self.data), FloatArray(other_data), m, k, n)
        return Tensor(data, [m, n], [n, 1], 0, "Float64")
    end
end

function from_values(values, shape):
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
