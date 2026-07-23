# Dynamic operations implemented in LSL and compiled by the direct backend.

function __lsl_is_space(character):
    return character == " " or character == "\t" or character == "\r" or character == "\n"
end

function __lsl_ext_case(code):
    # Latin Extended-A: 1 = uppercase (lower is code+1), -1 = lowercase
    # (upper is code-1), 0 = no simple single-char mapping. Reversed subblocks
    # 0x139-0x148 and 0x179-0x17E have odd=upper; elsewhere even=upper.
    if code == 304 or code == 305 or code == 312 or code == 329 or code == 383 or code == 376:
        return 0
    end
    even = code % 2 == 0
    if (code >= 313 and code <= 328) or (code >= 377 and code <= 382):
        if even:
            return -1
        end
        return 1
    end
    if even:
        return 1
    end
    return -1
end

function __lsl_lower_code(code):
    if code >= 65 and code <= 90:
        return code + 32
    elif code >= 192 and code <= 222 and code != 215:
        return code + 32
    elif code == 376:
        return 255
    elif code >= 256 and code <= 383:
        if __lsl_ext_case(code) == 1:
            return code + 1
        end
    end
    return code
end

function __lsl_upper_code(code):
    if code >= 97 and code <= 122:
        return code - 32
    elif code == 181:
        return 924
    elif code >= 224 and code <= 254 and code != 247:
        return code - 32
    elif code == 255:
        return 376
    elif code == 305:
        return 73
    elif code == 383:
        return 83
    elif code >= 256 and code <= 382:
        if __lsl_ext_case(code) == -1:
            return code - 1
        end
    end
    return code
end

function __lsl_lower(text):
    result = ""
    for character in text:
        result += chr(__lsl_lower_code(ord(character)))
    end
    return result
end

function __lsl_upper(text):
    result = ""
    for character in text:
        result += chr(__lsl_upper_code(ord(character)))
    end
    return result
end

function __lsl_capitalize(text):
    if len(text) == 0:
        return text
    end
    return __lsl_upper(text[0]) + __lsl_lower(text[1:len(text)])
end

function __lsl_title(text):
    result = ""
    word_start = True
    for character in text:
        code = ord(character)
        if code >= 65 and code <= 90:
            if word_start:
                result += character
            else:
                result += chr(code + 32)
            end
            word_start = False
        elif code >= 97 and code <= 122:
            if word_start:
                result += chr(code - 32)
            else:
                result += character
            end
            word_start = False
        else:
            result += character
            word_start = True
        end
    end
    return result
end

function __lsl_startswith(text, prefix):
    if len(prefix) > len(text):
        return False
    end
    index = 0
    while index < len(prefix):
        if text[index] != prefix[index]:
            return False
        end
        index += 1
    end
    return True
end

function __lsl_endswith(text, suffix):
    if len(suffix) > len(text):
        return False
    end
    offset = len(text) - len(suffix)
    index = 0
    while index < len(suffix):
        if text[offset + index] != suffix[index]:
            return False
        end
        index += 1
    end
    return True
end

function __lsl_lstrip(text):
    start = 0
    while start < len(text) and __lsl_is_space(text[start]):
        start += 1
    end
    result = ""
    index = start
    while index < len(text):
        result += text[index]
        index += 1
    end
    return result
end

function __lsl_rstrip(text):
    stop = len(text)
    while stop > 0 and __lsl_is_space(text[stop - 1]):
        stop -= 1
    end
    result = ""
    index = 0
    while index < stop:
        result += text[index]
        index += 1
    end
    return result
end

function __lsl_strip(text):
    return __lsl_rstrip(__lsl_lstrip(text))
end

function __lsl_find(text, needle):
    if len(needle) == 0:
        return 0
    end
    limit = len(text) - len(needle)
    start = 0
    while start <= limit:
        matches = True
        index = 0
        while index < len(needle):
            if text[start + index] != needle[index]:
                matches = False
                break
            end
            index += 1
        end
        if matches:
            return start
        end
        start += 1
    end
    return -1
end

function __lsl_string_index(text, needle):
    position = __lsl_find(text, needle)
    if position < 0:
        Error(ValueError: "substring is not in String")
    end
    return position
end

