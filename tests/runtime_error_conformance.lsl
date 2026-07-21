values = [10, 20]
try:
    print values[2]
else:
    print last_error()
end
try:
    values[-3] = 4
else:
    print last_error()
end
try:
    print 5 // 0
else:
    print last_error()
end
try:
    print 2 ** -1
else:
    print last_error()
end
data = {"ok": 1}
print data.get("missing", 42)
try:
    print data["missing"]
else:
    print last_error()
end
empty = []
try:
    print empty.pop()
else:
    print last_error()
end
try:
    print values.index(99)
else:
    print last_error()
end
try:
    print "hello".index("x")
else:
    print last_error()
end
print "hello".find("x")
print -7 // 3, -7 % 3, 7 // -3, 7 % -3
limit = -9223372036854775808
print limit // -1, limit % -1, 7 // -1, 7 % -1
