function identity(value):
    return value
end

print sqrt(0)
print sqrt(2.25)
print sqrt(identity(81))
print sqrt(-0.0)

try:
    print sqrt(-1)
else:
    print last_error()
end
