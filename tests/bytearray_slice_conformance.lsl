values = ByteArray()
for value in [10, 20, 30, 40, 50]:
    values.append(Int(value))
end

print values[1:4], type(values[1:4])
print values[::-1]
print values[4:0:-2]
print values[-3:]

function dynamic_slice(value):
    return value[1:-1]
end

escaped = [dynamic_slice]
print dynamic_slice(values), type(dynamic_slice(values))
