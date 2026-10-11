limit = Int(arg(1))
checksum = 0
for index in rang(limit):
    values = [index, index + 1, index + 2]
    item = {"value": values, "index": index}
    checksum += item["value"][1] - item["index"]
end
print checksum
