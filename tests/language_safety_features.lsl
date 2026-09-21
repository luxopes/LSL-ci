load time

function identity(value):
    return value
end

Int(i) = 10
i++
--i
++i
i--
check(i == 10 and type(i) == "Int", "increments or typed Int")
Float(f) = 1.5
f++
check(f == 2.5, "Float increment")
String(s) = "hello"
s += "!"
check(s == "hello!", "typed String update")
Bool(b) = True
List(xs) = [1, 2]
Tuple(pair) = (1, 2)
Dictionary(mapping) = {"a": 1}
Set(unique) = set([1, 1])
RealArray(real) = ![1, 2]
IntArray(ints) = IntArray()
FloatArray(floats) = FloatArray()
ByteArray(bytes) = ByteArray()
Function(callback) = identity
check(callback(7) == 7, "typed function")

function checked(value):
    Int(number) = value
    return number + 1
end
for value in [3, 4]:
    check(checked(value) == value + 1, "dynamic checked Int")
end
for value in [True, "wrong", None, 1.5, []]:
    safe:
        call checked(value)
    end
    check(last_error().startswith("TypeError: typed variable requires Int"), "typed parameter value accepted")
end
safe:
    i = "wrong"
end
check(i == 10 and last_error().startswith("TypeError:"), "failed assignment changed typed slot")
for i in [4, 5]:
    check(type(i) == "Int", "typed for binding")
end
safe:
    for i in ["wrong"]:
        Error(TestFailure: "typed loop accepted String")
    end
end
check(i == 5 and last_error().startswith("TypeError:"), "typed loop failed unsafely")

check(system(["true"]) == 0, "system argv PATH resolution")
check(system("false") == 1, "system String exit status")
check(system(["test", "a; echo unexpected", "=", "a; echo unexpected"]) == 0, "system shell metacharacters")
check(system("test 'two words' = \"two words\"") == 0, "system quoted arguments")
runner = system
check(runner(["true"]) == 0, "first-class system")
function shadow(system):
    return system
end
check(shadow(17) == 17, "system parameter shadowing")

text = clock()
check(type(text) == "String" and len(text) == 23 and text.endswith(" UTC"), "readable clock")
start = monotonic()
call time.sleep(0.01)
check(monotonic() > start and time.monotonic() >= start and time.perf_counter() >= start, "numeric timing")
unsafe:
    check(__lsl_clock_text(0.0) == "1970-01-01 00:00:00 UTC", "Unix epoch")
    check(__lsl_clock_text(-0.5) == "1969-12-31 23:59:59 UTC", "negative fractional timestamp")
    check(__lsl_clock_text(951782400.0) == "2000-02-29 00:00:00 UTC", "leap century")
    check(__lsl_clock_text(4107542400.0) == "2100-03-01 00:00:00 UTC", "non-leap century")
    check(__lsl_clock_text(-62135596800.0) == "0001-01-01 00:00:00 UTC", "first supported date")
    check(__lsl_clock_text(253402300799.0) == "9999-12-31 23:59:59 UTC", "last supported date")
end
print "typed variables, increments, system and readable clock passed"
