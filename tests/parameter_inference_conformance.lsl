# Parameter and return inference must stay static through recursion and
# global reads: a recursive helper defined before its external caller keeps
# its Int parameter, and a function returning a value read from a global
# IntArray returns Int, so both can be stored into IntArray slots.

slots = IntArray()
index = 0
while index < 16:
    slots.append(0)
    index += 1
end
LIMIT = 5

function descend(ply):
    slots[ply] = (ply & 127) * 10
    if ply < LIMIT:
        call descend(ply + 1)
    end
    return None
end

function read_slot(position):
    best = 0 - LIMIT
    if slots[position] > best:
        best = slots[position]
    end
    return best
end

function driver(start):
    call descend(start)
    slots[15] = read_slot(start + 2)
    return slots[15]
end

print driver(1)
print slots[1], slots[5], slots[6], slots[15]
