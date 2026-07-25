# Safe Linux process commands: direct PATH lookup + execve, never /bin/sh -c.

function tokenize(command):
    if type(command) == "List":
        result = command.copy()
    elif type(command) == "String":
        result = []
        current = ""
        quote = ""
        escaped = False
        started = False
        for character in command:
            if escaped:
                current += character
                escaped = False
                started = True
            elif character == chr(92):
                escaped = True
                started = True
            elif quote != "":
                if character == quote:
                    quote = ""
                else:
                    current += character
                end
                started = True
            elif character == chr(34) or character == chr(39):
                quote = character
                started = True
            elif character == " " or character == chr(9) or character == chr(10) or character == chr(13):
                if started:
                    result.append(current)
                    current = ""
                    started = False
                end
            else:
                current += character
                started = True
            end
        end
        if escaped:
            Error(OSCommandError: "command ends with an escape")
        elif quote != "":
            Error(OSCommandError: "command has an unclosed quote")
        elif started:
            result.append(current)
        end
    else:
        Error(TypeError: "os command must be a String or List")
    end
    if len(result) == 0:
        Error(OSCommandError: "command is empty")
    end
    for item in result:
        if type(item) != "String":
            Error(TypeError: "os command arguments must be Strings")
        end
    end
    return result
end

function which(name):
    if type(name) != "String":
        Error(TypeError: "os.which expects a String")
    end
    if "/" in name:
        if exists(name):
            return name
        end
        return None
    end
    path = __lsl_getenv("PATH")
    if path == None or path == "":
        path = "/usr/local/bin:/usr/bin:/bin"
    end
    for directory in path.split(":"):
        if directory == "":
            directory = "."
        end
        candidate = directory + "/" + name
        if exists(candidate):
            return candidate
        end
    end
    return None
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
    for argument in arguments:
        if type(argument) != "String":
            Error(TypeError: "os.run_argv arguments must be Strings")
        end
    end
    return __lsl_run(executable(program), arguments)
end

function capture_argv(program, arguments):
    if type(program) != "String" or type(arguments) != "List":
        Error(TypeError: "os.capture_argv expects (String, List)")
    end
    for argument in arguments:
        if type(argument) != "String":
            Error(TypeError: "os.capture_argv arguments must be Strings")
        end
    end
    return __lsl_capture(executable(program), arguments)
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
