keys = []
mapping = {}
for index in rang(128):
    key = "key" + String(index)
    keys.append(key)
    mapping[key] = index
end
limit = Int(arg(1))
checksum = 0
for index in rang(limit):
    key = keys[index & 127]
    mapping[key] += 1
    checksum += mapping[key]
end
print checksum
