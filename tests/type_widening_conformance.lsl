# Variable types are widened to a fixpoint (0.8.7): a later `for p in items`
# makes p dynamic, so the earlier `zbytek // p` must store a boxed result into
# a boxed zbytek instead of a raw slot. Before the fix this stored a pointer.
function require(condition, message):
    if not condition:
        Error(TestFailure: message)
    end
end

limit = 60
smallest = IntArray()
for _ in rang(limit + 1):
    smallest.append(0)
end
for i in rang(2, limit + 1):
    if smallest[i] == 0:
        for multiple in rang(i, limit + 1, i):
            if smallest[multiple] == 0:
                smallest[multiple] = i
            end
        end
    end
end

function factor_sum(table, upto):
    total = 0
    for k in rang(2, upto + 1):
        zbytek = k
        factors = []
        while zbytek > 1:
            require(zbytek >= 2 and zbytek <= upto, "raw slot received a boxed value")
            p = table[zbytek]
            factors.append(p)
            while zbytek % p == 0:
                zbytek = zbytek // p
            end
        end
        for p in factors:
            total += p
        end
    end
    return total
end

total = 0
for k in rang(2, limit + 1):
    zbytek = k
    factors = []
    while zbytek > 1:
        require(zbytek >= 2 and zbytek <= limit, "raw slot received a boxed value at module scope")
        p = smallest[zbytek]
        factors.append(p)
        while zbytek % p == 0:
            zbytek = zbytek // p
        end
    end
    for p in factors:
        total += p
    end
end
require(total == 866, "sum of distinct prime factors 2..60 at module scope")
require(factor_sum(smallest, limit) == 866, "sum of distinct prime factors 2..60 in a function")
print "type widening conformance passed"
