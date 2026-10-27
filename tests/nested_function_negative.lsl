function outer():
    value = "captured"
    function inner():
        return value
    end
    return inner()
end
print outer()
