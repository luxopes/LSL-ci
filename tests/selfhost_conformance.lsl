# This suite is compiled only by compiler/lslc.lsl, never the Python frontend.
class Counter(True):
    ctype Public
    step = 2
    function init(self, start):
        self.value = start
    end
    function add(self, amount):
        self.value += amount
        return self.value
    end
    function label(prefix):
        return prefix + "-counter"
    end
end

load modules.sample
from modules.sample load multiply as module_multiply
from modules.sample load name as module_name
load json
from json load decode as json_parse

function factorial(value):
    result = 1
    for number in rang(2, value + 1):
        result *= number
    end
    return result
end

function apply(callback, value):
    return callback(value)
end

function select_factorial():
    return factorial
end

callback = factorial
selected_callback = select_factorial()

items = [3, 1, 2]
items.insert(1, 4)
items.remove(4)
items.extend((5, 0))
items.sort()
copy = items.copy()
fixed = ![1, 2, 3]
fixed[1] = 8
point = (10, 20)
data = {
    "language": "LSL"
    "version": 7
}
data.setdefault("native", True)
data.update({"selfhost": True})
del(data["version"])

letters = ""
for letter in "abc":
    letters += letter
end
keys_seen = 0
for key in data:
    if key in data:
        keys_seen += 1
    end
end

caught = ""
try:
    Error(TestError: expected)
else:
    caught = last_error()
end
safe:
    Error(Ignored: safe)
end

text = "  lux SIMPLE lang  ".strip().title().replace("Simple", "Native")
printl "factorial={factorial(6)} letters={letters}"
print callback(5), apply(factorial, 4), selected_callback(3), type(callback)
print items[0], items[len(items) - 1], copy.count(2), copy.index(3), fixed[1], point[1]
print data["language"], data.get("native"), data.get("missing", "fallback"), len(data), keys_seen
print text, "banana".count("an"), "banana".index("na"), "-".join(["a", "b", "c"])
print 2 in items, 9 not in items, "language" in data, "ell" in "hello"
print caught
print chr(65), ord("A"), sum([1, 2, 3]), min(8, 3), max(8, 3), type(fixed), type(point)
unicode_text = "A" + chr(128512) + "ž"
print len(unicode_text), unicode_text[1], unicode_text[-1], unicode_text[1:3], List(unicode_text)[2], unicode_text.index("ž")
cycle = []
cycle.append(cycle)
del(cycle)
print gc()
counter = Counter(1)
print Counter.step, Counter.label("native"), counter.add(4), counter.value, type(Counter), type(counter)
print sample.name, sample.multiply(4), module_name, module_multiply(5)
tool = sample.Tool(6)
print tool.double(), type(sample.Tool), type(tool)
json_text = json.encode({"ok": True, "values": [1, None, "x"]})
json_data = json_parse(json_text)
surrogate_json = "\"" + chr(92) + "ud83d" + chr(92) + "ude00\""
decoded_emoji = json_parse(surrogate_json)
print json_text, json_data["ok"], json_data["values"][1]
print decoded_emoji, len(decoded_emoji), chr(10) in json.pretty(json_data)
