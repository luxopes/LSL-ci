d = {}
d[5] = "five"
d[10] = "ten"
d[5] = "FIVE"
print d[5], d[10], len(d)
print 5 in d, 10 in d, 7 in d
big = {}
i = 0
while i < 30:
    big[i] = i * i
    i += 1
end
print big[7], big[29], len(big)
print 15 in big, 100 in big
del(big[7])
print 7 in big, len(big)
strings = {"a": 1, "b": 2}
print strings["a"], "b" in strings, "z" in strings
bools = {True: "yes", False: "no"}
print bools[True], bools[False]
mixed = {}
mixed[1] = "int"
mixed["1"] = "str"
print mixed[1], mixed["1"], len(mixed)
