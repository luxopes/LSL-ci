function require(condition, message):
    if not condition:
        Error(TestFailure: message)
    end
end

function expect(program, arguments, expected, message):
    output = capture(program, arguments)
    call require(capture_status() == 0 and output == expected, message + ": " + capture_stderr())
end

cli = arg(1)
compiler = arg(2)
root = arg(3) + "/dotenv integration"
call mkdir(root)
call mkdir(root + "/source")
call mkdir(root + "/binary")
call mkdir(root + "/moved")
call unlink(root + "/source/.env")
call unlink(root + "/binary/.env")
source = "load env" + chr(10) + "print env.get(\"LSL_DOTENV_TEST_VALUE_089\", \"fallback\")" + chr(10) + "print env.has(\"LSL_DOTENV_TEST_VALUE_089\")" + chr(10)
script = root + "/source/program.lsl"
call writefile(script, source)
call expect(cli, [script], "fallback" + chr(10) + "False" + chr(10), "absent automatic dotenv")
call writefile(root + "/source/.env", "LSL_DOTENV_TEST_VALUE_089=source-test-only" + chr(10))
call expect(cli, [script], "source-test-only" + chr(10) + "True" + chr(10), "dotenv beside script from another cwd")
call expect("/usr/bin/env", ["LSL_DOTENV_TEST_VALUE_089=exported-test-only", cli, script], "exported-test-only" + chr(10) + "True" + chr(10), "process value overrides dotenv")
call expect("/usr/bin/env", ["LSL_DOTENV_TEST_VALUE_089=", cli, script], chr(10) + "True" + chr(10), "empty process value overrides dotenv")
call writefile(root + "/source/helper.lsl", "load env" + chr(10) + "function value():" + chr(10) + "    return env.require(\"LSL_DOTENV_TEST_VALUE_089\")" + chr(10) + "end" + chr(10))
call writefile(root + "/source/nested.lsl", "load helper" + chr(10) + "print helper.value()" + chr(10))
call expect(cli, [root + "/source/nested.lsl"], "source-test-only" + chr(10), "transitive env import uses entry directory")
for executable in ["cli-program", "direct-program"]:
    binary = root + "/binary/" + executable
    if executable == "cli-program":
        call capture(cli, ["compile", script, binary])
    else:
        call capture(compiler, [script, binary])
    end
    call require(capture_status() == 0, "compile dotenv program")
    call require("source-test-only" not in readfile(binary), "dotenv secret embedded in compiled program")
    call expect(binary, [], "fallback" + chr(10) + "False" + chr(10), "compiled program does not read build source dotenv")
    call writefile(root + "/binary/.env", "LSL_DOTENV_TEST_VALUE_089=binary-test-only" + chr(10))
    call expect(binary, [], "binary-test-only" + chr(10) + "True" + chr(10), "compiled program dotenv beside executable")
    moved = root + "/moved/" + executable
    call writebytes(moved, readbytes(binary))
    call writefile(root + "/moved/.env", "LSL_DOTENV_TEST_VALUE_089=moved-test-only" + chr(10))
    call expect(moved, [], "moved-test-only" + chr(10) + "True" + chr(10), "relocated compiled program dotenv")
    call unlink(root + "/binary/.env")
end
call writefile(root + "/source/.env", "LSL_DOTENV_TEST_VALUE_089='secret-without-closing-quote" + chr(10))
call capture(cli, [script])
call require(capture_status() != 0 and "EnvironmentError" in capture_stderr() and "secret-without-closing-quote" not in capture_stderr(), "automatic dotenv errors do not reveal secrets")
call writefile(root + "/source/.env", "LSL_DOTENV_TEST_VALUE_089=updated-test-only" + chr(10))
call expect(cli, [script], "updated-test-only" + chr(10) + "True" + chr(10), "dotenv reread for next process")
print "env integration passed"
