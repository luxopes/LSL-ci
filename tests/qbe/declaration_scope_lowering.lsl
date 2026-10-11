function calculate(value):
    Int(total) = 0
    Int(index) = 0
    for index in [1, 2, 3]:
        total += index
    end
    if value:
        String(message) = "hello"
        message += " world"
    else:
        String(message) = "other"
    end
    Int(recovered) = 0
    try:
        Int(recovered) = 2
        Error(Probe: "expected")
    else:
        recovered += 4
    end
    return [total, message, recovered, [x*x for x in rang(3)]]
end
class Typed(True):
    function answer(self):
        Int(local_value) = 42
        return local_value
    end
end
check(calculate(True) == [6, "hello world", 6, [0, 1, 4]], "typed branches, loop and recovery")
check(calculate(False) == [6, "other", 6, [0, 1, 4]], "typed alternate branch")
check(Typed().answer() == 42, "typed method in untyped class scope")
print "declaration scope lowering passed"