function __lsl_split(text, separator):
    chars = __lsl_string_chars(text)
    seps = __lsl_string_chars(separator)
    count = len(chars)
    sep_len = len(seps)
    result = []
    current = ""
    index = 0
    while index < count:
        matches = False
        if sep_len > 0 and index + sep_len <= count:
            matches = True
            offset = 0
            while offset < sep_len:
                if chars[index + offset] != seps[offset]:
                    matches = False
                    break
                end
                offset += 1
            end
        end
        if matches:
            call result.append(current)
            current = ""
            index += sep_len
        else:
            current += chars[index]
            index += 1
        end
    end
    call result.append(current)
    return result
end

function __lsl_join(separator, values):
    result = ""
    index = 0
    while index < len(values):
        if index > 0:
            result += separator
        end
        result += values[index]
        index += 1
    end
    return result
end

function __lsl_extend(target, values):
    for value in values:
        call target.append(value)
    end
end

function __lsl_list(values):
    result = []
    value_code = __lsl_type_code(values)
    if value_code == 13:
        index = 0
        while index < len(values):
            result.append(__lsl_raw_int(values[index]))
            index += 1
        end
        return result
    elif value_code == 14:
        index = 0
        while index < len(values):
            result.append(__lsl_float_from_bits(__lsl_raw_int(values[index])))
            index += 1
        end
        return result
    elif value_code == 15:
        index = 0
        while index < len(values):
            result.append(__lsl_raw_int(values[index]))
            index += 1
        end
        return result
    end
    for value in values:
        result.append(value)
    end
    return result
end

function __lsl_require_real(value):
    value_type = __lsl_type_code(value)
    if value_type != 0 and value_type != 6 and value_type != 9:
        Error(TypeError: "RealArray accepts only Int or Float values")
    end
    return value
end

function __lsl_real_array(values):
    result = []
    for value in values:
        result.append(__lsl_require_real(value))
    end
    return result
end

function __lsl_sum(values):
    result = 0
    for value in values:
        result += value
    end
    return result
end

function __lsl_parse_float(text):
    normalized = __lsl_lower(text)
    if normalized == "nan" or normalized == "+nan" or normalized == "-nan":
        return 0.0 / 0.0
    elif normalized == "inf" or normalized == "+inf" or normalized == "infinity" or normalized == "+infinity":
        return 1.0 / 0.0
    elif normalized == "-inf" or normalized == "-infinity":
        return -1.0 / 0.0
    end
    sign = 1.0
    index = 0
    if len(text) > 0 and text[0] == "-":
        sign = -1.0
        index = 1
    elif len(text) > 0 and text[0] == "+":
        index = 1
    end
    value = 0.0
    fraction_scale = 1.0
    after_dot = False
    exponent = 0
    exponent_negative = False
    in_exponent = False
    exponent_sign_allowed = False
    digits = 0
    exponent_digits = 0
    while index < len(text):
        character = text[index]
        code = ord(character)
        if code >= 48 and code <= 57:
            digit = code - 48
            if in_exponent:
                exponent = exponent * 10 + digit
                exponent_digits += 1
                exponent_sign_allowed = False
            else:
                value = value * 10.0 + Float(digit)
                digits += 1
                if after_dot:
                    fraction_scale *= 10.0
                end
            end
        elif character == "." and not after_dot and not in_exponent:
            after_dot = True
        elif (character == "e" or character == "E") and not in_exponent and digits > 0:
            in_exponent = True
            exponent_sign_allowed = True
        elif in_exponent and exponent_sign_allowed and (character == "-" or character == "+"):
            if character == "-":
                exponent_negative = True
            end
            exponent_sign_allowed = False
        else:
            Error(ValueError: "invalid Float String")
        end
        index += 1
    end
    if digits == 0 or (in_exponent and exponent_digits == 0):
        Error(ValueError: "invalid Float String")
    end
    value /= fraction_scale
    while exponent > 0:
        if exponent_negative:
            value /= 10.0
        else:
            value *= 10.0
        end
        exponent -= 1
    end
    return value * sign
end

function __lsl_float_any(value):
    value_type = __lsl_type_code(value)
    if value_type == 6:
        return value
    elif value_type == 1:
        return __lsl_parse_float(value)
    elif value_type == 0:
        return __lsl_float_from_int(value)
    elif value_type == 9:
        return __lsl_float_from_int(__lsl_unbox_int(value))
    end
    Error(TypeError: "Float expects Int, Float, or String")
