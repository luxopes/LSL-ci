# No gc() calls: every collection in this test must be automatic.
load fd

function rss_kib():
    for line in fd.read_text_limit("/proc/self/status", 65536).split("\n"):
        if line.startswith("VmRSS:"):
            return Int(line[6:len(line)].strip().split(" ")[0])
        end
    end
    Error(TestFailure: "VmRSS unavailable")
end

function churn(count):
    checksum = 0
    for index in rang(count):
        text = "abcdefgh" * 256
        values = [text, {"key": (index, text)}]
        values.append(values)
        checksum += len(values[0])
        if index % 3 == 0:
            continue
        end
        text += "!"
    end
    return checksum
end

function combine(first, second, third):
    check(first == ["left", {"nested": 123}], "caller temporary was reclaimed")
    check(third == "right", "later argument changed")
    return second
end

function callback(value):
    call churn(128)
    return value + "!"
end

function apply_each(function_value, items):
    result = []
    for item in items:
        result.append(function_value(item))
    end
    return result
end

# Deep live graphs used to abort the whole recursive GC, retaining unrelated
# garbage forever. Worklist tracing must collect while this graph stays live.
chain = None
for index in rang(3000):
    chain = [index, chain]
end
survivors = {"list": ["kept", (1, 2)], "set": set([3, 4, 3])}
survivors["cycle"] = survivors
bytes = ByteArray()
for value in [2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0]:
    bytes.append(Int(value))
end
ints = IntArray()
for value in [2, 1, 1, 0, 11, 123, 456, 789]:
    ints.append(Int(value))
end
floats = FloatArray()
floats.append(1.25)
floats.append(-2.5)
total = 0
for batch in rang(20):
    total += combine(["left", {"nested": 123}], churn(128), "right")
    check(survivors["list"][0] == "kept" and len(survivors["set"]) == 2, "live container changed")
    check(survivors["cycle"] == survivors, "cycle changed")
    check(chain[0] == 2999, "deep graph changed")
    check(ints[7] == 789 and bytes[8] == 1 and floats[1] == -2.5, "typed backing storage reclaimed")
    check(rss_kib() < 32768, "automatic GC did not bound allocation churn")
end
check(total == 5242880, "checksum changed")
mapped = apply_each(callback, ["a", "b", "c"])
check(mapped == ["a!", "b!", "c!"], "callback roots changed")

for index in rang(20):
    try:
        call churn(128)
        Error(ExpectedError: "kept-" + String(index))
    else:
        message = last_error()
        call churn(128)
        check(message == "ExpectedError: kept-" + String(index), "pending exception was reclaimed")
    end
end
cursor = chain
count = 0
while cursor != None:
    check(cursor[0] == 2999 - count, "deep graph child changed")
    cursor = cursor[1]
    count += 1
end
check(count == 3000 and rss_kib() < 32768, "endurance memory bound failed")
print "automatic GC roots, cycles, deep graphs, callbacks, exceptions and memory bound passed"
