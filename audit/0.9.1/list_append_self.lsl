x = [1]
x.append(x)
call gc()
print x[0], len(x)
