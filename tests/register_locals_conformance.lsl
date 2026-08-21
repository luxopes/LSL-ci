# Hot Int locals live in callee-saved registers; they must survive calls,
# recursion, raised errors and early returns, and a caller's registers must
# come back intact after a callee that uses its own.

function inner(limit, seed):
    acc = seed
    k = 0
    while k < limit:
        acc = (acc * 31 + k) & 65535
        if acc == 12345:
            Error(ValueError: "unlucky")
        end
        k += 1
    end
    return acc
end

function outer(rounds, base):
    total = 0
    i = 0
    while i < rounds:
        j = 0
        while j < 4:
            total += inner(j + 3, base + i)
            j += 1
        end
        i += 1
    end
    return total
end

function depth(n, acc):
    i = 0
    while i < 3:
        acc += n * i
        i += 1
    end
    if n == 0:
        return acc
    end
    return depth(n - 1, acc + i)
end

function wide(a, b, c, d, e, f, g, h):
    sum = 0
    i = 0
    while i < 2:
        sum += a + b + c + d + e + f + g + h + i
        i += 1
    end
    return sum
end

print outer(5, 7)
print depth(10, 1)
print wide(1, 2, 3, 4, 5, 6, 7, 8)
try:
    print inner(100000, 1)
else:
    print "caught", last_error()
end
count = 0
i = 0
while i < 1000:
    try:
        count += inner(50, i)
    else:
        count += 1
    end
    i += 1
end
print count
