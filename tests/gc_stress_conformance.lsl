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

# Repeated collections with survivors in between: sweep must never treat a
# freed block's free-list link as a mark bit (that severed the free list and
# leaked every previously freed block), and long-lived containers must keep
# their contents across many gc() calls.
class Frame(True):
    function init(self, count):
        self.count = count
        self.cells = __lsl_int_zeros(count)
    end
end

frame = Frame(5000)
frame.cells[4999] = 424242
survivor = {}
for index in rang(40):
    survivor["key-" + String(index)] = index * 3
end
for round in rang(12):
    garbage = []
    for index in rang(2000):
        garbage.append("cycle-" + String(round) + "-" + String(index))
    end
    garbage = None
    call gc()
end
print survivor["key-0"], survivor["key-39"], len(survivor), frame.cells[4999], frame.count
