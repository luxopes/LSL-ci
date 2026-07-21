print Bool(""), Bool("x"), Bool([]), Bool([1]), Bool({}), Bool({"a": 1})
print Bool(0), Bool(1), Bool(0.0), Bool(1.5), Bool(None)
if "":
    print "BUG empty string truthy"
else:
    print "empty string falsy"
end
if not []:
    print "empty list falsy"
end
if not {}:
    print "empty dict falsy"
end
if "hello" and [1] and {"k": 1}:
    print "non-empty all truthy"
end
count = 0
values = [1, 2, 3]
while values:
    del(values[0])
    count += 1
end
print "drained after", count
