x = [10, 20, 30, 40]
del(x[0])
print x
del(x[-1])
print x
y = ["a", "b", "c"]
del(y[1])
print y
z = [1]
del(z[0])
print z, len(z)
d = {"a": 1, "b": 2}
del(d["a"])
print d
safe:
    values = [1, 2]
    del(values[5])
end
print "survived"
