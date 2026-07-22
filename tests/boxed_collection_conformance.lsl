load json

values = [0, 1, -1, 9223372036854775807, -9223372036854775808]
print values
for value in values:
    print __lsl_type_code(value), type(value), Int(value)
end
print json.encode(values)
values.append(4)
values.insert(1, 5)
values[0] = 6
values[1] += 2
print values
print __lsl_type_code(values[0]), __lsl_type_code(values[1]), sum(values[0:3])

fixed = (0, 1)
reals = ![0, 1, 2.5]
print fixed, reals, type(fixed[0]), type(reals[1])

mapping = {"zero": 0, "one": 1}
mapping["zero"] += 7
mapping["two"] = 2
mapping.setdefault("three", 3)
print mapping
print type(mapping["zero"]), json.encode(mapping)
