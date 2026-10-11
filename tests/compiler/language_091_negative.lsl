# Chybové případy jazykových novinek 0.9.1: kód se nesmí přeložit a hlášení
# musí obsahovat cestu a očekávaný popis.
compiler = arg(1)
root = arg(2)
newline = chr(10)
cases = [
    ["load random" + newline + "epocha = 1" + newline + "printl \"Epocha: {epocha} loss: {chyba}\"" + newline + "chyba = 2", ".lsl:3:33"],
    ["x = 1" + newline + "print l\"a\\tb {x + undefined_name} c\"", ".lsl:2:19"],
    ["v = 2" + newline + "printl \"value {v +} end\"", ".lsl:2:19"],
    ["a, b += 1", "multiple assignment requires ="],
    ["f(1), b = 1, 2", "invalid assignment target"],
    ["a, b = 1, 2, 3", "expected 2 values, got 3"],
    ["a, b = [1, 2, 3]", "expected 2 values, got 3"],
    ["print \"a b\".split(\",\", 1)", "method split expects zero or one argument"],
    ["for a, a in [[1, 2]]:" + newline + "end", "duplicate loop variable"],
    ["for a, in [[1, 2]]:" + newline + "end", "expected loop variable after comma"],
    ["x = 1" + newline + "/* never closed" + newline + "print x", "unterminated block comment"],
    ["print r\"abc", "unterminated String literal"],
    ["global x" + newline + "x = 1", "global is only allowed inside a function"],
    ["function f():" + newline + "global missing" + newline + "missing = 1" + newline + "end" + newline + "call f()", "global 'missing' has no module-level variable"],
    ["x = 1" + newline + "function f(x):" + newline + "global x" + newline + "end", "'x' is both a parameter and global"],
    ["for i in rang(0):" + newline + "x = i" + newline + "end" + newline + "print x", "may be read before assignment"],
    ["n = 3" + newline + "for i in rang(n):" + newline + "x = i" + newline + "end" + newline + "print x", "may be read before assignment"],
    ["for i in rang(3):" + newline + "if i == 0:" + newline + "break" + newline + "end" + newline + "x = i" + newline + "end" + newline + "print x", "may be read before assignment"],
    ["for i in rang(3):" + newline + "if i == 0:" + newline + "continue" + newline + "end" + newline + "x = i" + newline + "end" + newline + "print x", "may be read before assignment"],
    ["for i in rang(3):" + newline + "x = i" + newline + "del(x)" + newline + "end" + newline + "print x", "may be read before assignment"],
    ["for i in []:" + newline + "x = i" + newline + "end" + newline + "print x", "may be read before assignment"],
    ["g = IntArray()" + newline + "g.append(0)" + newline + "function f():" + newline + "lock g:" + newline + "return 1" + newline + "end" + newline + "end", "return cannot leave a lock block"],
    ["g = IntArray()" + newline + "g.append(0)" + newline + "for i in rang(3):" + newline + "lock g:" + newline + "if i == 1:" + newline + "break" + newline + "end" + newline + "end" + newline + "end", "break cannot leave a lock block"],
    ["g = IntArray()" + newline + "g.append(0)" + newline + "while True:" + newline + "lock g:" + newline + "continue" + newline + "end" + newline + "end", "continue cannot leave a lock block"],
    ["g = IntArray()" + newline + "g.append(0)" + newline + "lock g:" + newline + "print 1", "lock block has no end"]
]
for i in rang(len(cases)):
    path = root + "/language-091-negative-" + String(i) + ".lsl"
    call writefile(path, String(cases[i][0]) + newline)
    output = capture(compiler, [path, root + "/language-091-negative"])
    if capture_status() == 0:
        Error(TestFailure: "invalid 0.9.1 case compiled: " + String(i))
    end
    details = output + capture_stderr()
    if details.find(path) < 0:
        Error(TestFailure: "0.9.1 diagnostic lost source path: " + String(i))
    end
    if details.find(String(cases[i][1])) < 0:
        Error(TestFailure: "wrong 0.9.1 diagnostic: " + String(i) + " " + details)
    end
end
# Zastínění globálu je jen varování na stderr; program se přeloží.
warning_path = root + "/language-091-warning.lsl"
call writefile(warning_path, "total = 1" + newline + "function f():" + newline + "total = 2" + newline + "return total" + newline + "end" + newline + "print f(), total" + newline)
warning_stdout = capture(compiler, [warning_path, root + "/language-091-warning"])
if capture_status() != 0:
    Error(TestFailure: "shadowing warning stopped compilation")
end
if warning_stdout.find("W2004") >= 0:
    Error(TestFailure: "shadowing warning printed to stdout")
