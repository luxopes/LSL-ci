function add(left, right):
    return left + right
end

function apply(callback, left, right):
    print type(callback), __lsl_type_code(callback), Bool(callback), String(callback)
    return callback(left, right)
end

function identity(value):
    return value
end

callback = add
print apply(callback, 2, 3)
callbacks = [callback]
from_list = callbacks[0]
print type(from_list), __lsl_type_code(from_list), from_list(4, 5)
selected = identity(callback)
print type(selected), __lsl_type_code(selected), selected(6, 7), selected == callback
call gc()
print selected(8, 9)
