# load a, b [as x] and quotes inside Lux String interpolation (0.8.6).
load os, time
load time, os as shared
load random, math as first
from os load which as lookup

function require(condition, message):
    if not condition:
        Error(TestFailure: message)
    end
end

require(type(os.which("sh")) == "String", "os keeps its own name")
require(time.time() > 0.0, "time keeps its own name")
require(shared.monotonic() > 0.0, "shared alias resolves a time member")
require(type(shared.which("sh")) == "String", "shared alias resolves an os member")
require(first.randint(5, 5) == 5, "shared alias picks the first module that exports the member")
require(lookup("sh") == os.which("sh"), "selective import beside grouped loads")

x = 3
require(l"{"a" * x}" == "aaa", "double quotes inside interpolation")
require(l'{"dvojite " + 'jednoduche'}' == "dvojite jednoduche", "mixed quotes inside interpolation")
require(l"{ {"k": 1}["k"] } a {{doslova}}" == "1 a {doslova}", "nested braces and literal braces")
require(l"stare: {String(x) + \"a\"}" == "stare: 3a", "escaped quotes still work")
require(l"vnorene: {l"in {x}"}!" == "vnorene: in 3!", "nested Lux String")
require(l"zavorka: {"}" + "{"}" == "zavorka: }{", "braces inside inner Strings")
require(l"{x}{x}" == "33", "adjacent interpolations")
print "module groups and Lux String quoting passed"
