effects = []
function tick(label):
    effects.append(label)
    return 1
end
function pair(left, right):
    return left + right
end
print pair(tick("left"), tick("right")), effects
safe:
    call pair(tick("wrong arity"))
end
print last_error().startswith("TypeError:"), effects
safe:
    call missing_function(tick("missing function argument"))
end
print last_error().startswith("NameError:"), effects
safe:
    value = False and missing_variable
    value = True or missing_variable
end
print last_error() == None
safe:
    value = missing_variable
end
print last_error().find("validation_flow.lsl:") >= 0
saved = last_error()
safe:
    print last_error() == saved
end
print last_error() == None
function leave():
    safe:
        safe:
            Error(Inner: "caught")
        end
        return 42
    end
end
print leave(), last_error() == None
value = "old"
for value in rang(3,3):
    Error(TestFailure: "empty range entered")
end
print value
visited = []
for value in rang(0,6):
    visited.append(value)
    value += 1
end
print visited, value
visited = []
for value in rang(0,6):
    visited.append(value)
    value += 2
    continue
end
print visited, value
for value in rang(7,10):
    break
end
print value
value = 20
for value in rang(2,value):
    Error(TestFailure: "stop read previous binding")
end
print value
