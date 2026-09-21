load update_install

cli = arg(1)
work = update_install.private_work("/tmp")
source = work + "/case.lsl"
output = work + "/case"
for text in ["i++\n", "Int(i) = i\n", "function f():\n    print i\n    Int(i) = 10\nend\ncall f()\n"]:
    call writefile(source, text)
    diagnostic = capture(cli, ["compile", source, output])
    diagnostic += capture_stderr()
    check(capture_status() == 1 and "error[E2002]" in diagnostic, "unsafe initialization with new syntax")
end
for text in ["Int(i) = 1\nString(i) = \"bad\"\n", "Unknown(i) = 1\n", "Int(i, j) = 1\n", "Int(i) += 1\n", "Int(1) = 1\n", "Int(i=1) = 1\n", "i = 1\nx = i++\n", "i = 1\n++i++\n", "function f(i):\n    Int(i) = 1\nend\n"]:
    call writefile(source, text)
    diagnostic = capture(cli, ["compile", source, output])
    diagnostic += capture_stderr()
    check(capture_status() == 1 and "error[" in diagnostic, "invalid declaration/increment accepted: " + text)
end
call writefile(source, "function system(value):\n    return value + 1\nend\nprint system(4)\n")
result = capture(cli, [source])
check(capture_status() == 0 and result == "5\n", "user system function was overwritten")
plain = "function tally():\n    i = 0\n    total = 0\n    while i < 1000:\n        total += i\n        i += 1\n    end\n    return total\nend\nprint tally()\n"
call writefile(source, plain)
call capture(cli, ["compile", source, output])
check(capture_status() == 0, "plain loop compile")
plain_image = readbytes(output)
typed = plain.replace("    i = 0", "    Int(i) = 0").replace("    total = 0", "    Int(total) = 0").replace("        i += 1", "        i++")
call writefile(source, typed)
call capture(cli, ["compile", source, output])
check(capture_status() == 0 and readbytes(output) == plain_image, "known typed variables/increments changed hot-path machine code")
call update_install.cleanup_scratch(work)
print "typed declaration and increment diagnostics, system shadowing passed"
