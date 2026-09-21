value = None
for value in [7, "text"]:
    check(value == 7 or value == "text", "List binding reinterpreted")
end
for value in "ok":
    check(len(value) == 1, "String binding reinterpreted")
end
bytes = ByteArray()
call bytes.append(42)
for value in bytes:
    check(type(value) == "Int" and value == 42, "ByteArray binding not boxed")
end
for value in rang(3):
    check(type(value) == "Int" and value >= 0 and value < 3, "dynamic range binding")
end
for value in rang(5, 0, -2):
    check(type(value) == "Int" and value >= 1 and value <= 5, "dynamic stepped range binding")
end
IntArray(ints) = IntArray()
call ints.append(99)
for value in ints:
    check(type(value) == "Int" and value == 99, "IntArray binding not boxed")
end
function reused():
    value = None
    for value in ["ok"]:
        check(len(value) == 2, "local dynamic binding")
    end
    for value in rang(3):
        check(type(value) == "Int", "local range binding")
    end
    return value
end
check(reused() == 3, "range exit value changed")
function register_callee():
    __save_r12 = "user value"
    __save_r13 = "user value"
    __save_r14 = "user value"
    __save_r15 = "user value"
    i = 0
    total = 0
    while i < 20:
        total += i
        i += 1
    end
    return total
end
function register_caller():
    i = 0
    total = 0
    while i < 10:
        total += register_callee()
        i += 1
    end
    return total
end
check(register_caller() == 1900, "user variable collided with a compiler save slot")
print "reused loop bindings retain safe value representation"
