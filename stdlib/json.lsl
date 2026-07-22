# Pure-LSL JSON codec. No libc or foreign runtime.

function escape_string(text):
    result = "\""
    slash = chr(92)
    for character in text:
        if character == "\"" or character == slash:
            result += slash + character
        elif character == chr(10):
            result += slash + "n"
        elif character == chr(13):
            result += slash + "r"
        elif character == chr(9):
            result += slash + "t"
        else:
            result += character
        end
    end
    return result + "\""
end

function encode(value):
    value_type = __lsl_type_code(value)
    if value_type == 1:
        return escape_string(value)
    elif value_type == 2 or value_type == 7 or value_type == 8:
        result = "["
        index = 0
        while index < len(value):
            if index > 0:
                result += ","
            end
            result += encode(value[index])
            index += 1
        end
        return result + "]"
    elif value_type == 3:
        result = "{"
        keys = value.keys()
        index = 0
        while index < len(keys):
            if index > 0:
                result += ","
            end
            key = keys[index]
            result += escape_string(key) + ":" + encode(value[key])
            index += 1
        end
        return result + "}"
    elif value_type == 4:
        if __lsl_unbox_bool(value):
            return "true"
        end
        return "false"
    elif value_type == 5:
        return "null"
    elif value_type == 6:
        return __lsl_float_string(value)
    end
    return String(value)
end

function skip_space(state):
    text = state[0]
    index = state[1]
    while index < len(text):
        if text[index] not in " \n\r\t":
            break
        end
        index += 1
    end
    state[1] = index
end

function json_error(message):
    Error(JsonError: message)
end

function json_digit(character):
    code = ord(character)
    return code >= 48 and code <= 57
end

function hex_value(state):
    text = state[0]
    if state[1] + 4 > len(text):
        call json_error("incomplete Unicode escape")
    end
    value = 0
    count = 0
    while count < 4:
        code = ord(text[state[1]])
        if code >= 48 and code <= 57:
            digit = code - 48
        elif code >= 97 and code <= 102:
            digit = code - 87
        elif code >= 65 and code <= 70:
            digit = code - 55
        else:
            call json_error("invalid Unicode escape")
        end
        value = value * 16 + digit
        state[1] = state[1] + 1
        count += 1
    end
    return value
end

function parse_string(state):
    text = state[0]
    if state[1] >= len(text) or text[state[1]] != "\"":
        call json_error("expected String")
    end
    state[1] = state[1] + 1
    result = ""
    slash = chr(92)
    while state[1] < len(text):
        character = text[state[1]]
        state[1] = state[1] + 1
        if character == "\"":
            return result
        elif character == slash:
            if state[1] >= len(text):
                call json_error("unfinished escape sequence")
            end
            escaped = text[state[1]]
            state[1] = state[1] + 1
            if escaped == "\"" or escaped == slash or escaped == "/":
                result += escaped
            elif escaped == "n":
                result += chr(10)
            elif escaped == "r":
                result += chr(13)
            elif escaped == "t":
                result += chr(9)
            elif escaped == "b":
                result += chr(8)
            elif escaped == "f":
                result += chr(12)
            elif escaped == "u":
                codepoint = __lsl_typed_int(hex_value(state))
                if codepoint >= 55296 and codepoint <= 56319:
                    if state[1] + 2 > len(text):
                        call json_error("high surrogate requires a low surrogate")
                    end
                    if text[state[1]] != slash or text[state[1] + 1] != "u":
                        call json_error("high surrogate requires a low surrogate")
                    end
                    state[1] = state[1] + 2
                    low = __lsl_typed_int(hex_value(state))
                    if low < 56320 or low > 57343:
                        call json_error("invalid low surrogate")
                    end
                    codepoint = 65536 + (codepoint - 55296) * 1024 + low - 56320
                elif codepoint >= 56320 and codepoint <= 57343:
                    call json_error("unexpected low surrogate")
                end
                result += chr(codepoint)
            else:
                call json_error("invalid escape sequence")
            end
        elif ord(character) < 32:
            call json_error("unescaped control character")
        else:
            result += character
        end
    end
    call json_error("unterminated String")
    return ""
end

