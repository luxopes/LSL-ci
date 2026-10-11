
function checked_argument(value, label):
    if type(value) != "String":
        Error(TypeError: label + " must be a String")
    elif __lsl_text_byte_length(String(value)) > 131071:
        Error(OSCommandError: label + " exceeds the Linux argv limit")
    elif chr(0) in value:
        Error(OSCommandError: label + " contains NUL")
    end
    return value
end

function which(name):
    call checked_argument(name, "os.which name")
    if len(name) == 0:
        Error(OSCommandError: "os.which name is empty")
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

function which_trusted(name):
    call checked_argument(name, "trusted command name")
    if len(name) == 0 or "/" in name:
        Error(OSCommandError: "trusted command must be a basename")
    end
    for character in name:
        code = ord(character)
        if not ((code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or character == "-" or character == "_" or character == "."):
            Error(OSCommandError: "trusted command has an invalid character")
        end
    end
    for directory in ["/usr/local/sbin", "/usr/local/bin", "/usr/sbin", "/usr/bin", "/sbin", "/bin"]:
        candidate = directory + "/" + name
        if exists(candidate):
            return candidate
        end
    end
    return None
end
