# rang(...) outside a for iterable is a List value (0.8.7).
function require(condition, message):
    if not condition:
        Error(TestFailure: message)
    end
end

values = List(rang(2, 100 + 1))
call require(len(values) == 99 and values[0] == 2 and values[98] == 100, "List(rang(START, STOP))")
call require(rang(4) == [0, 1, 2, 3], "rang(STOP)")
call require(rang(10, 0, -3) == [10, 7, 4, 1], "negative step")
call require(len(rang(0, 10, 3)) == 4 and type(rang(3)) == "List", "step and type")
call require(rang(5, 2) == [], "empty range")
grown = rang(1, 4)
grown.append(9)
call require(grown == [1, 2, 3, 9] and grown.find(3) == 2, "ordinary List afterwards")
total = 0
for i in rang(1, 4):
    total += i
end
call require(total == 6 and [v * 2 for v in rang(3)] == [0, 2, 4], "loops keep working")
rejected = False
try:
    call rang(1, 5, 0)
else:
    rejected = "ValueError" in last_error()
end
call require(rejected, "zero step")
rejected = False
try:
    call rang("a")
else:
    rejected = "TypeError" in last_error()
end
call require(rejected, "non-Int argument")
function shadow(rang):
    return rang + 1
end
call require(shadow(41) == 42, "parameter named rang shadows the builtin")
print "rang value conformance passed"
