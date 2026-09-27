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
require(items.find(2) == 1, "first position")
require(items.find(9) == -1, "missing value is -1, not an error")
require(["a", "b"].find("b") == 1, "String elements")
require((1, 2, 3).find(3) == 2, "Tuple find")
require(dynamic_find(items, 3) == 2, "runtime List receiver")
require(dynamic_find("abc", "c") == 2, "runtime String receiver")
require("abc".find("z") == -1, "String find unchanged")
require(dynamic_find([1, 2], 5) == -1, "runtime List miss")
rejected = False
try:
    call dynamic_find(42, 1)
else:
    rejected = "TypeError" in last_error()
end
require(rejected, "find on an Int is a TypeError")
print "List.find conformance passed"
