# Opravy 0.10.7 (chyby nalezené při převodu LuxAI do LSL).

# Podmíněný výraz z manuálu, vyhodnotí se jen vybraná větev.
calls = []
function side(name, value):
    calls.append(name)
    return value
end
print "yes" if True else "no", "yes" if False else "no"
print side("a", 1) if 2 > 1 else side("b", 2), calls
size = 50
print "big" if size > 1000 else "medium" if size > 10 else "small"
print [x * 10 if x % 2 == 0 else x for x in rang(5) if x > 0]

# Instance předaná jako parametr: pole i metody.
class Item:
    function init(self):
        self.value = "hello"
        self.count = 0
    end
    function bump(self, by):
        self.count += by
        return self.count
    end
end
class Receiver:
    function inspect(self, item):
        return item.value
    end
    function change(self, item):
        item.value = "changed"
        return item.bump(2)
    end
end
function read_value(item):
    return item.value
end
function relay(callback, value):
    return callback(value)
end
item = Item()
receiver = Receiver()
print receiver.inspect(item), receiver.change(item), item.value, relay(read_value, item)
print [Item(), item][1].count
try:
    print read_value({"other": 1})
else:
    print last_error()
end
try:
    print read_value(5)
else:
    print last_error()
end

# None z jedné větve a Int z druhé zůstane None.
function optional(flag, items):
    if flag:
        return None
    end
    return len(items)
end
print optional(True, [1]), type(optional(True, [1])), optional(True, [1]) == None, optional(False, [1, 2])
function early(flag):
    if flag:
        return
    end
    return 7
end
print early(True), early(False)

# strip a výřez bez statického typu jsou lineární a správné i pro UTF-8.
function generic_slice(value, start, stop):
    return value[start:stop]
end
text = "  žluťoučký kůň  "
print "[" + text.strip() + "]", "[" + text.lstrip() + "]", "[" + text.rstrip() + "]"
print "[" + "xxžxx".strip("x") + "]", "[" + "čaj čaj".strip("čj") + "]", "[" + "".strip() + "]"
print generic_slice("příliš", 1, 4), generic_slice("příliš", -3, 100), generic_slice("abc", 2, 1) == ""
long_text = "a" * 200000 + "  "
started = monotonic()
stripped = long_text.strip()
cut = generic_slice(long_text, 0, 199999)
print len(stripped), len(cut), monotonic() - started < 1.0

# Stejnojmenná metoda ve dvou třídách na hodnotě bez statického typu.
class First:
    function label(self):
        return "First"
    end
end
class Second:
    function label(self):
        return "Second"
    end
end
function show_label(value):
    return value.label()
end
try:
    print show_label(First()), show_label(Second())
else:
    print String(last_error()).startswith("AttributeError: method label is defined by several classes and the receiver's class is not known")
end
