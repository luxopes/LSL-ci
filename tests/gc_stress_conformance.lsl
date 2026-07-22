roots = []
for index in rang(10000):
    cycle = [index]
    cycle.append(cycle)
    roots.append(cycle)
end
call gc()
print len(roots), roots[0][0], roots[9999][0], roots[5000][1] == roots[5000]

roots = []
cycle = None
released_cycles = gc()
print released_cycles != 0

chain = None
for index in rang(3000):
    chain = [index, chain]
end
call gc()
count = 0
cursor = chain
while cursor != None:
    count += 1
    cursor = cursor[1]
end
print count, chain[0]

chain = None
cursor = None
released_chain = gc()
print released_chain != 0

reused = []
for index in rang(10000):
    reused.append([index])
end
print len(reused), reused[9999][0]
