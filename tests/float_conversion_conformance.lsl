function convert(value):
    return Float(value)
end
print convert(12), convert("2.5e1"), convert(3.5)
try:
    print Float("1e")
else:
    print last_error()
end
try:
    print convert([])
else:
    print last_error()
end