end

function __lsl_float_candidate(significand, digit_count, exponent):
    digits = __lsl_int_to_string(significand)
    if exponent >= 0 and exponent < 16:
        integer_count = exponent + 1
        result = digits[0:integer_count] + "."
        if integer_count < digit_count:
            return result + digits[integer_count:digit_count]
        end
        return result + "0"
    elif exponent < 0 and exponent > -7:
        result = "0."
        for index in rang(-exponent - 1):
            result += "0"
        end
        return result + digits[0:digit_count]
    end
    result = digits[0]
    if digit_count == 1:
        result += ".0"
    else:
        result += "." + digits[1:digit_count]
    end
    if exponent >= 0:
        return result + "e+" + __lsl_int_to_string(exponent)
    end
    return result + "e-" + __lsl_int_to_string(-exponent)
end

function __lsl_render_float_digits(significand, digit_count, exponent, negative):
    digits = __lsl_int_to_string(significand)
    prefix = ""
    if negative:
        prefix = "-"
    end
    if exponent >= 16 or exponent <= -7:
        return prefix + __lsl_float_candidate(significand, digit_count, exponent)
    end
    result = prefix
    if exponent >= 0:
        index = 0
        while index <= exponent:
            if index < digit_count:
                result += digits[index]
            else:
                result += "0"
            end
            index += 1
        end
        result += "."
        if index >= digit_count:
            result += "0"
        else:
            result += digits[index:digit_count]
        end
        return result
    end
    result += "0."
    for index in rang(-exponent - 1):
        result += "0"
    end
    return result + digits[0:digit_count]
end

function __lsl_format_float(value):
    bits = __lsl_float_bits(value)
    if bits == 9218868437227405312:
        return "inf"
    elif bits == -4503599627370496:
        return "-inf"
    elif bits > 9218868437227405312 or (bits < 0 and bits > -4503599627370496):
        return "nan"
    end
    negative = value < 0.0 or (value == 0.0 and bits < 0)
    if negative:
        value = -value
    end
    if value == 0.0:
        if negative:
            return "-0.0"
        end
        return "0.0"
    end
    integer_value = Int(value)
    if integer_value >= 0 and __lsl_float_from_int(integer_value) == value:
        integer_text = __lsl_int_to_string(integer_value) + ".0"
        if negative:
            return "-" + integer_text
        end
        return integer_text
    end
    target_bits = __lsl_float_bits(value)

    exponent = 0
    significand = 0
    round_digit = 0
    if integer_value >= 0 and value >= 1.0:
        integer_digits = len(__lsl_int_to_string(integer_value))
        exponent = integer_digits - 1
        significand = integer_value
        fraction = value - __lsl_float_from_int(integer_value)
        generated = integer_digits
        while generated < 17:
            fraction *= 10.0
            digit = Int(fraction)
            if digit < 0:
                digit = 0
            elif digit > 9:
                digit = 9
            end
            significand = significand * 10 + digit
            fraction -= __lsl_float_from_int(digit)
            generated += 1
        end
        round_digit = Int(fraction * 10.0)
    else:
        scaled = value
        while scaled >= 10.0:
            scaled /= 10.0
            exponent += 1
        end
        while scaled < 1.0:
            scaled *= 10.0
            exponent -= 1
        end
        for index in rang(17):
            digit = Int(scaled)
            if digit < 0:
                digit = 0
            elif digit > 9:
                digit = 9
            end
            significand = significand * 10 + digit
            scaled = (scaled - __lsl_float_from_int(digit)) * 10.0
        end
        round_digit = Int(scaled)
    end
    if round_digit >= 5:
        significand += 1
    end
    if significand >= 100000000000000000:
        significand = significand // 10
        exponent += 1
    end

    # Repeated decimal scaling above can drift by a few ulps. Correct the final
    # 17-digit integer against the original IEEE bits before shortening it.
    attempts = 0
    candidate = __lsl_float_candidate(significand, 17, exponent)
    parsed = __lsl_parse_float(candidate)
    while __lsl_float_bits(parsed) != target_bits and attempts < 10000:
        if parsed < value:
            significand += 1
        else:
            significand -= 1
        end
        candidate = __lsl_float_candidate(significand, 17, exponent)
        parsed = __lsl_parse_float(candidate)
        attempts += 1
    end
    if __lsl_float_bits(parsed) != target_bits:
        Error(FloatFormatError: "could not produce a round-trip decimal")
    end

    digit_count = 17
    shortening = True
    while digit_count > 1 and shortening:
        next_count = digit_count - 1
        matched = False
        rounded = (significand + 5) // 10
        rounded_text = __lsl_int_to_string(rounded)
        if len(rounded_text) == next_count:
            rounded_candidate = __lsl_float_candidate(rounded, next_count, exponent)
            if __lsl_float_bits(__lsl_parse_float(rounded_candidate)) == target_bits:
                significand = rounded
                digit_count = next_count
                matched = True
            end
        end
        if not matched:
            lower = significand // 10
            lower_text = __lsl_int_to_string(lower)
            if len(lower_text) == next_count:
                lower_candidate = __lsl_float_candidate(lower, next_count, exponent)
                if __lsl_float_bits(__lsl_parse_float(lower_candidate)) == target_bits:
                    significand = lower
                    digit_count = next_count
                    matched = True
                end
            end
        end
        if not matched:
            shortening = False
        end
    end
    return __lsl_render_float_digits(significand, digit_count, exponent, negative)
