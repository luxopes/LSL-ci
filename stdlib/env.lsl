# Proměnné procesu a .env načítané výhradně za běhu programu.

_values = {}

function _dotenv_error(path, line):
    # Diagnostika nikdy neobsahuje řádek se skutečnou hodnotou tajemství.
    Error(EnvironmentError: "invalid .env entry at " + String(path) + ":" + String(line))
end

function _dotenv_name(name):
    first = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_"
    rest = first + "0123456789"
    if len(name) == 0 or len(name) > 255:
        return False
    end
    if name[0] not in first:
        return False
    end
    for character in name:
        if character not in rest:
            return False
        end
    end
    return True
end

function _dotenv_value(text, path, line):
    if len(text) == 0:
        return ""
    end
    quote = text[0]
    if quote == chr(34) or quote == chr(39):
        pieces = []
        index = 1
        while index < len(text):
            character = text[index]
            if character == quote:
                tail = text[index + 1:len(text)].strip()
                if tail != "" and not tail.startswith("#"):
                    call _dotenv_error(path, line)
                end
                return "".join(pieces)
            elif quote == chr(34) and character == chr(92):
                index += 1
                if index >= len(text):
                    call _dotenv_error(path, line)
                end
                escaped = text[index]
                if escaped == "n":
                    pieces.append(chr(10))
                elif escaped == "r":
                    pieces.append(chr(13))
                elif escaped == "t":
                    pieces.append(chr(9))
                elif escaped == chr(34) or escaped == chr(92):
                    pieces.append(escaped)
                else:
                    pieces.append(chr(92) + escaped)
                end
            else:
                pieces.append(character)
            end
            index += 1
        end
        call _dotenv_error(path, line)
    end
    index = 0
    while index < len(text):
        if text[index] == "#":
            if index == 0 or text[index - 1] == " " or text[index - 1] == chr(9):
                return text[0:index].strip()
            end
        end
        index += 1
    end
    return text.strip()
end

function _parse_dotenv(source, path):
    if __lsl_text_byte_length(String(source)) > 1048576:
        Error(EnvironmentError: ".env exceeds the 1 MiB limit: " + String(path))
    end
    if source.startswith(chr(65279)):
        source = source[1:len(source)]
    end
    result = {}
    line_number = 0
    for raw_line in source.split(chr(10)):
        line_number += 1
        line = raw_line.strip()
        if chr(0) in line:
            call _dotenv_error(path, line_number)
        end
        if line == "" or line.startswith("#"):
            continue
        end
        if line.startswith("export ") or line.startswith("export" + chr(9)):
            line = line[7:len(line)].strip()
        end
        equals = line.find("=")
        if equals < 0:
            call _dotenv_error(path, line_number)
        end
        name = line[0:equals].strip()
        if not _dotenv_name(name):
            call _dotenv_error(path, line_number)
        end
        result[name] = _dotenv_value(line[equals + 1:len(line)].strip(), path, line_number)
    end
    return result
end

function _default_path():
    entry = __lsl_entry_source()
    if entry == "<stdin>":
        return ".env"
    elif entry == "":
        entry = executable_path()
    end
    slash = -1
    index = 0
    while index < len(entry):
        if entry[index] == "/":
            slash = index
        end
        index += 1
    end
    if slash < 0:
        return ".env"
    end
    return entry[0:slash + 1] + ".env"
end

function load_dotenv(path=None):
    if path == None:
        path = _default_path()
    end
    if type(path) != "String" or len(path) == 0 or chr(0) in path:
        Error(EnvironmentError: ".env path must be a nonempty String without NUL")
    end
    if not exists(path):
        return False
    end
    parsed = _parse_dotenv(readfile(path), path)
    # Změna je atomická: neplatný soubor nezanechá částečně načtené hodnoty.
    call _values.update(parsed)
    return True
end

function checked_name(name):
    if type(name) != "String" or len(name) == 0 or len(name) > 255 or chr(0) in name or "=" in name:
        Error(EnvironmentError: "environment name must contain 1..255 characters without NUL or =")
    end
    return name
end

function get(name, default_value=None):
    name = checked_name(name)
    value = __lsl_getenv(name)
    if value == None:
        return _values.get(name, default_value)
    end
    return value
end

function has(name):
    name = checked_name(name)
    return __lsl_getenv(name) != None or name in _values
end

function require(name):
    name = checked_name(name)
    value = get(name, None)
    if value == None:
        Error(EnvironmentError: "missing environment variable " + name)
    end
    return value
end

call load_dotenv()
