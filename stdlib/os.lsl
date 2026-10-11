load _os_platform as transport
# Společné rozdělení argumentů a procesní API; vyhledání cest poskytuje OS.

function checked_argument(value, label):
    return transport.checked_argument(value, label)
end

function tokenize(command):
    if type(command) == "List":
        result = command.copy()
    elif type(command) == "String":
        if __lsl_text_byte_length(String(command)) > 1048576:
            Error(OSCommandError: "command exceeds 1 MiB")
        end
        result = []
        current = []
        quote = ""
        escaped = False
        started = False
        for character in command:
            if escaped:
                current.append(character)
                escaped = False
                started = True
            elif character == chr(92):
                escaped = True
                started = True
            elif quote != "":
                if character == quote:
                    quote = ""
                else:
                    current.append(character)
                end
                started = True
            elif character == chr(34) or character == chr(39):
                quote = character
                started = True
            elif character == " " or character == chr(9) or character == chr(10) or character == chr(13):
                if started:
                    result.append("".join(current))
                    current = []
                    started = False
                end
            else:
                current.append(character)
                started = True
            end
        end
        if escaped:
            Error(OSCommandError: "command ends with an escape")
        elif quote != "":
            Error(OSCommandError: "command has an unclosed quote")
        elif started:
            result.append("".join(current))
        end
    else:
        Error(TypeError: "os command must be a String or List")
    end
    if len(result) == 0:
        Error(OSCommandError: "command is empty")
    end
    for item in result:
        call checked_argument(item, "os command argument")
    end
    return result
end

function which(name):
    return transport.which(name)
end

# Fixed privileged lookup that never consults PATH or the current directory.
function which_trusted(name):
    return transport.which_trusted(name)
end

function executable(name):
    resolved = which(name)
    if resolved == None:
        # Preserve the process runtime's deterministic exec failure status 127.
        return name
    end
    return resolved
end

function run_argv(program, arguments):
    if type(program) != "String" or type(arguments) != "List":
        Error(TypeError: "os.run_argv expects (String, List)")
    end
    call checked_argument(program, "os.run_argv program")
    if len(arguments) > 4096:
        Error(OSCommandError: "os.run_argv has too many arguments")
    end
    for argument in arguments:
        call checked_argument(argument, "os.run_argv argument")
    end
    return __lsl_run(executable(program), arguments)
end

function run_argv_clean(program, arguments):
    if type(program) != "String" or type(arguments) != "List":
        Error(TypeError: "os.run_argv_clean expects (String, List)")
    end
    call checked_argument(program, "os.run_argv_clean program")
    if len(arguments) > 4096:
        Error(OSCommandError: "os.run_argv_clean has too many arguments")
    end
    for argument in arguments:
        call checked_argument(argument, "os.run_argv_clean argument")
    end
    return run_clean(executable(program), arguments)
end

function capture_argv(program, arguments):
    if type(program) != "String" or type(arguments) != "List":
        Error(TypeError: "os.capture_argv expects (String, List)")
    end
    call checked_argument(program, "os.capture_argv program")
    if len(arguments) > 4096:
        Error(OSCommandError: "os.capture_argv has too many arguments")
    end
    for argument in arguments:
        call checked_argument(argument, "os.capture_argv argument")
    end
    return __lsl_capture(executable(program), arguments)
end

function capture_argv_clean(program, arguments):
    if type(program) != "String" or type(arguments) != "List":
        Error(TypeError: "os.capture_argv_clean expects (String, List)")
    end
    call checked_argument(program, "os.capture_argv_clean program")
    if len(arguments) > 4096:
        Error(OSCommandError: "os.capture_argv_clean has too many arguments")
    end
    for argument in arguments:
        call checked_argument(argument, "os.capture_argv_clean argument")
    end
    return capture_clean(executable(program), arguments)
end

function run(command):
    arguments = tokenize(command)
    return run_argv(arguments[0], arguments[1:len(arguments)])
end

function system(command):
    return run(command)
end

function capture(command):
    arguments = tokenize(command)
    return capture_argv(arguments[0], arguments[1:len(arguments)])
end

function capture_result(command):
    output = capture(command)
    status = capture_status()
    return {"stdout": output, "stderr": capture_stderr(), "status": status, "ok": status == 0}
end

function check(command):
    result = capture_result(command)
    if not result["ok"]:
        Error(OSCommandError: "command exited with status " + String(result["status"]) + ": " + result["stderr"])
    end
    return result["stdout"]
end
