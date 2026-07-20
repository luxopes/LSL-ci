function multiply(left, right):
    product = left * right
    return product
end

function factorial(value):
    result = 1
    while value > 1:
        result = result * value
        value = value - 1
    end
    return result
end

print multiply(6, 7)
print factorial(6)
