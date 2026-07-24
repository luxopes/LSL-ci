load package

name = arg(1)
home = arg(2)
server = arg(3)
helper = arg(4)
lsl = arg(5)
call package.install(name, home, server, helper, helper, helper, helper, lsl)
destination = home + "/.local/lib/lsl/stdlib/" + name + ".lsl"
expected = "function registry_answer():" + chr(10) + "    return 42" + chr(10) + "end" + chr(10)
if readfile(destination) != expected:
    Error(TestFailure: "installed library source differs")
end
print "package-install-ok"
