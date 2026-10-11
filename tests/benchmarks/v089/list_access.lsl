values = []
for index in rang(1024):
    values.append(index)
end
limit = Int(arg(1))
checksum = 0
for index in rang(limit):
    slot = index & 1023
    values[slot] = values[slot] + 1
    checksum += values[slot]
end
print checksum
