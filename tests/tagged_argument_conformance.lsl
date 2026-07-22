function inspect(value):
    print type(value), __lsl_type_code(value), String(value), Bool(value)
    return value
end

call inspect(0)
call inspect(1)
call inspect(-9223372036854775808)
call inspect(9223372036854775807)
call inspect(True)
call inspect(False)
call inspect(None)

values = [inspect(0), inspect(1)]
print values, type(values[0]), type(values[1])

class Tagged(True):
    ctype Public
    function init(self, value):
        self.value = value
    end
    function add(self, amount):
        self.value += amount
        return self.value
    end
end

item = Tagged(0)
print type(item.value), item.add(2), type(item.value)

function dynamic_add(left, right):
    return left + right
end

computed = dynamic_add(2, -2)
print type(computed), __lsl_type_code(computed), computed
summed = sum([2, -2])
print type(summed), __lsl_type_code(summed), summed
function descend(value):
    if value == 0:
        return value
    end
    return descend(value - 1)
end
recursive = descend(4)
print type(recursive), __lsl_type_code(recursive), recursive
