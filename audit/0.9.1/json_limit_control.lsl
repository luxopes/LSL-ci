load json
s = "x" * 4194294
print len(json.encode([s, False]))
