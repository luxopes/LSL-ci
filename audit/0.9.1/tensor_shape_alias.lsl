load tensor
shape = [2]
x = tensor.from_values([10, 20], shape)
shape[0] = 3
print x.size()
print x.get([2])
