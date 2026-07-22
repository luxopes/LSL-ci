print 7.5 // 2.0, 7.5 % 2.0
print -7.5 // 2.0, -7.5 % 2.0
print 7.5 // -2.0, 7.5 % -2.0
print -7.5 // -2.0, -7.5 % -2.0
print 7.5 // 2, 7 // 2.0
print 7.5 % 2, 7 % 2.0
print 10.0 // 3.0, 10.0 % 3.0
print 6.0 // 2.0, 6.0 % 2.0
print 0.0 // 5.0, 0.0 % 5.0
print 7 // 2, 7 % 2, -7 // 2, -7 % 2
x = 9.5
print x // 2.0, x % 2.0
safe:
    print 1.0 // 0.0
end
print "survived div0"
reals = ![7.5, 2.0]
print reals[0] // reals[1], reals[0] % reals[1]
ints = [7, 2, 0]
print ints[0] // ints[1], ints[0] % ints[1]
print ints[2] // ints[1], ints[2] % ints[1]
floatlist = [7.5, 2.0]
print floatlist[0] // floatlist[1], floatlist[0] % floatlist[1]
function fdyn(a, b):
    return a // b
end
print fdyn(7.5, 2.0), fdyn(7, 2)
nums = {"a": 7.5, "b": 2.0}
print nums["a"] // nums["b"], nums["a"] % nums["b"]
