# lsl: internal-abi
function require(value, message):
    if not value:
        Error(TestFailure: message)
    end
end
function sumdown(n):
    if n <= 0:
        return 0
    end
    return n + sumdown(n - 1)
end
function seven(a,b,c,d,e,f,g):
    return a+b+c+d+e+f+g
end
function roots():
    a = ["left"]
    b = {"right": "live"}
    call gc()
    call require(a[0] == "left" and b["right"] == "live", "register/stack roots")
    return a
end
values = {"a": 1, "b": 2, "c": 3}
result = 0
for key in values:
    result += values[key]
end
call require(result == 6, "dictionary iteration")
result = 0
for i in rang(10,0,-1):
    if i == 7:
        continue
    end
    if i == 3:
        break
    end
    result += i
end
call require(result == 42, "loop phis")
call require(sumdown(10) == 55, "recursion")
call require(seven(1,2,3,4,5,6,7) == 28, "stack arguments")
call require(roots()[0] == "left", "returned root")
try:
    Error(Probe: "caught")
else:
    call require(last_error() == "Probe: caught", "caught error")
end
call require(last_error() == "Probe: caught", "retained error")
safe:
    result = 1
end
call require(last_error() == None, "successful safe resets error")
print "QBE core passed"
