# Frontend musí odmítnout chybný program bez závislosti na strojovém backendu.
load frontend

if arg(1) == "--probe":
    call frontend.prepare("validation-probe.lsl", arg(2), "", 0, False)
    exit(0)
end

function rejects(source, message):
    failure = capture(executable_path(), ["--probe", source])
    failure += capture_stderr()
    check(capture_status() == 1 and message in failure, "frontend missed diagnostic: " + message + ": " + failure)
end

call rejects("print len()\n", "builtin len expects 1 argument(s), got 0")
call rejects("print -\"text\"\n", "unary - requires a numeric operand")
call rejects("print \"text\" + 1\n", "+ requires two numbers")
call rejects("print 1 << -1\n", "negative shift count")
call rejects("print (1).strip()\n", "type Int has no method strip")
call rejects("print \"text\".replace(\"t\")\n", "method replace expects 2 argument(s)")
call rejects("print \"text\".lower(value=1)\n", "builtin methods do not accept keyword arguments")
call rejects("function f(a, b=2):\n    return a\nend\nprint f(b=1)\n", "missing required argument: a")
call rejects("function f(a, b=2):\n    return a\nend\nprint f(1, a=2)\n", "multiple values for one argument")
call rejects("function f(a):\n    return a\nend\nprint f(1, 2)\n", "function argument count mismatch for f")
call rejects("print origin.missing()\n", "origin can only be used inside a class method")
call rejects("items = (1, 2)\nitems[0] = 3\n", "does not support indexed assignment")
call rejects("items = IntArray()\nitems.append(\"bad\")\n", "IntArray append requires an Int")
call rejects("print {[]: 1}\n", "cannot be a Dictionary key")
call rejects("for value in 3:\n    print value\nend\n", "is not iterable")

# Konstantně mrtvý kód se nadále nevaliduje.
unit = frontend.prepare("dead.lsl", "if False:\n    print len()\nend\nprint 1\n", "", 0, False)
check(unit["validation_version"] == 1, "frontend did not finish validation")

# Bindování defaultů a keywordů proběhne jednou před předáním backendu.
unit = frontend.prepare("keywords.lsl", "function choose(a, b=2):\n    return b\nend\nprint choose(b=3, a=1)\nprint choose(4)\n", "", 0, False)
check(len(unit["prepared_arguments"]) == 2, "frontend did not prepare keyword/default arguments")
for arguments in unit["prepared_arguments"].values():
    check(len(arguments) == 2, "prepared call lost an argument")
end

# Zachytitelné chyby jsou metadata, nikoli předčasné odmítnutí programu.
unit = frontend.prepare("caught.lsl", "safe:\n    print len()\nend\nfunction fail():\n    return -\"bad\"\nend\n", "", 0, False)
check("builtin_arity" in unit["validation_errors"], "safe error was not prepared")
check("unary_numeric" in unit["validation_errors"], "function error was not prepared")
print "frontend argument, method, operand and catchable-error validation passed"
