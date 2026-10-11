limit = Int(arg(1))
checksum = 0
index = 0
while index < limit:
    checksum += index % 97
    index += 1
end
print checksum
