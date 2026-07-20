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

function hex_digit(character):
    digits = "0123456789abcdef"
    result = digits.index(character)
    if result < 0:
        result = "0123456789ABCDEF".index(character)
    end
    return result
end

function hex_value(state):
    text = state[0]
    value = 0
    count = 0
    while count < 4:
        value = value * 16 + hex_digit(text[state[1]])
        state[1] = state[1] + 1
        count += 1
    end
    return value
end

function parse_string(state):
    text = state[0]
    state[1] = state[1] + 1
    result = ""
    slash = chr(92)
    while state[1] < len(text):
        character = text[state[1]]
        state[1] = state[1] + 1
        if character == "\"":
            return result
        elif character == slash:
            escaped = text[state[1]]
            state[1] = state[1] + 1
            if escaped == "n":
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
                codepoint = hex_value(state)
                if codepoint >= 55296 and codepoint <= 56319:
                    if text[state[1]] == slash and text[state[1] + 1] == "u":
                        state[1] = state[1] + 2
                        low = hex_value(state)
                        codepoint = 65536 + (codepoint - 55296) * 1024 + low - 56320
                    end
                end
                result += chr(codepoint)
            else:
                result += escaped
            end
        else:
            result += character
        end
    end
    Error(JsonError: "unterminated String")
    return ""
end

function parse_number(state):
    text = state[0]
    start = state[1]
    while state[1] < len(text) and text[state[1]] in "-0123456789":
        state[1] = state[1] + 1
    end
    return Int(text[start:state[1]])
end

function parse_array(state):
    result = []
    state[1] = state[1] + 1
    call skip_space(state)
    if state[0][state[1]] == "]":
        state[1] = state[1] + 1
        return result
    end
    loop:
        result.append(parse_value(state))
        call skip_space(state)
        character = state[0][state[1]]
        state[1] = state[1] + 1
        if character == "]":
            return result
        elif character != ",":
            Error(JsonError: "expected comma in Array")
        end
        call skip_space(state)
    end
end

function parse_object(state):
    result = {}
    state[1] = state[1] + 1
    call skip_space(state)
    if state[0][state[1]] == "}":
        state[1] = state[1] + 1
        return result
    end
    loop:
        key = parse_string(state)
        call skip_space(state)
        if state[0][state[1]] != ":":
            Error(JsonError: "expected colon in Object")
        end
        state[1] = state[1] + 1
        call skip_space(state)
        result[key] = parse_value(state)
        call skip_space(state)
        character = state[0][state[1]]
        state[1] = state[1] + 1
        if character == "}":
            return result
        elif character != ",":
            Error(JsonError: "expected comma in Object")
        end
        call skip_space(state)
    end
end

function parse_value(state):
    call skip_space(state)
    text = state[0]
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
    end
    return parse_number(state)
end

function decode(text):
    state = [text, 0]
    return parse_value(state)
end

function pretty(value):
    # Deterministic compact JSON is valid pretty output until indentation options land.
    return encode(value) + chr(10)
end
