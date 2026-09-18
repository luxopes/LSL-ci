function require(value, message):
    if not value:
        Error(TestFailure: message)
    end
end

function absent_callee():
    call nonexist()
end
function two(a, b):
    return a + b
end
function defaulted(a, b=2):
    return a + b
end
function recovery():
    result = 0
    for index in rang(10000):
        safe:
            unused = [two(nonexist(), 7), 9]
            result += 100000
        end
        result += 1
    end
    return result
end

safe:
    call nonexist()
    Error(TestFailure: "safe continued after missing function")
end
call require("NameError:" in last_error(), "missing function")
safe:
    call absent_callee()
end
call require("nonexist" in last_error(), "callee propagation")
safe:
    value = missing_variable
end
call require("NameError:" in last_error(), "missing variable")
safe:
    call two(1)
end
call require("TypeError:" in last_error(), "direct arity")
safe:
    call defaulted(no_such=1)
end
call require("TypeError:" in last_error(), "keyword arity")
safe:
    call len()
end
call require("TypeError:" in last_error(), "builtin arity")
safe:
    call "hello".nonexist()
end
call require("AttributeError:" in last_error(), "missing method")
safe:
    value = "hello" + 1
end
call require("TypeError:" in last_error(), "static operand error")
safe:
    value = 42[0]
end
call require("TypeError:" in last_error(), "static indexing error")
safe:
    value = 1 << -1
end
call require(last_error().startswith("ValueError:"), "negative shift")
safe:
    value = readfile(42)
end
call require(last_error().startswith("TypeError:"), "file argument type")
safe:
    value = [1][9]
end
call require(last_error().startswith("IndexError:"), "native error String methods")
value = Tuple([1])
safe:
    value[0] = 2
end
call require(last_error().startswith("TypeError:"), "immutable assignment")
safe:
    for item in 42:
        Error(TestFailure: "noniterable body executed")
    end
end
call require(last_error().startswith("TypeError:"), "noniterable")
safe:
    for item in rang():
        Error(TestFailure: "invalid rang body executed")
    end
end
call require(last_error().startswith("TypeError:"), "rang arity")
safe:
    del(missing_name)
end
call require(last_error().startswith("NameError:"), "delete unknown name")
safe:
    value = 1 < "text"
end
call require(last_error().startswith("TypeError:"), "comparison")
try:
    value = [1, two(nonexist(), 7)]
else:
    call require("NameError:" in last_error(), "try missing name")
end
for index in rang(10000):
    safe:
        value = [1, 4 // 0]
    end
end
call require(recovery() == 10000, "function stack recovery")
safe:
    safe:
        call nonexist()
    end
    call require(two(20, 22) == 42, "nested continuation")
    Error(Outer: "caught")
end
call require("Outer: caught" in last_error(), "nested catch")
call require(two(20, 22) == 42, "successful direct call")
call gc()
print "safe name/type/attribute errors, propagation and stack recovery passed"
