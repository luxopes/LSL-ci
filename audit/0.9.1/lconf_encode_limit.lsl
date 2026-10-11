load lconf
s = lconf.encode({"apt": ["x" * 1048577], "lux": [], "lsl": []})
print len(s)
print lconf.decode(s)
