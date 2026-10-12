# List.find(VALUE) returns the first position or -1 (0.8.7); String.find unchanged.
function require(condition, message):
    if not condition:
        Error(TestFailure: message)
    end
end

function dynamic_find(target, value):
    return target.find(value)
end

items = [1, 2, 3, 2]
call require(items.find(2) == 1, "first position")
call require(items.find(9) == -1, "missing value is -1, not an error")
call require(["a", "b"].find("b") == 1, "String elements")
call require((1, 2, 3).find(3) == 2, "Tuple find")
call require(dynamic_find(items, 3) == 2, "runtime List receiver")
call require(dynamic_find("abc", "c") == 2, "runtime String receiver")
call require("abc".find("z") == -1, "String find unchanged")
call require(dynamic_find([1, 2], 5) == -1, "runtime List miss")
rejected = False
try:
    call dynamic_find(42, 1)
else:
    rejected = "TypeError" in last_error()
end
call require(rejected, "find on an Int is a TypeError")
print "List.find conformance passed"
