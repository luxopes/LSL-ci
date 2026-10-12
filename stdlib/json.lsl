# Pure-LSL JSON codec. No libc or foreign runtime.

JSON_MAX_BYTES = 4194304
JSON_MAX_DEPTH = 128
JSON_MAX_ITEMS = 262144

function spend(budget, amount):
    amount = Int(amount)
    if amount < 0 or amount > budget[0]:
        Error(JsonError: "encoded JSON exceeds 4 MiB")
    end
    budget[0] -= amount
end

function escape_string(text, budget):
    if type(text) != "String":
        Error(JsonError: "JSON object keys must be Strings")
    end
    source = String(text)
    count = __lsl_text_byte_length(source)
    if count + 2 > budget[0]:
        Error(JsonError: "encoded JSON exceeds 4 MiB")
    end
    # Build escaped UTF-8 as raw bytes. Per-character String pieces used one
    # heap object per input character and made large values a memory DoS.
    result = __lsl_byte_zeros(0)
    result.append(34)
    hexadecimal = "0123456789abcdef"
    index = 0
    while index < count:
        code = __lsl_text_byte(source, index)
        if code == 34 or code == 92:
            result.append(92)
            result.append(code)
        elif code == 8:
            result.append(92)
            result.append(98)
        elif code == 12:
            result.append(92)
            result.append(102)
        elif code == 10:
            result.append(92)
            result.append(110)
        elif code == 13:
            result.append(92)
            result.append(114)
        elif code == 9:
            result.append(92)
            result.append(116)
        elif code < 32:
            result.append(92)
            result.append(117)
            result.append(48)
            result.append(48)
            result.append(__lsl_text_byte(hexadecimal, code // 16))
            result.append(__lsl_text_byte(hexadecimal, code % 16))
        elif code < 128:
            result.append(code)
        else:
            if code >= 194 and code <= 223:
                width = 2
            elif code >= 224 and code <= 239:
                width = 3
            elif code >= 240 and code <= 244:
                width = 4
            else:
                Error(JsonError: "String contains invalid UTF-8")
            end
            remaining = width - 1
            if index + remaining >= count:
                Error(JsonError: "String contains truncated UTF-8")
            end
            second = __lsl_text_byte(source, index + 1)
            if second < 128 or second > 191 or (code == 224 and second < 160) or (code == 237 and second > 159) or (code == 240 and second < 144) or (code == 244 and second > 143):
                Error(JsonError: "String contains invalid UTF-8")
            end
            result.append(code)
            copied = 1
            while copied <= remaining:
                continuation = __lsl_text_byte(source, index + copied)
                if continuation < 128 or continuation > 191:
                    Error(JsonError: "String contains invalid UTF-8")
                end
                result.append(continuation)
                copied += 1
            end
            index += remaining
        end
        if len(result) + 1 > budget[0]:
            Error(JsonError: "encoded JSON exceeds 4 MiB")
        end
        index += 1
    end
    result.append(34)
    call spend(budget, len(result))
    return __lsl_text_from_bytes(result, 0, len(result))
end

function encode_value(value, depth, budget):
    if depth > JSON_MAX_DEPTH:
        Error(JsonError: "JSON nesting exceeds 128 levels")
    end
    value_type = __lsl_type_code(value)
    if value_type == 1:
        return escape_string(value, budget)
    elif value_type == 2 or value_type == 7 or value_type == 8 or value_type == 13 or value_type == 14 or value_type == 15:
        if len(value) > JSON_MAX_ITEMS:
            Error(JsonError: "JSON Array contains too many items")
        end
        call spend(budget, 2 + max(0, len(value) - 1))
        pieces = []
        index = 0
        while index < len(value):
            pieces.append(encode_value(value[index], depth + 1, budget))
            index += 1
        end
        return "[" + ",".join(pieces) + "]"
    elif value_type == 3:
        if len(value) > JSON_MAX_ITEMS:
            Error(JsonError: "JSON Object contains too many entries")
        end
        call spend(budget, 2 + max(0, len(value) - 1) + len(value))
        pieces = []
        keys = value.keys()
        index = 0
        while index < len(keys):
            key = keys[index]
            pieces.append(escape_string(key, budget) + ":" + encode_value(value[key], depth + 1, budget))
            index += 1
        end
        return "{" + ",".join(pieces) + "}"
    elif value_type == 4:
        # Rozpočet podle skutečné délky tokenu (true 4, false 5 bajtů).
        if __lsl_unbox_bool(value):
            call spend(budget, 4)
            return "true"
        end
        call spend(budget, 5)
        return "false"
    elif value_type == 5:
        call spend(budget, 4)
        return "null"
    elif value_type == 6:
        result = __lsl_float_string(value)
        if result == "nan" or result == "inf" or result == "-inf":
            Error(JsonError: "JSON cannot encode NaN or Infinity")
        end
        call spend(budget, len(result))
        return result
    elif value_type == 0 or value_type == 9:
        result = String(value)
        call spend(budget, len(result))
        return result
    end
    Error(JsonError: "value is not JSON-serializable: " + type(value))
    return ""
end

function encode(value):
    budget = [JSON_MAX_BYTES]
    return encode_value(value, 1, budget)
end

function skip_space(state):
    source = String(state[0])
    index = state[1]
    while index < state[3]:
        value = __lsl_text_byte(source, index)
        if value != 32 and value != 10 and value != 13 and value != 9:
            break
        end
        index += 1
    end
    state[1] = index
end

function json_error(message):
    Error(JsonError: message)
end

function json_digit(value):
    return value >= 48 and value <= 57
end

function hex_value(state):
    source = String(state[0])
    if state[1] + 4 > state[3]:
        call json_error("incomplete Unicode escape")
    end
    value = 0
    count = 0
    while count < 4:
        code = __lsl_text_byte(source, state[1])
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

function append_codepoint(output, codepoint):
    encoded = chr(codepoint)
    count = __lsl_text_byte_length(encoded)
    index = 0
    while index < count:
        output.append(__lsl_text_byte(encoded, index))
        index += 1
    end
end

function byte_slice(state, start, stop):
    source = String(state[0])
    count = stop - start
    output = __lsl_byte_zeros(count)
    index = 0
    while index < count:
        output[index] = __lsl_text_byte(source, start + index)
        index += 1
    end
    return __lsl_text_from_bytes(output, 0, count)
end

function matches_ascii(state, literal):
    source = String(state[0])
    expected = String(literal)
    count = __lsl_text_byte_length(expected)
    if state[1] + count > state[3]:
        return False
    end
    index = 0
    while index < count:
        if __lsl_text_byte(source, state[1] + index) != __lsl_text_byte(expected, index):
            return False
        end
        index += 1
    end
    return True
end

function parse_string(state):
    source = String(state[0])
    if state[1] >= state[3] or __lsl_text_byte(source, state[1]) != 34:
        call json_error("expected String")
    end
    state[1] = state[1] + 1
    output = __lsl_byte_zeros(0)
    while state[1] < state[3]:
        value = __lsl_text_byte(source, state[1])
        state[1] = state[1] + 1
        if value == 34:
            return __lsl_text_from_bytes(output, 0, len(output))
        elif value == 92:
            if state[1] >= state[3]:
                call json_error("unfinished escape sequence")
            end
            escaped = __lsl_text_byte(source, state[1])
            state[1] = state[1] + 1
            if escaped == 34 or escaped == 92 or escaped == 47:
                output.append(escaped)
            elif escaped == 110:
                output.append(10)
            elif escaped == 114:
                output.append(13)
            elif escaped == 116:
                output.append(9)
            elif escaped == 98:
                output.append(8)
            elif escaped == 102:
                output.append(12)
            elif escaped == 117:
                codepoint = __lsl_typed_int(hex_value(state))
                if codepoint >= 55296 and codepoint <= 56319:
                    if state[1] + 2 > state[3]:
                        call json_error("high surrogate requires a low surrogate")
                    end
                    if __lsl_text_byte(source, state[1]) != 92 or __lsl_text_byte(source, state[1] + 1) != 117:
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
                call append_codepoint(output, codepoint)
            else:
                call json_error("invalid escape sequence")
            end
        elif value < 32:
            call json_error("unescaped control character")
        elif value < 128:
            output.append(value)
        else:
            # Validate canonical UTF-8 while copying it. Invalid continuation,
            # overlong encodings, surrogate encodings and values above U+10FFFF
            # are rejected instead of being smuggled into an LSL String.
            if value >= 194 and value <= 223:
                width = 2
            elif value >= 224 and value <= 239:
                width = 3
            elif value >= 240 and value <= 244:
                width = 4
            else:
                call json_error("invalid UTF-8 in JSON String")
            end
            remaining = width - 1
            if state[1] + remaining > state[3]:
                call json_error("truncated UTF-8 in JSON String")
            end
            second = __lsl_text_byte(source, state[1])
            if second < 128 or second > 191:
                call json_error("invalid UTF-8 continuation byte")
            elif value == 224 and second < 160:
                call json_error("overlong UTF-8 sequence")
            elif value == 237 and second > 159:
                call json_error("UTF-8 surrogate is not allowed")
            elif value == 240 and second < 144:
                call json_error("overlong UTF-8 sequence")
            elif value == 244 and second > 143:
                call json_error("UTF-8 code point is out of range")
            end
            output.append(value)
            copied = 0
            while copied < remaining:
                continuation = __lsl_text_byte(source, state[1])
                if continuation < 128 or continuation > 191:
                    call json_error("invalid UTF-8 continuation byte")
                end
                output.append(continuation)
                state[1] = state[1] + 1
                copied += 1
            end
        end
        if len(output) > JSON_MAX_BYTES:
            call json_error("decoded JSON String exceeds 4 MiB")
        end
    end
    call json_error("unterminated String")
    return ""
end

function decimal_within(digits, limit):
    if len(digits) < len(limit):
        return True
    elif len(digits) > len(limit):
        return False
    end
    index = 0
    while index < len(digits):
        digit = ord(digits[index])
        boundary = ord(limit[index])
        if digit < boundary:
            return True
        elif digit > boundary:
            return False
        end
        index += 1
    end
    return True
end

function parse_number(state):
    source = String(state[0])
    start = state[1]
    if state[1] < state[3] and __lsl_text_byte(source, state[1]) == 45:
        state[1] = state[1] + 1
    end
    if state[1] >= state[3]:
        call json_error("invalid number")
    end
    if __lsl_text_byte(source, state[1]) == 48:
        state[1] = state[1] + 1
        if state[1] < state[3] and json_digit(__lsl_text_byte(source, state[1])):
            call json_error("leading zero in number")
        end
    elif json_digit(__lsl_text_byte(source, state[1])):
        while state[1] < state[3] and json_digit(__lsl_text_byte(source, state[1])):
            state[1] = state[1] + 1
            if state[1] - start > 1024:
                call json_error("JSON number token is too long")
            end
        end
    else:
        call json_error("invalid number")
    end
    is_float = False
    if state[1] < state[3] and __lsl_text_byte(source, state[1]) == 46:
        is_float = True
        state[1] = state[1] + 1
        fraction_start = state[1]
        while state[1] < state[3] and json_digit(__lsl_text_byte(source, state[1])):
            state[1] = state[1] + 1
            if state[1] - start > 1024:
                call json_error("JSON number token is too long")
            end
        end
        if state[1] == fraction_start:
            call json_error("fraction requires digits")
        end
    end
    if state[1] < state[3] and (__lsl_text_byte(source, state[1]) == 101 or __lsl_text_byte(source, state[1]) == 69):
        is_float = True
        state[1] = state[1] + 1
        if state[1] < state[3] and (__lsl_text_byte(source, state[1]) == 43 or __lsl_text_byte(source, state[1]) == 45):
            state[1] = state[1] + 1
        end
        exponent_start = state[1]
        while state[1] < state[3] and json_digit(__lsl_text_byte(source, state[1])):
            state[1] = state[1] + 1
            if state[1] - start > 1024:
                call json_error("JSON number token is too long")
            end
        end
        if state[1] == exponent_start:
            call json_error("exponent requires digits")
        end
    end
    token = byte_slice(state, start, state[1])
    if len(token) > 1024:
        call json_error("JSON number token is too long")
    end
    if is_float:
        value = Float(token)
        rendered = __lsl_float_string(value)
        if rendered == "nan" or rendered == "inf" or rendered == "-inf":
            call json_error("JSON number is outside the finite Float range")
        end
        return value
    end
    digits = token
    limit = "9223372036854775807"
    if token.startswith("-"):
        digits = token[1:len(token)]
        limit = "9223372036854775808"
    end
    if not decimal_within(digits, limit):
        call json_error("JSON integer is outside the Int64 range")
    end
    return Int(token)
end

function parse_array(state):
    source = String(state[0])
    result = []
    state[1] = state[1] + 1
    call skip_space(state)
    if state[1] >= state[3]:
        call json_error("unterminated Array")
    end
    if __lsl_text_byte(source, state[1]) == 93:
        state[1] = state[1] + 1
        return result
    end
    loop:
        result.append(parse_value(state))
        if len(result) > JSON_MAX_ITEMS:
            call json_error("JSON Array contains too many items")
        end
        call skip_space(state)
        if state[1] >= state[3]:
            call json_error("unterminated Array")
        end
        character = __lsl_text_byte(source, state[1])
        state[1] = state[1] + 1
        if character == 93:
            return result
        elif character != 44:
            call json_error("expected comma in Array")
        end
        call skip_space(state)
        if state[1] >= state[3] or __lsl_text_byte(source, state[1]) == 93:
            call json_error("expected Array value")
        end
    end
end

function parse_object(state):
    source = String(state[0])
    result = {}
    state[1] = state[1] + 1
    call skip_space(state)
    if state[1] >= state[3]:
        call json_error("unterminated Object")
    end
    if __lsl_text_byte(source, state[1]) == 125:
        state[1] = state[1] + 1
        return result
    end
    loop:
        if state[1] >= state[3] or __lsl_text_byte(source, state[1]) != 34:
            call json_error("Object key must be a String")
        end
        key = parse_string(state)
        call skip_space(state)
        if state[1] >= state[3] or __lsl_text_byte(source, state[1]) != 58:
            call json_error("expected colon in Object")
        end
        state[1] = state[1] + 1
        call skip_space(state)
        if key in result:
            call json_error("duplicate JSON Object key")
        end
        result[key] = parse_value(state)
        if len(result) > JSON_MAX_ITEMS:
            call json_error("JSON Object contains too many entries")
        end
        call skip_space(state)
        if state[1] >= state[3]:
            call json_error("unterminated Object")
        end
        character = __lsl_text_byte(source, state[1])
        state[1] = state[1] + 1
        if character == 125:
            return result
        elif character != 44:
            call json_error("expected comma in Object")
        end
        call skip_space(state)
        if state[1] >= state[3] or __lsl_text_byte(source, state[1]) == 125:
            call json_error("expected Object entry")
        end
    end
end

function parse_value(state):
    source = String(state[0])
    state[2] += 1
    if state[2] > JSON_MAX_DEPTH:
        call json_error("JSON nesting exceeds 128 levels")
    end
    call skip_space(state)
    if state[1] >= state[3]:
        call json_error("expected value")
    end
    character = __lsl_text_byte(source, state[1])
    if character == 34:
        result = parse_string(state)
    elif character == 91:
        result = parse_array(state)
    elif character == 123:
        result = parse_object(state)
    elif matches_ascii(state, "true"):
        state[1] = state[1] + 4
        result = __lsl_box_bool(True)
    elif matches_ascii(state, "false"):
        state[1] = state[1] + 5
        result = __lsl_box_bool(False)
    elif matches_ascii(state, "null"):
        state[1] = state[1] + 4
        result = __lsl_box_none()
    elif character == 45 or json_digit(character):
        result = parse_number(state)
    else:
        call json_error("invalid value")
    end
    state[2] -= 1
    return result
end

function decode(text):
    if type(text) != "String":
        call json_error("JSON input must be a String")
    end
    source = String(text)
    byte_count = __lsl_text_byte_length(source)
    if byte_count > JSON_MAX_BYTES:
        call json_error("JSON input exceeds 4 MiB")
    end
    state = [source, 0, 0, byte_count]
    result = parse_value(state)
    call skip_space(state)
    if state[1] != byte_count:
        call json_error("trailing data")
    end
    return result
end

function pretty(value):
    # Deterministic compact JSON is valid pretty output until indentation options land.
    return encode(value) + chr(10)
end