end

function __lsl_parse_int(text):
    length = len(text)
    index = 0
    sign = 1
    if length > 0 and text[0] == "-":
        sign = -1
        index = 1
    elif length > 0 and text[0] == "+":
        index = 1
    end
    if index >= length:
        Error(ValueError: "invalid Int String")
    end
    value = 0
    while index < length:
        code = ord(text[index])
        if code < 48 or code > 57:
            Error(ValueError: "invalid Int String")
        end
        value = value * 10 + (code - 48)
        index += 1
    end
    return value * sign
end

function __lsl_int_any(value):
    value_type = __lsl_type_code(value)
    if value_type == 0:
        return value
    elif value_type == 9:
        return __lsl_unbox_int(value)
    elif value_type == 1:
        return __lsl_parse_int(value)
    elif value_type == 6:
        return __lsl_float_to_int(value)
    elif value_type == 4:
        return __lsl_unbox_bool(value)
    end
    Error(TypeError: "Int expects Int, Float, String, or Bool")
end

function __lsl_int_to_string(number):
    if number == 0:
        return "0"
    end
    if number == -9223372036854775808:
        return "-9223372036854775808"
    end
    negative = False
    remaining = number
    if remaining < 0:
        negative = True
        remaining = -remaining
    end
    digits = ""
    while remaining > 0:
        digit = remaining % 10
        digits = chr(48 + digit) + digits
        remaining = remaining // 10
    end
    if negative:
        return "-" + digits
    end
    return digits
end

function __lsl_require_rang_step(value):
    if __lsl_type_code(value) == 9:
        return __lsl_unbox_int(value)
    end
    if __lsl_is_heap(value):
        Error(TypeError: "rang step must be an Int")
    end
    return __lsl_raw_int(value)
end

function __lsl_render(value, quote):
    if not __lsl_is_heap(value):
        return __lsl_int_to_string(value)
    end
    code = __lsl_type_code(value)
    if code == 0:
        return __lsl_int_to_string(value)
    elif code == 9:
        return __lsl_int_to_string(__lsl_unbox_int(value))
    elif code == 1:
        if quote:
            return "'" + value + "'"
        end
        return value
    elif code == 4:
        if __lsl_unbox_bool(value):
            return "True"
        end
        return "False"
    elif code == 5:
        return "None"
    elif code == 6:
        return __lsl_format_float(value)
    elif code == 10:
        return "<Function>"
    elif code == 3:
        result = "{"
        first = True
        for key in value.keys():
            if not first:
                result = result + ", "
            end
            result = result + __lsl_render(key, True) + ": " + __lsl_render(value[key], True)
            first = False
        end
        return result + "}"
    elif code == 13:
        result = "IntArray(["
        index = 0
        while index < len(value):
            if index > 0:
                result += ", "
            end
            result += __lsl_int_to_string(__lsl_raw_int(value[index]))
            index += 1
        end
        return result + "])"
    elif code == 14:
        result = "FloatArray(["
        index = 0
        while index < len(value):
            if index > 0:
                result += ", "
            end
            result += __lsl_format_float(__lsl_float_from_bits(__lsl_raw_int(value[index])))
            index += 1
        end
        return result + "])"
    elif code == 15:
        result = "ByteArray(["
        index = 0
        while index < len(value):
            if index > 0:
                result += ", "
            end
            result += __lsl_int_to_string(__lsl_raw_int(value[index]))
            index += 1
        end
        return result + "])"
    end
    open_bracket = "["
    close_bracket = "]"
    if code == 7:
        open_bracket = "("
        close_bracket = ")"
    elif code == 8:
        open_bracket = "!["
    end
    result = open_bracket
    index = 0
    length = len(value)
    while index < length:
        if index > 0:
            result = result + ", "
        end
        result = result + __lsl_render(value[index], True)
        index += 1
    end
    return result + close_bracket
