numbers = ![1, 2.5]
print numbers[0], numbers[1]
numbers[0] = 3.5
print numbers[0]
try:
    bad = ![1, "x"]
else:
    print last_error()
end
try:
    numbers[0] = "x"
else:
    print last_error()
end
try:
    bad = RealArray([1, True])
else:
    print last_error()
end
