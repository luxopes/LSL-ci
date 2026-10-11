load json
s = "x" * 4194295
print len(json.encode([s, True]))
