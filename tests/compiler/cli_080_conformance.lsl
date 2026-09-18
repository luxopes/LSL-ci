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
require(capture_status() == 0 and "random  bundled" in output and chr(27) not in output, "plain bundled inventory")
require(not exists(home + "/.local"), "list modified HOME")
output = invoke(["check", "random"])
require(capture_status() == 0 and "is installed (bundled)" in output, "check bundled")
call invoke(["check", "absent_probe"])
require(capture_status() == 1, "check missing status")
require(not exists(home + "/.local"), "check modified HOME")
directory = package.user_directory(home)
call writefile(directory + "/probe.lsl", "print 42" + chr(10))
output = invoke(["check", "probe"])
require(capture_status() == 0 and "is installed (user)" in output, "check user")
output = invoke(["list"])
require(capture_status() == 0 and "probe  user" in output, "list user")
for arguments in [["check"], ["list", "extra"], ["search", "one", "two"], ["man", "one", "two"], ["help", "one", "two"]]:
    call invoke(arguments)
    require(capture_status() == 2, "CLI usage exit status")
end
call invoke(["check", "../bad"])
require(capture_status() == 1 and "invalid library name" in capture_stderr(), "invalid package name")
call invoke(["install", "--tui"])
require(capture_status() == 1 and "interactive terminal" in capture_stderr(), "TUI requires terminal before network")
output = invoke(["man"])
require(capture_status() == 0 and "17-cli-and-packages" in output and chr(27) not in output, "manual pipe fallback")
output = invoke(["man", "--plain", "random"])
require(capture_status() == 0 and "MT19937" in output, "full offline chapter")
for arguments in [["man", "../README"], ["man", "no_such_topic"], ["help", "no_such_topic"]]:
    call invoke(arguments)
    require(capture_status() == 1, "invalid manual/help topic")
end
for topic in ["install", "list", "search", "check", "man", "update", "print"]:
    output = invoke(["help", topic])
    require(capture_status() == 0 and len(output) > 30 and chr(27) not in output, "topic CLI help")
end
output = capture_input(cli, [], "help()" + chr(10))
require(capture_status() == 0 and "Lux Simple Lang (LSL) 0.8.2" in output and "topics:" in output, "help() index")
for source in ["help(\"print\", \"len\")", "help(topic=\"print\")"]:
    call writefile(work + "/bad-help.lsl", source + chr(10))
    call capture(compiler, [work + "/bad-help.lsl", work + "/bad-help"])
    require(capture_status() != 0, "invalid help arity/keyword compiled")
end
call update_install.cleanup_scratch(work)
print "CLI 0.8.0 conformance passed"
