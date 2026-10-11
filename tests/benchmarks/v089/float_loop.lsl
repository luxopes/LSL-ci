limit = Int(arg(1))
value = 0.0
for index in rang(limit):
    value = (value + 0.5) * 1.000001
end
print Int(value * 1024.0)