function parse_number(state):
    text = state[0]
    start = state[1]
    if state[1] < len(text) and text[state[1]] == "-":
        state[1] = state[1] + 1
    end
    if state[1] >= len(text):
        call json_error("invalid number")
    end
    if text[state[1]] == "0":
        state[1] = state[1] + 1
        if state[1] < len(text) and json_digit(text[state[1]]):
            call json_error("leading zero in number")
        end
    elif json_digit(text[state[1]]):
        while state[1] < len(text) and json_digit(text[state[1]]):
            state[1] = state[1] + 1
        end
    else:
        call json_error("invalid number")
    end
    is_float = False
    if state[1] < len(text) and text[state[1]] == ".":
        is_float = True
        state[1] = state[1] + 1
        fraction_start = state[1]
        while state[1] < len(text) and json_digit(text[state[1]]):
            state[1] = state[1] + 1
        end
        if state[1] == fraction_start:
            call json_error("fraction requires digits")
        end
    end
    if state[1] < len(text) and (text[state[1]] == "e" or text[state[1]] == "E"):
        is_float = True
        state[1] = state[1] + 1
        if state[1] < len(text) and (text[state[1]] == "+" or text[state[1]] == "-"):
            state[1] = state[1] + 1
        end
        exponent_start = state[1]
        while state[1] < len(text) and json_digit(text[state[1]]):
            state[1] = state[1] + 1
        end
        if state[1] == exponent_start:
            call json_error("exponent requires digits")
        end
    end
    token = text[start:state[1]]
    if is_float:
        return Float(token)
    end
    return Int(token)
end

function parse_array(state):
    result = []
    state[1] = state[1] + 1
    call skip_space(state)
    if state[1] >= len(state[0]):
        call json_error("unterminated Array")
    end
    if state[0][state[1]] == "]":
        state[1] = state[1] + 1
        return result
    end
    loop:
        result.append(parse_value(state))
        call skip_space(state)
        if state[1] >= len(state[0]):
            call json_error("unterminated Array")
        end
        character = state[0][state[1]]
        state[1] = state[1] + 1
        if character == "]":
            return result
        elif character != ",":
            call json_error("expected comma in Array")
        end
        call skip_space(state)
        if state[1] >= len(state[0]) or state[0][state[1]] == "]":
            call json_error("expected Array value")
        end
    end
end

function parse_object(state):
    result = {}
    state[1] = state[1] + 1
    call skip_space(state)
    if state[1] >= len(state[0]):
        call json_error("unterminated Object")
    end
    if state[0][state[1]] == "}":
        state[1] = state[1] + 1
        return result
    end
    loop:
        if state[1] >= len(state[0]) or state[0][state[1]] != "\"":
            call json_error("Object key must be a String")
        end
        key = parse_string(state)
        call skip_space(state)
        if state[1] >= len(state[0]) or state[0][state[1]] != ":":
            call json_error("expected colon in Object")
        end
        state[1] = state[1] + 1
        call skip_space(state)
        result[key] = parse_value(state)
        call skip_space(state)
        if state[1] >= len(state[0]):
            call json_error("unterminated Object")
        end
        character = state[0][state[1]]
        state[1] = state[1] + 1
        if character == "}":
            return result
        elif character != ",":
            call json_error("expected comma in Object")
        end
        call skip_space(state)
        if state[1] >= len(state[0]) or state[0][state[1]] == "}":
            call json_error("expected Object entry")
        end
    end
end

function parse_value(state):
    call skip_space(state)
    text = state[0]
    if state[1] >= len(text):
        call json_error("expected value")
    end
    character = text[state[1]]
    if character == "\"":
        return parse_string(state)
    elif character == "[":
        return parse_array(state)
    elif character == "{":
        return parse_object(state)
    elif text[state[1]:state[1] + 4] == "true":
        state[1] = state[1] + 4
        return __lsl_box_bool(True)
    elif text[state[1]:state[1] + 5] == "false":
        state[1] = state[1] + 5
        return __lsl_box_bool(False)
    elif text[state[1]:state[1] + 4] == "null":
        state[1] = state[1] + 4
        return __lsl_box_none()
    elif character == "-" or json_digit(character):
        return parse_number(state)
    end
    call json_error("invalid value")
    return None
end

function decode(text):
    state = [text, 0]
    result = parse_value(state)
    call skip_space(state)
    if state[1] != len(text):
        call json_error("trailing data")
    end
    return result
end

function pretty(value):
    # Deterministic compact JSON is valid pretty output until indentation options land.
    return encode(value) + chr(10)
end
