members = set([3, 4, 3])
check(type(members) == "Set" and len(members) == 2, "Set representation changed")
total = 0
for value in members:
    total += Int(value)
end
check(total == 7, "public Set iteration changed")
check(List(members) == [3, 4], "Set private traversal changed")
reals = RealArray([-7, 3, 2.5])
check(String(reals) == "![-7, 3, 2.5]", "RealArray representation changed")
check(type(reals) == "RealArray", "RealArray tag changed")
trace = []
function item(index):
    trace.append(index)
    for count in rang(2048):
        temporary = ["abc" * 64, {"n": count}]
    end
    return [index, "kept"]
end
values = [item(1), item(2), item(3)]
check(trace == [1, 2, 3] and values == [[1, "kept"], [2, "kept"], [3, "kept"]], "literal evaluation order or roots changed")
function stop_item():
    Error(Expected: "stop")
end
try:
    bad = [item(4), stop_item(), item(5)]
else:
    check(last_error() == "Expected: stop" and trace == [1, 2, 3, 4], "literal exception order changed")
end
values[-1] = 99
check(values[2] == 99, "negative List store changed")
try:
    values[3] = 0
else:
    check(last_error().startswith("IndexError: index out of range"), "List store bounds changed")
end
words = ["hé", "λ", "", "🙂"]
check("|".join(words) == "hé|λ||🙂", "UTF-8 join changed")
check("|".join([]) == "", "empty join changed")
single = "fresh" + "piece"
check(__lsl_address("|".join([single])) == __lsl_address(single), "single-piece join identity changed")
try:
    bad = "|".join(["ok", 3, "later"])
else:
    check(last_error() == "TypeError: expected a String", "join element validation changed")
end
check("λ🙂" * 3 == "λ🙂λ🙂λ🙂" and "x" * 0 == "" and "x" * -1 == "", "repeat bytes or bounds changed")
check(__lsl_address(single * 1) != __lsl_address(single), "repeat result must remain fresh")
print "Set, RealArray, literal roots, collection stores, joins and repeats passed"