end
if capture_stderr().find("warning[W2004]") < 0 or capture_stderr().find("global total") < 0:
    Error(TestFailure: "missing shadowing warning: " + capture_stderr())
end
if capture(root + "/language-091-warning", []) != "2 1" + newline:
    Error(TestFailure: "shadowing changed the global")
end
# Nezachycená běhová chyba: formát diagnostiky na stderr, zachycená nic nevypíše.
runtime_path = root + "/language-091-runtime.lsl"
call writefile(runtime_path, "function pick(items, key):" + newline + "    return items[key]" + newline + "end" + newline + "print pick([1, 2], \"a\")" + newline)
call capture(compiler, [runtime_path, root + "/language-091-runtime"])
if capture_status() != 0:
    Error(TestFailure: "runtime diagnostic fixture did not compile")
end
call capture_clean("/usr/bin/env", ["NO_COLOR=1", root + "/language-091-runtime"])
runtime_stderr = capture_stderr()
for part in ["error[TypeError]: sequence index must be Int", " --> " + runtime_path + ":2:18", "2 |     return items[key]", "^~~", " help: convert the index with Int(...)"]:
    if runtime_stderr.find(part) < 0 or capture_status() != 1:
        Error(TestFailure: "runtime diagnostic is missing " + part + ": " + runtime_stderr)
    end
end
caught_path = root + "/language-091-caught.lsl"
call writefile(caught_path, "try:" + newline + "    x = [1][5]" + newline + "else:" + newline + "    print \"handled\"" + newline + "end" + newline)
call capture(compiler, [caught_path, root + "/language-091-caught"])
caught_output = capture(root + "/language-091-caught", [])
if caught_output != "handled" + newline or capture_stderr() != "" or capture_status() != 0:
    Error(TestFailure: "caught error printed a diagnostic")
end
# Worker ukončený nezachycenou chybou ji vypíše na stderr; zdravý worker nic.
worker_path = root + "/language-091-worker.lsl"
call writefile(worker_path, "function bad():" + newline + "    values = [1]" + newline + "    return values[3]" + newline + "end" + newline + "function good():" + newline + "    return None" + newline + "end" + newline + "unsafe:" + newline + "    print thread_join(thread_spawn(bad))" + newline + "    print thread_join(thread_spawn(good))" + newline + "end" + newline)
call capture(compiler, [worker_path, root + "/language-091-worker"])
if capture_status() != 0:
    Error(TestFailure: "worker diagnostic fixture did not compile")
end
worker_output = capture(root + "/language-091-worker", [])
worker_stderr = capture_stderr()
if worker_output != "0" + newline + "0" + newline or capture_status() != 0:
    Error(TestFailure: "worker fixture output changed: " + worker_output)
end
if worker_stderr != "LSL worker error: IndexError: index out of range at " + worker_path + ":3" + newline:
    Error(TestFailure: "worker death was not reported: " + worker_stderr)
end
# load ai: novější aikit v ~/.local/lib/lsl/stdlib má přednost, starší ne;
# jiné vestavěné moduly uživatelská knihovna nezastíní.
ai_home = root + "/language-091-home"
ai_library = ai_home + "/.local/lib/lsl/stdlib"
call mkdir(ai_home)
call mkdir(ai_home + "/.local")
call mkdir(ai_home + "/.local/lib")
call mkdir(ai_home + "/.local/lib/lsl")
call mkdir(ai_library)
ai_program = root + "/language-091-ai.lsl"
call writefile(ai_program, "load ai" + newline + "load json" + newline + "print ai.version, json.encode([1])" + newline)
call writefile(ai_library + "/json.lsl", "# AI 9.0.0: shadow" + newline + "function encode(value):" + newline + "    return \"shadowed\"" + newline + "end" + newline)
for ai_case in [["# AI 9.1.0: newer", "9.1.0"], ["# AI 0.0.1: older", "builtin"], ["# AI 9.x: malformed", "builtin"]]:
    call writefile(ai_library + "/aikit.lsl", ai_case[0] + newline + "version = \"9.1.0\"" + newline)
    call capture_clean("/usr/bin/env", ["HOME=" + ai_home, compiler, ai_program, root + "/language-091-ai"])
    if capture_status() != 0:
        Error(TestFailure: "ai precedence fixture did not compile: " + capture_stderr())
    end
    ai_output = capture(root + "/language-091-ai", [])
    ai_expected = "9.1.0 [1]" + newline
    if ai_case[1] == "builtin":
        ai_expected = "1.1.0 [1]" + newline
    end
    if ai_output != ai_expected:
        Error(TestFailure: "ai library precedence for " + ai_case[0] + ": " + ai_output)
    end
end
print "language 0.9.1 diagnostics passed"
