limit = Int(arg(1))
checksum = 0
for index in rang(limit):
    text = "alpha,beta,gamma,delta" * 3
    parts = text.split(",")
    joined = "|".join(parts)
    checksum += len(joined) + len(parts[2])
end
print checksum