end

function __lsl_str_value(value):
    return __lsl_render(value, False)
end

function __lsl_type_name(value):
    code = __lsl_type_code(value)
    if code == 0 or code == 9:
        return "Int"
    elif code == 1:
        return "String"
    elif code == 2:
        return "List"
    elif code == 3:
        return "Dictionary"
    elif code == 4:
        return "Bool"
    elif code == 5:
        return "None"
    elif code == 6:
        return "Float"
    elif code == 7:
        return "Tuple"
    elif code == 8:
        return "RealArray"
    elif code == 10:
        return "Function"
    elif code == 13:
        return "IntArray"
    elif code == 14:
        return "FloatArray"
    elif code == 15:
        return "ByteArray"
    end
    return "Any"
end

function __lsl_list_concat(left, right):
    result = []
    for value in left:
        result.append(value)
    end
    for value in right:
        result.append(value)
    end
    return result
end

function __lsl_float_floor(x):
    # floor of a Float, returned as Float. Int() truncates toward zero.
    truncated = Float(Int(x))
    if truncated > x:
        return truncated - 1.0
    end
    return truncated
end

function __lsl_ffloordiv(a, b):
    left = Float(a)
    right = Float(b)
    if right == 0.0:
        Error(ZeroDivisionError: "float floor division by zero")
    end
    return __lsl_float_floor(left / right)
end

function __lsl_fmod(a, b):
    left = Float(a)
    right = Float(b)
    if right == 0.0:
        Error(ZeroDivisionError: "float modulo by zero")
    end
    return left - __lsl_float_floor(left / right) * right
end

function __lsl_floordiv_dyn(a, b):
    # Both operands are Any (only reachable from user Any // Any). Boxed Int
    # remains on the exact signed Int path; boxed Float selects Float semantics.
    a_type = __lsl_type_code(a)
    b_type = __lsl_type_code(b)
    if a_type == 6 or b_type == 6:
        return __lsl_ffloordiv(a, b)
    end
    left = __lsl_raw_int(a)
    right = __lsl_raw_int(b)
    if a_type == 9:
        left = __lsl_unbox_int(a)
    end
    if b_type == 9:
        right = __lsl_unbox_int(b)
    end
    return left // right
end

function __lsl_mod_dyn(a, b):
    a_type = __lsl_type_code(a)
    b_type = __lsl_type_code(b)
    if a_type == 6 or b_type == 6:
        return __lsl_fmod(a, b)
    end
    left = __lsl_raw_int(a)
    right = __lsl_raw_int(b)
    if a_type == 9:
        left = __lsl_unbox_int(a)
    end
    if b_type == 9:
        right = __lsl_unbox_int(b)
    end
    return left % right
end

function __lsl_slice3(target, start, has_start, stop, has_stop, step):
    # General strided slice with Python semantics. step != 0. Negative step
    # flips the default bounds. Returns String for String targets, else List
    # (codegen retags Tuple/RealArray).
    if step == 0:
        Error(ValueError: "slice step cannot be zero")
    end
    length = len(target)
    if not has_start:
        if step > 0:
            start = 0
        else:
            start = length - 1
        end
    else:
        if start < 0:
            start += length
        end
        if step > 0:
            if start < 0:
                start = 0
            elif start > length:
                start = length
            end
        else:
            if start < 0:
                start = -1
            elif start > length - 1:
                start = length - 1
            end
        end
    end
    if not has_stop:
        if step > 0:
            stop = length
        else:
            stop = -1
        end
    else:
        if stop < 0:
            stop += length
        end
        if step > 0:
            if stop < 0:
                stop = 0
            elif stop > length:
                stop = length
            end
        else:
            if stop < 0:
                stop = -1
            elif stop > length - 1:
                stop = length - 1
            end
        end
    end
    is_string = __lsl_type_code(target) == 1
    parts = []
    index = start
    if step > 0:
        while index < stop:
            parts.append(target[index])
            index += step
        end
    else:
        while index > stop:
            parts.append(target[index])
            index += step
        end
    end
    if is_string:
        joined = ""
        for piece in parts:
            joined += piece
        end
        return joined
    end
    return parts
