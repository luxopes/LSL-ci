load json
x = 1.7976931348623157e308
print json.decode(json.encode(x)) == x
