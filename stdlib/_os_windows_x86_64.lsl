# Windows: hledání programů. CreateProcessW nehledá v PATH a vyžaduje
# příponu, proto which zkouší přípony z PATHEXT; oddělovač PATH je ";".

function checked_argument(value, label):
    if type(value) != "String":
        Error(TypeError: label + " must be a String")
    elif __lsl_text_byte_length(String(value)) > 32766:
        Error(OSCommandError: label + " exceeds the Windows command line limit")
    elif chr(0) in value:
        Error(OSCommandError: label + " contains NUL")
    end
    return value
end

function system_root():
    root = __lsl_getenv("SystemRoot")
    if root == None or String(root) == "":
        return "C:\\Windows"
    end
    return String(root)
end

# Jméno s příponou se zkouší samo, jinak s každou příponou z PATHEXT.
function candidates(base):
    # Jméno souboru za posledním oddělovačem cesty.
    name = ""
    for character in String(base):
        if character == "\\" or character == "/":
            name = ""
        else:
            name = name + character
        end
    end
    if "." in name:
        return [base]
    end
    extensions = __lsl_getenv("PATHEXT")
    if extensions == None or String(extensions) == "":
        extensions = ".COM;.EXE;.BAT;.CMD"
    end
    result = []
    for extension in String(extensions).split(";"):
        if extension != "":
            result.append(base + extension.lower())
        end
    end
    return result
end

function first_existing(base):
    for candidate in candidates(base):
        if exists(candidate):
            return candidate
        end
    end
    return None
end

function which(name):
    call checked_argument(name, "os.which name")
    if len(name) == 0:
        Error(OSCommandError: "os.which name is empty")
    end
    if "/" in name or "\\" in name or ":" in name:
        return first_existing(name)
    end
    path = __lsl_getenv("PATH")
    if path == None or String(path) == "":
        path = system_root() + "\\System32;" + system_root()
    end
    for directory in String(path).split(";"):
        directory = directory.strip()
        if len(directory) >= 2 and directory.startswith("\"") and directory.endswith("\""):
            directory = directory[1:len(directory) - 1]
        end
        if directory != "":
            found = first_existing(directory + "\\" + name)
            if found != None:
                return found
            end
        end
    end
    return None
end

# Důvěryhodné příkazy jen ze systémových adresářů Windows.
function which_trusted(name):
    call checked_argument(name, "trusted command name")
    if len(name) == 0 or "/" in name or "\\" in name or ":" in name:
        Error(OSCommandError: "trusted command must be a basename")
    end
    for character in name:
        code = ord(character)
        if not ((code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or character == "-" or character == "_" or character == "."):
            Error(OSCommandError: "trusted command has an invalid character")
        end
    end
    for directory in [system_root() + "\\System32", system_root()]:
        found = first_existing(directory + "\\" + name)
        if found != None:
            return found
        end
    end
    return None
end