end

function __lsl_str_repeat(text, count):
    result = ""
    index = 0
    while index < count:
        result = result + text
        index += 1
    end
    return result
end

function __lsl_equal_seen(left, right, seen_left, seen_right):
    if __lsl_raw_equal(left, right):
        return True
    end
    left_code = __lsl_type_code(left)
    right_code = __lsl_type_code(right)
    if left_code != right_code:
        return False
    end
    if left_code == 2 or left_code == 7 or left_code == 8 or left_code == 3:
        seen_index = 0
        while seen_index < len(seen_left):
            if __lsl_raw_equal(seen_left[seen_index], left):
                return __lsl_raw_equal(seen_right[seen_index], right)
            end
            seen_index += 1
        end
        seen_left.append(left)
        seen_right.append(right)
    end
    if left_code == 2 or left_code == 7 or left_code == 8:
        length = len(left)
        if length != len(right):
            return False
        end
        index = 0
        while index < length:
            if not __lsl_equal_seen(left[index], right[index], seen_left, seen_right):
                return False
            end
            index += 1
        end
        return True
    elif left_code == 13:
        length = len(left)
        if length != len(right):
            return False
        end
        index = 0
        while index < length:
            if __lsl_raw_int(left[index]) != __lsl_raw_int(right[index]):
                return False
            end
            index += 1
        end
        return True
    elif left_code == 14:
        length = len(left)
        if length != len(right):
            return False
        end
        index = 0
        while index < length:
            left_value = __lsl_float_from_bits(__lsl_raw_int(left[index]))
            right_value = __lsl_float_from_bits(__lsl_raw_int(right[index]))
            if left_value != right_value:
                return False
            end
            index += 1
        end
        return True
    elif left_code == 15:
        length = len(left)
        if length != len(right):
            return False
        end
        index = 0
        while index < length:
            if __lsl_raw_int(left[index]) != __lsl_raw_int(right[index]):
                return False
            end
            index += 1
        end
        return True
    elif left_code == 3:
        if len(left) != len(right):
            return False
        end
        for key in left.keys():
            if not (key in right):
                return False
            end
            if not __lsl_equal_seen(left[key], right[key], seen_left, seen_right):
                return False
            end
        end
        return True
    end
    return __lsl_raw_equal(left, right)
end

function __lsl_equal(left, right):
    if __lsl_raw_equal(left, right):
        return True
    end
    left_code = __lsl_type_code(left)
    right_code = __lsl_type_code(right)
    if left_code != right_code:
        return False
    end
    if left_code == 2 or left_code == 7 or left_code == 8 or left_code == 13 or left_code == 14 or left_code == 15 or left_code == 3:
        return __lsl_equal_seen(left, right, [], [])
    end
    return False
end

function __lsl_min(values):
    first = True
    result = None
    for value in values:
        if first or value < result:
            result = value
        end
        first = False
    end
    if first:
        Error(ValueError: "min of empty sequence")
    end
    return result
end

function __lsl_max(values):
    first = True
    result = None
    for value in values:
        if first or value > result:
            result = value
        end
        first = False
    end
    if first:
        Error(ValueError: "max of empty sequence")
    end
    return result
end

function __lsl_delete_at(target, position):
    length = len(target)
    if position < 0:
        position += length
    end
    if position < 0 or position >= length:
        Error(IndexError: "del index out of range")
    end
    index = position
    while index + 1 < length:
        target[index] = target[index + 1]
        index += 1
    end
    call __lsl_pop_last(target)
end

function __lsl_insert(target, position, value):
    if position < 0:
        position += len(target)
    end
    if position < 0:
        position = 0
    elif position > len(target):
        position = len(target)
    end
    call target.append(None)
    index = len(target) - 1
    while index > position:
        target[index] = target[index - 1]
        index -= 1
    end
    target[position] = value
