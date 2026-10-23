# Cache přeložených skriptů `lsl program.lsl`: druhý běh program nepřekládá,
# změna skriptu nebo načteného modulu cache zneplatní, LSL_CACHE=0 ji vypne,
# argumenty a návratový kód procházejí.
load update_install

function require(condition, message):
    if not condition:
        Error(TestFailure: message)
    end
end

cli = arg(1)
work = update_install.private_work("/tmp")
home = work + "/home"
cache = work + "/cache"
call mkdir(home)
call mkdir(cache)
programs = cache + "/lsl/programs"

function invoke(extra_env, arguments):
    command = ["-i", "HOME=" + home, "XDG_CACHE_HOME=" + cache, "NO_COLOR=1", "TERM=xterm"]
    call command.extend(extra_env)
    command.append(cli)
    call command.extend(arguments)
    return capture_clean("/usr/bin/env", command)
end

function entries():
    if not exists(programs):
        return 0
    end
    return len(__lsl_list_directory(programs))
end

script = work + "/script.lsl"
call writefile(script, "print(\"one\", arg(1))" + chr(10) + "exit(3)" + chr(10))
output = invoke([], [script, "a"])
call require(capture_status() == 3 and output == "('one', 'a')" + chr(10), "first run output: " + output)
call require(entries() == 2, "program and manifest stored")
output = invoke([], [script, "b"])
call require(capture_status() == 3 and output == "('one', 'b')" + chr(10), "second run output: " + output)
call require(entries() == 2, "second run reuses the entry")
print("ok cached run")

call writefile(script, "print(\"two\", arg(1))" + chr(10) + "exit(4)" + chr(10))
output = invoke([], [script, "c"])
call require(capture_status() == 4 and output == "('two', 'c')" + chr(10), "changed script output: " + output)
call require(entries() == 2, "changed script replaces the entry")
print("ok changed script")

call mkdir(work + "/mod")
call writefile(work + "/mod/helper.lsl", "function greet():" + chr(10) + "    return \"v1\"" + chr(10) + "end" + chr(10))
call writefile(work + "/mod/main.lsl", "load helper" + chr(10) + "print(helper.greet())" + chr(10))
output = invoke([], [work + "/mod/main.lsl"])
call require(capture_status() == 0 and output == "v1" + chr(10), "module run: " + output)
call require(entries() == 4, "second program stored")
call writefile(work + "/mod/helper.lsl", "function greet():" + chr(10) + "    return \"v2\"" + chr(10) + "end" + chr(10))
output = invoke([], [work + "/mod/main.lsl"])
call require(capture_status() == 0 and output == "v2" + chr(10), "changed module run: " + output)
print("ok changed module")

call writefile(work + "/plain.lsl", "print(\"plain\")" + chr(10))
output = invoke(["LSL_CACHE=0"], [work + "/plain.lsl"])
call require(capture_status() == 0 and output == "plain" + chr(10), "uncached run: " + output)
call require(entries() == 4, "LSL_CACHE=0 stores nothing")
print("ok cache disabled")

call writefile(work + "/broken.lsl", "print(" + chr(10))
call invoke([], [work + "/broken.lsl"])
call require(capture_status() != 0, "compile error status")
call require(entries() == 4, "compile error stores nothing")
print("ok compile error")
print("CLI cache conformance passed")
