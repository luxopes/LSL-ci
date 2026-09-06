load linker

compiler = arg(1)
root = arg(2)
newline = chr(10)
declaration = "function f(a, b=2):" + newline + "return a+b" + newline + "end" + newline
cases = [
    declaration + "print f()",
    declaration + "print f(c=2)",
    declaration + "print f(1, a=2)",
    declaration + "print f(a=1, a=2)",
    declaration + "print f(a=1, 2)",
    declaration + "alias = f",
    "class Empty(True):" + newline + "end" + newline + "x=Empty(unused=1)",
    "function f(a=1, b): return b end",
    "function f(a=[]): return a end",
    "function f(a=clock()): return a end",
    "function f(a,a): return a end",
    "print len(value=[1])",
    "x=[]" + newline + "call x.append(value=1)",
    "print [x for x in rang(stop=3)]",
    "print [x for in [1]]",
    "print [x for x [1]]",
    "print {x:x for x in [1]",
    "print [x for x in [1], 2]",
    "print x" + newline + "data=[x for x in [1]]"
]
expected_details = [
    "missing required argument", "unknown keyword", "multiple values",
    "duplicate keyword", "positional argument after keyword", "Function values",
    "class without init", "required parameter after a default", "immutable literal",
    "immutable literal", "duplicate parameter", "keyword arguments", "keyword arguments",
    "keyword arguments"
]
for i in rang(len(cases)):
    path = root + "/language-negative-" + String(i) + ".lsl"
    call writefile(path, String(cases[i]) + newline)
    output = capture(compiler, [path, root + "/language-negative"])
    if capture_status() == 0:
        Error(TestFailure: "invalid extension case compiled: " + String(i))
    end
    details = output + capture_stderr()
    if details.find(path) < 0:
        Error(TestFailure: "extension diagnostic lost source path: " + String(i))
    end
    if i < len(expected_details) and details.find(String(expected_details[i])) < 0:
        Error(TestFailure: "wrong extension diagnostic: " + String(i) + " " + details)
    end
end
for source in [
    "print [__lsl_syscall(39,0,0,0,0) for x in [1]]",
    "print [x for x in [1] if __lsl_syscall(39,0,0,0,0)]",
    "print {__lsl_syscall(39,0,0,0,0):x for x in [1]}",
    "print [x for x in [__lsl_syscall(39,0,0,0,0)]]"
]:
    failure = ""
    try:
        call linker.link_checked("<comprehension-safety>", source, False)
    else:
        failure = last_error()
    end
    if failure.find("__lsl_syscall") < 0:
        Error(TestFailure: "comprehension bypassed safe validation")
    end
end
print "language extension diagnostics passed"