end

function __lsl_list_find(target, value):
    index = 0
    while index < len(target):
        if target[index] == value:
            return index
        end
        index += 1
    end
    return -1
end

function __lsl_list_index(target, value):
    position = __lsl_list_find(target, value)
    if position < 0:
        Error(ValueError: "value is not in collection")
    end
    return position
end

function __lsl_pop(target):
    if len(target) == 0:
        Error(IndexError: "pop from empty List")
    end
    return __lsl_pop_last(target)
end

function __lsl_pop_at(target, position):
    length = len(target)
    if position < 0:
        position += length
    end
    if position < 0 or position >= length:
        Error(IndexError: "pop index out of range")
    end
    value = target[position]
    call __lsl_delete_at(target, position)
    return value
end

function __lsl_list_count(target, value):
    result = 0
    for item in target:
        if item == value:
            result += 1
        end
    end
    return result
end

function __lsl_remove(target, value):
    position = __lsl_list_find(target, value)
    if position < 0:
        Error(ValueError: "value is not in List")
    end
    call __lsl_delete_at(target, position)
end

function __lsl_reverse(target):
    left = 0
    right = len(target) - 1
    while left < right:
        temporary = target[left]
        target[left] = target[right]
        target[right] = temporary
        left += 1
        right -= 1
    end
end

function __lsl_sort(target):
    limit = len(target)
    while limit > 1:
        index = 1
        while index < limit:
            if target[index] < target[index - 1]:
                temporary = target[index]
                target[index] = target[index - 1]
                target[index - 1] = temporary
            end
            index += 1
        end
        limit -= 1
    end
end

function __lsl_copy(target):
    return target[0:len(target)]
end

function __lsl_dict_get(target, key, default_value):
    if key in target:
        return target[key]
    end
    return default_value
end

function __lsl_setdefault(target, key, default_value):
    if key not in target:
        target[key] = default_value
    end
    return target[key]
end

function __lsl_update(target, values):
    for key in values.keys():
        target[key] = values[key]
    end
end

function __lsl_dictionary(values):
    if __lsl_type_code(values) == 3:
        return __lsl_dict_copy(values)
    end
    result = {}
    for entry in values:
        if len(entry) != 2:
            Error(ValueError: "Dictionary entries must contain two values")
        end
        result[entry[0]] = entry[1]
    end
    return result
end

function __lsl_dict_values(target):
    result = []
    for key in target.keys():
        result.append(target[key])
    end
    return result
end

function __lsl_dict_items(target):
    result = []
    for key in target.keys():
        result.append((key, target[key]))
    end
    return result
end

function __lsl_dict_copy(target):
    result = {}
    call result.update(target)
    return result
end

function __lsl_dict_clear(target):
    keys = target.keys()
    for key in keys:
        del(target[key])
    end
end

function __lsl_dict_pop(target, key):
    value = target[key]
    del(target[key])
    return value
end

function __lsl_dict_pop_default(target, key, default_value):
    if key not in target:
        return default_value
    end
    return __lsl_dict_pop(target, key)
end

function __lsl_replace(text, old_value, new_value):
    result = ""
    index = 0
    while index < len(text):
        matches = False
        if index + len(old_value) <= len(text):
            matches = True
            offset = 0
            while offset < len(old_value):
                if text[index + offset] != old_value[offset]:
                    matches = False
                    break
                end
                offset += 1
            end
        end
        if matches:
            result += new_value
            index += len(old_value)
        else:
            result += text[index]
            index += 1
        end
    end
    return result
end

function __lsl_count(text, needle):
    count = 0
    offset = 0
    while offset <= len(text) - len(needle):
        found = __lsl_find_offset(text, needle, offset)
        if found < 0:
            break
        end
        count += 1
        step = len(needle)
        if step < 1:
            step = 1
        end
        offset = found + step
    end
    return count
end

function __lsl_find_offset(text, needle, offset):
    limit = len(text) - len(needle)
    start = offset
    while start <= limit:
        matches = True
        index = 0
        while index < len(needle):
            if text[start + index] != needle[index]:
                matches = False
                break
            end
            index += 1
        end
        if matches:
            return start
        end
        start += 1
    end
    return -1
end
