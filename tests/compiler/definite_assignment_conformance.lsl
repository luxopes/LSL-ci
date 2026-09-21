load update_install

function require(value, message):
    if not value:
        Error(TestFailure: message)
    end
end

cli = arg(1)
work = update_install.private_work("/tmp")
source = work + "/case.lsl"
output = work + "/case"

bad = [
    "function f():\n    for i in [1]:\n        print len(__iterator_1)\n    end\n    __iterator_1 = \"later\"\nend\ncall f()\n",
    "function f():\n    print i\n    i = 5\nend\ncall f()\n",
    "function f():\n    print len(s)\n    s = \"ahoj\"\nend\ncall f()\n",
    "function f():\n    i += 1\nend\ncall f()\n",
    "function f(flag):\n    if flag:\n        s = \"ok\"\n    end\n    print len(s)\nend\ncall f(False)\n",
    "function f(xs):\n    for s in xs:\n        print s\n    end\n    print len(s)\nend\ncall f([])\n",
    "function f():\n    safe:\n        s = readfile(\"/missing-flow-fixture\")\n    end\n    print len(s)\nend\ncall f()\n",
    "function f():\n    s = \"ok\"\n    del(s)\n    print len(s)\nend\ncall f()\n",
    "function f(flag):\n    s = \"ok\"\n    while flag:\n        print len(s)\n        del(s)\n    end\nend\ncall f(True)\n",
    "s = \"global\"\nfunction f():\n    print len(s)\n    s = \"local\"\nend\ncall f()\n",
    "print len(s)\ns = \"later\"\n",
    "function f():\n    safe:\n        print len(s)\n    end\n    s = \"later\"\nend\ncall f()\n"
]
for text in bad:
    call writefile(source, text)
    result = capture(cli, ["compile", source, output])
    call require(capture_status() == 1 and "error[E2002]" in result + capture_stderr(), "uninitialized source accepted: " + text + result + capture_stderr())
end

good = [
    "class Parent:\nend\nclass Child(Parent):\nend\nprint 2\n",
    "function f(flag):\n    if flag:\n        s = \"yes\"\n    else:\n        s = \"no\"\n    end\n    print len(s)\nend\ncall f(False)\n",
    "function f():\n    loop:\n        s = \"ok\"\n        break\n    end\n    print len(s)\nend\ncall f()\n",
    "function f():\n    try:\n        s = \"ok\"\n    else:\n        return\n    end\n    print len(s)\nend\ncall f()\n",
    "function f():\n    if True:\n        s = \"ok\"\n    end\n    print len(s)\nend\ncall f()\n",
    "function f():\n    s = \"ok\"\n    return len(s)\n    print missing\nend\nprint f()\n"
]
for text in good:
    call writefile(source, text)
    result = capture(cli, [source])
    call require(capture_status() == 0 and result == "2" + chr(10), "valid definite assignment rejected: " + text + result + capture_stderr())
end
call writefile(source, "function f(flag):\n    if flag:\n        print len(s)\n    end\nend\ncall f(False)\nsafe:\n    call f(True)\nend\nprint last_error().startswith(\"NameError:\")\ns = \"ok\"\ncall f(True)\ndel(s)\nsafe:\n    call f(True)\nend\nprint last_error().startswith(\"NameError:\")\n")
result = capture(cli, [source])
call require(capture_status() == 0 and result == "True\n2\nTrue\n", "global initialization/untaken branch/deletion guard: " + result + capture_stderr())
call writefile(source, "s = \"ok\"\nfunction erase():\n    del(s)\nend\ncallback = erase\ncall callback()\nsafe:\n    print len(s)\nend\nprint last_error().startswith(\"NameError:\")\ns = \"new\"\nprint len(s)\n")
result = capture(cli, [source])
call require(capture_status() == 0 and result == "True\n3\n", "global deletion in callback bypassed module read/reinitialization guards: " + result + capture_stderr())
call update_install.cleanup_scratch(work)
print "definite assignment, exception/loop flow and global initialization passed"
