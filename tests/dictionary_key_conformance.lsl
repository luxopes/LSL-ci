function marker(value):
    return value
end

mapping = {
    1: "int"
    True: "bool"
    None: "none"
    1.5: "float"
    marker: "function"
}
print len(mapping), mapping[1], mapping[True], mapping[None], mapping[1.5], mapping[marker]
mapping[2] = "two"
mapping[False] = "false"
print mapping[2], mapping[False], 2 in mapping, False in mapping
print type(mapping.keys()[0]), type(mapping.keys()[1]), type(mapping.keys()[2]), type(mapping.keys()[3]), type(mapping.keys()[4])
