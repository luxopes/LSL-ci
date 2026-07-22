# Pure-LSL dense CPU tensor with zero-copy views over a shared RealArray.

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
        return self.data[self.position(indices)]
    end

    function set(self, indices, value):
        self.data[self.position(indices)] = value
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
end

function from_values(values, shape):
    if len(values) != element_count(shape):
        Error(TensorShapeError: "tensor data length does not match shape")
    end
    data = RealArray(values)
    return Tensor(data, List(shape), contiguous_strides(shape), 0, "Float64")
end

function zeros(shape):
    values = []
    for index in rang(element_count(shape)):
        values.append(0.0)
    end
    return from_values(values, shape)
end
