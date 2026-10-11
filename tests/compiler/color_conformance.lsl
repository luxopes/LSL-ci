load update_install

function require(value, message):
    if not value:
        Error(TestFailure: message)
    end
end

cli = arg(1)
work = update_install.private_work("/tmp")
call writefile(work + "/runtime.lsl", "message = \"dynamic message\"" + chr(10) + "Error(DemoError: message)" + chr(10))
call writefile(work + "/compile.lsl", "print (" + chr(10))
call require(run(cli, ["compile", work + "/runtime.lsl", work + "/runtime"]) == 0, "compile runtime color fixture")
for settings in [[], ["TERM=dumb"], ["FORCE_COLOR=0"], ["FORCE_COLOR=1"], ["TERM=dumb", "FORCE_COLOR=1"], ["FORCE_COLOR=1", "NO_COLOR=1"], ["NO_COLOR=", "FORCE_COLOR=1"]]:
    colored = "FORCE_COLOR=1" in settings and "NO_COLOR=1" not in settings and "NO_COLOR=" not in settings
    command = ["-i"] + settings + [work + "/runtime"]
    stdout = capture_clean("/usr/bin/env", command)
    stderr = capture_stderr()
    call require(capture_status() == 1 and stdout == "", "runtime status/stream")
    heading = "error[DemoError]: dynamic message"
    help_line = " help: handle expected errors with try: ... else: ... end or safe: ... end"
    if colored:
        heading = chr(27) + "[1;31m" + heading + chr(27) + "[0m"
        help_line = chr(27) + "[36m" + help_line + chr(27) + "[0m"
    end
    call require(stderr == heading + chr(10) + help_line + chr(10), "runtime color policy: " + String(settings))
    command = ["-i"] + settings + [cli, "compile", work + "/compile.lsl", work + "/invalid"]
    stdout = capture_clean("/usr/bin/env", command)
    stderr = capture_stderr()
    call require(capture_status() == 1 and "error[" in stdout + stderr, "compile error diagnostic")
    call require((chr(27) in stdout + stderr) == colored, "compile color policy")
end
call update_install.cleanup_scratch(work)
print "compile/runtime colors and NO_COLOR/FORCE_COLOR passed"
