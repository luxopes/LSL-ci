load package
load update_install

function require(condition, message):
    if not condition:
        Error(TestFailure: message)
    end
end

cli = arg(1)
compiler = arg(2)
work = update_install.private_work("/tmp")
home = work + "/home"
call mkdir(home)
base = ["-i", "HOME=" + home, "NO_COLOR=1", "TERM=xterm", cli]
function invoke(arguments):
    command = base.copy()
    call command.extend(arguments)
    return capture_clean("/usr/bin/env", command)
end
output = invoke(["list"])
call require(capture_status() == 0 and "random  bundled" in output and chr(27) not in output, "plain bundled inventory")
call require(not exists(home + "/.local"), "list modified HOME")
output = invoke(["check", "random"])
call require(capture_status() == 0 and "is installed (bundled)" in output, "check bundled")
call invoke(["check", "absent_probe"])
call require(capture_status() == 1, "check missing status")
call require(not exists(home + "/.local"), "check modified HOME")
directory = package.user_directory(home)
call writefile(directory + "/probe.lsl", "print 42" + chr(10))
output = invoke(["check", "probe"])
call require(capture_status() == 0 and "is installed (user)" in output, "check user")
output = invoke(["list"])
call require(capture_status() == 0 and "probe  user" in output, "list user")
for arguments in [["check"], ["list", "extra"], ["search", "one", "two"], ["man", "one", "two"], ["help", "one", "two"]]:
    call invoke(arguments)
    call require(capture_status() == 2, "CLI usage exit status")
end
call invoke(["check", "../bad"])
call require(capture_status() == 1 and "invalid library name" in capture_stderr(), "invalid package name")
call invoke(["install", "--tui"])
call require(capture_status() == 1 and "interactive terminal" in capture_stderr(), "TUI requires terminal before network")
output = invoke(["man"])
call require(capture_status() == 0 and "17-cli-and-packages" in output and chr(27) not in output, "manual pipe fallback")
output = invoke(["man", "--plain", "random"])
call require(capture_status() == 0 and "MT19937" in output, "full offline chapter")
for arguments in [["man", "../README"], ["man", "no_such_topic"], ["help", "no_such_topic"]]:
    call invoke(arguments)
    call require(capture_status() == 1, "invalid manual/help topic")
end
for topic in ["install", "list", "search", "check", "man", "update", "print"]:
    output = invoke(["help", topic])
    call require(capture_status() == 0 and len(output) > 30 and chr(27) not in output, "topic CLI help")
end
output = invoke(["about"])
call require(capture_status() == 0 and "Lux Simple Lang (LSL) 0.10.5" in output and "MIT" in output and chr(27) not in output, "lsl about")
output = invoke(["about", "random"])
call require(capture_status() == 0 and output.startswith("random") and "MT19937" in output, "lsl about random")
output = invoke(["about", "probe"])
call require(capture_status() == 0 and "without a descriptive header comment" in output, "about of a user library without header")
call writefile(directory + "/described.lsl", "# Described probe library." + chr(10) + "# Second line." + chr(10) + chr(10) + "print 1" + chr(10))
output = invoke(["about", "described"])
call require(capture_status() == 0 and "Described probe library. Second line." in output, "about from header comment")
call invoke(["about", "absent_probe"])
call require(capture_status() == 1, "about of a missing library")
call invoke(["about", "../bad"])
call require(capture_status() == 1, "about rejects invalid names")
call invoke(["about", "one", "two"])
call require(capture_status() == 2, "about usage")
call invoke(["--tui"])
call require(capture_status() == 1 and "interactive terminal" in capture_stderr(), "editor requires a terminal")
call invoke(["--tui", "a", "b"])
call require(capture_status() == 2, "editor usage")
output = invoke(["man", "--plain", "16-random"])
call require(capture_status() == 0 and "```" not in output and "• " in output and "│" in output and chr(27) not in output, "manual markdown formatting")
output = capture_input("/usr/bin/env", base, "help(\"random\")" + chr(10) + "help(\"described\")" + chr(10))
call require(capture_status() == 0 and output.startswith("random: ") and "Described probe library." in output, "help() shows library about")
output = capture_input(cli, [], "help()" + chr(10))
call require(capture_status() == 0 and "Lux Simple Lang (LSL) 0.10.5" in output and "topics:" in output, "help() index")
for source in ["help(\"print\", \"len\")", "help(topic=\"print\")"]:
    call writefile(work + "/bad-help.lsl", source + chr(10))
    call capture(compiler, [work + "/bad-help.lsl", work + "/bad-help"])
    call require(capture_status() != 0, "invalid help arity/keyword compiled")
end
call update_install.cleanup_scratch(work)
print "CLI 0.8.0 conformance passed"
