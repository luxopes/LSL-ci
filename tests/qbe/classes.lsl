# Class objects and instances retain the existing Dictionary representation.
events = []
function observed(name, value):
    events.append(name)
    return value
end
class Pair(True):
    title = "pair"
    function init(self, first, second=20):
        self.first = first
        self.second = second
    end
    function total(self, extra=1):
        return self.first + self.second + extra
    end
    function identity(self):
        return self
    end
    function static_value(value=7):
        return value * 2
    end
end
class Quiet(False):
    field = observed("skipped", 100)
end
pair = Pair(observed("first", 10), observed("second", 20))
print ",".join(events)
print Pair.title, pair.total(), pair.total(extra=4), Pair.static_value()
other = Pair(second=9, first=4)
print other.total(extra=0), Pair(5).total()
alias = pair.identity()
alias.first = 100
print pair.first, alias.total(extra=0)
alias.extra = "temporary"
del(alias.extra)
print len(events)

class Parent:
    function init(self, value=30):
        self.value = value
    end
    function read(self, add=0):
        return self.value + add
    end
end
class Child(Parent):
    function read(self, add=0):
        return origin.read(add=add) + 1
    end
end
child = Child()
print child.read(add=2)

# A constructor and wide method keep the instance and boxed arguments live.
class Rooted:
    function init(self, a, b, c, d, e, f, g, h):
        call gc()
        self.values = [a, b, c, d, e, f, g, h]
        self.owner = self
    end
    function retain(self, a, b, c, d, e, f, g, h):
        call gc()
        return Int(a) + Int(b) + Int(c) + Int(d) + Int(e) + Int(f) + Int(g) + Int(h) + Int(self.values[0])
    end
end
rooted = Rooted(1, 2, 3, 4, 5, 6, 7, 8)
print rooted.retain(10, 20, 30, 40, 50, 60, 70, 80)
call gc()
print rooted.values, type(pair), type(Pair)

# Recoverable validation failures must be raised before invoking a bad call.
try:
    invalid = Pair()
    print "missed constructor arity"
else:
    print "constructor arity caught"
end
try:
    invalid = Pair(1, unknown=2)
    print "missed constructor keyword"
else:
    print "constructor keyword caught"
end
try:
    print pair.total(1, 2)
else:
    print "method arity caught"
end
try:
    print pair.missing()
else:
    print "missing method caught"
end
class Empty:
    ctype Public
end
try:
    invalid = Empty(value=1)
    print "missed empty keyword"
else:
    print "empty keyword caught"
end
class Broken:
    function init(self):
        self.alive = "before-error"
        Error(ExpectedError: "constructor failure")
    end
end
try:
    invalid = Broken()
    print "missed constructor error"
else:
    print "constructor error caught"
end
