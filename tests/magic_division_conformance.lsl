function report(label, magic, plain):
    if magic != plain:
        print "FAIL", label, magic, plain
    end
end
values = [0, 1, 9, 10, 11, 99, 100, 123456, 1000000007, 2000000000]
for divisor in [3, 5, 6, 7, 10, 99, 1000, 65537, 1000000007]:
    for magnitude in values:
        for sign in [1, -1]:
            n = magnitude * sign
            d = divisor
            call report("floor", n // divisor, n // d)
            call report("mod", n % divisor, n % d)
        end
    end
end
print 1234567890 // 10, 1234567890 % 10
print -1234567890 // 10, -1234567890 % 10
print -7 // 3, -7 % 3, 7 // 3, 7 % 3
print 100 // 7, 100 % 7, -100 // 7, -100 % 7
print "magic division ok"
