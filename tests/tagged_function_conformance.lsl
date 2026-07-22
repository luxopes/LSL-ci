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

function positive(value):
    return value > 0
end
function nothing():
    return None
end
function choose():
    return add
end
predicate = positive
empty = nothing
selector = choose
chosen = selector()
print type(predicate(1)), __lsl_type_code(predicate(1)), predicate(-1)
print type(empty()), __lsl_type_code(empty()), empty()
print type(chosen), __lsl_type_code(chosen), chosen(10, 11)
function varying(flag):
    if flag:
        return 0
    end
    return "text"
end
variant = varying
print type(variant(True)), __lsl_type_code(variant(True)), variant(True)
print type(variant(False)), __lsl_type_code(variant(False)), variant(False)
