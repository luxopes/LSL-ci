function convert(value):
    return Int(value)
end
print convert("123"), convert("-45"), convert("+7"), convert(3.9), convert(True)
try:
    print Int("abc")
else:
    print last_error()
end
try:
    print Int("12x")
else:
    print last_error()
end
try:
    print Int("")
else:
    print last_error()
end
try:
    print convert([])
else:
    print last_error()
end
