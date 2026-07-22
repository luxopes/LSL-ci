load json

result = json.decode(arg(1))
if len(result["generated"]) != 100 or len(result["values"]) != 101:
    Error(TestFailure: "generated config size differs")
end
for index in rang(100):
    expected = index
    if index % 4 == 0:
        expected = index * 10
    elif index % 2 == 0:
        expected = index * 2
    end
    if result["generated"]["k" + String(index)] != expected:
        Error(TestFailure: "generated config value differs")
    end
    if result["values"][index + 1] != index:
        Error(TestFailure: "generated config List differs")
    end
end
print "config fuzz passed"
