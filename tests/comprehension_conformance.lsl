function require(condition, message):
    if not condition:
        Error(TestFailure: message)
    end
end

function add(a, b=4):
    return a + b
end
function literals(text="žluťoučký", number=-3, flag=True, empty=None):
    return [text, number, flag, empty]
end
function wide(a, b, c=3, d=4, e=5, f=6, g=7, h=8, i=9):
    return [a, b, c, d, e, f, g, h, i]
end
require(add(3) == 7 and add(b=8, a=2) == 10, "default and keyword binding")
require(literals() == ["žluťoučký", -3, True, None], "immutable defaults")
require(wide(1, i=19, b=2) == [1, 2, 3, 4, 5, 6, 7, 8, 19], "wide default ABI")

class Base(True):
    function init(self, x=5):
        self.x = x
    end
    function value(self, y=2):
        return self.x + y
    end
end
class Child(Base):
    function value(self, y=3):
        return origin.value(y=y)
    end
end
instance = Child(x=10)
require(instance.value() == 13 and instance.value(y=9) == 19, "inherited keyword defaults")

x = 40
require([x*x for x in rang(6) if x % 2 == 0] == [0, 4, 16], "filtered list")
require(x == 40, "comprehension does not leak variable")
require([x+y for x in rang(3) if x > 0 for y in rang(x)] == [1, 2, 3], "chained clauses")
require({k:v*2 for k,v in [("a",2), ("b",3)]} == {"a":4, "b":6}, "dict with unpacking")
require([[i*j for j in rang(3)] for i in rang(2)] == [[0,0,0], [0,1,2]], "nested comprehension")
require([i for i in [1,2,3]][1] == 2, "postfix index")
require({i%2:i for i in rang(4)} == {0:2, 1:3}, "last duplicate key wins")
require([i for i in []] == [] and {i:i for i in []} == {}, "empty comprehensions")
require([a+b for (a,b) in [(1,2), (3,4)]] == [3,7], "parenthesized unpack")
require([a for a in [1,2] for a in rang(a)] == [0,0,1], "rebound loop variable")
outer = [1,2,3]
require([outer for outer in outer] == [1,2,3] and outer == [1,2,3], "outer iterable scope")
require(Tuple([i for i in rang(3)]) == (0,1,2), "eager Tuple conversion")
require([i for i in rang(10) if i > 2 if i < 5] == [3,4], "multiple filters")

effects = []
function iterable():
    call effects.append("iterable")
    return [1,2]
end
function key(i):
    call effects.append("key" + String(i))
    return i
end
function value(i):
    call effects.append("value" + String(i))
    return i * 2
end
require({key(i):value(i) for i in iterable()} == {1:2, 2:4}, "comprehension calls")
require(effects == ["iterable", "key1", "value1", "key2", "value2"], "iterable once, key before value")

function local_comprehensions(n):
    a = [i for i in rang(n)]
    b = {i:[j for j in rang(i)] for i in a}
    for i in rang(40):
        garbage = [j*j for j in rang(20)]
        call gc()
    end
    return [a, b]
end
require(local_comprehensions(3) == [[0,1,2], {0:[], 1:[0], 2:[0,1]}], "local allocation, nesting and GC")
failed = False
try:
    bad = [a for a,b in [(1,2,3)]]
else:
    failed = last_error().find("unpacking length") >= 0
end
require(failed and x == 40, "unpacking error")
failed = False
try:
    bad = [10 // i for i in [1,0,2]]
else:
    failed = True
end
require(failed and x == 40, "expression error escapes comprehension")
print "comprehension conformance passed"
