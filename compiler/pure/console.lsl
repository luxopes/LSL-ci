# Terminal presentation shared by CLI, diagnostics and package tools.
# Never emit downloaded control sequences. Pipes stay plain and scriptable.
function clean(value):
    result = []
    for character in String(value):
        code = ord(character)
        if code >= 32 and code != 127 and not (code >= 128 and code <= 159):
            result.append(character)
        else:
            result.append(" ")
        end
    end
    return "".join(result)
end

function colors():
    return colors_fd(1)
end

function colors_fd(descriptor):
    if __lsl_getenv("NO_COLOR") != None:
        return False
    end
    force = __lsl_getenv("FORCE_COLOR")
    if force == "0":
        return False
    elif force != None and force != "":
        return True
    end
    term = __lsl_getenv("TERM")
    return __lsl_isatty(descriptor) and term != "dumb"
end

function style(text, code):
    if colors():
        return chr(27) + "[" + code + "m" + String(text) + chr(27) + "[0m"
    end
    return String(text)
end

function heading(text):
    print style(clean(text), "1;36")
end

function success(text):
    print style(clean(text), "32")
end

function warning(text):
    print style(clean(text), "33")
end

function error(text):
    message = "error: " + clean(text)
    if colors_fd(2):
        message = chr(27) + "[1;31m" + message + chr(27) + "[0m"
    end
    message += chr(10)
    bytes = __lsl_byte_zeros(__lsl_text_byte_length(message))
    for index in rang(len(bytes)):
        bytes[index] = __lsl_text_byte(message, index)
    end
    call __lsl_fd_write(2, bytes, len(bytes))
end

function require_terminal():
    if not __lsl_isatty(0) or not __lsl_isatty(1) or __lsl_getenv("TERM") == "dumb":
        Error(CliError: "TUI requires an interactive terminal (TERM must not be dumb); use lsl search or lsl man --plain")
    end
end
