# Full token-span lexer for the direct compiler.
#
# The source is scanned as UTF-8 bytes through the text intrinsics instead of
# materializing one String per code point. Columns still count code points:
# every byte that is not a continuation byte (10xxxxxx) starts a new column.
# Identifiers, numbers and operators are ASCII; other bytes only occur inside
# String literals and comments, or end in the unexpected-character diagnostic.

load diagnostics

function is_digit(code):
    return code >= 48 and code <= 57
end

function is_alpha(code):
    return (code >= 97 and code <= 122) or (code >= 65 and code <= 90) or code == 95
end

function digit_value(code):
    if code >= 48 and code <= 57:
        return code - 48
    elif code >= 97 and code <= 102:
        return code - 87
    elif code >= 65 and code <= 70:
        return code - 55
    end
    return -1
end

# Byte length of the UTF-8 sequence introduced by its first byte.
function char_width(code):
    if code < 128:
        return 1
    elif code < 224:
        return 2
    elif code < 240:
        return 3
    end
    return 4
end

function decimal_scale_add(digits, base, addend):
    # Big-endian decimal String multiplied by base plus one digit. Converting a
    # based literal in decimal rather than in an Int keeps the whole Int64
    # pattern range spellable: the token stays an ordinary decimal literal and
    # wraps in exactly the same place a decimal literal would.
    result = ""
    carry = addend
    index = len(digits) - 1
    while index >= 0:
        product = (ord(digits[index]) - 48) * base + carry
        result = chr(48 + product % 10) + result
        carry = product // 10
        index -= 1
    end
    while carry > 0:
        result = chr(48 + carry % 10) + result
        carry = carry // 10
    end
    if len(result) == 0:
        return "0"
    end
    return result
end

function source_line(source, line_number):
    lines = source.split(chr(10))
    if line_number < 1 or line_number > len(lines):
        return ""
    end
    return lines[line_number - 1]
end

function token(kind, value, line, column, end_column):
    return {"kind": kind, "value": value, "line": line, "column": column, "end_column": end_column}
end

# Byte value of the character an escape sequence stands for.
function decode_escape(path, lines, line, column, escaped):
    if escaped == 110:
        return 10
    elif escaped == 114:
        return 13
    elif escaped == 116:
        return 9
    elif escaped == 48:
        return 0
    elif escaped == 34:
        return 34
    elif escaped == 39:
        return 39
    elif escaped == 92:
        return 92
    end
    call diagnostics.fail(path, line, column, 2, source_line(lines, line), "E0003", "unknown escape sequence", "supported escapes: n, r, t, 0, quote, backslash")
    return 0
end

# The String spelled by the source bytes start..stop. The caller's scratch
# buffer is reused for every token instead of allocating one per token.
function text_slice(text, start, stop, buffer):
    call buffer.clear()
    index = start
    while index < stop:
        call buffer.append(__lsl_text_byte(text, index))
        index += 1
    end
    return __lsl_text_from_bytes(buffer, 0, len(buffer))
end

function tokenize(path, source):
    text = String(source)
    count = __lsl_text_byte_length(text)
    if count > 4194304:
        Error(CompileError: "source exceeds the 4 MiB compiler limit: " + path)
    end
    result = []
    scratch = ByteArray()
    # Diagnostics materialize lines only on failure.
    lines = source
    newline = chr(10)
    index = 0
    line = 1
    column = 1
    depth = 0
    while index < count:
        code = __lsl_text_byte(text, index)
        if code == 10:
            if depth == 0:
                result.append(token("newline", newline, line, column, column + 1))
            end
            index += 1
            line += 1
            column = 1
        elif code == 32 or code == 9 or code == 13:
            index += 1
            column += 1
        elif code == 35:
            while index < count and __lsl_text_byte(text, index) != 10:
                index += char_width(__lsl_text_byte(text, index))
                column += 1
            end
        elif code == 34 or code == 39 or (code == 108 and index + 1 < count and (__lsl_text_byte(text, index + 1) == 34 or __lsl_text_byte(text, index + 1) == 39)):
            lux_string = code == 108
            start_line = line
            start_column = column
            value_bytes = scratch
            call value_bytes.clear()
            value_length = 0
            if lux_string:
                index += 1
                column += 1
                code = __lsl_text_byte(text, index)
            end
            quote = code
            index += 1
            column += 1
            closed = False
            # Inside a Lux String interpolation `{...}` the quote that opened
            # the literal does not end it: braces nest and inner String
            # literals (either quote) are skipped, so l"{"a" * n}" is one
            # token. The parser later splits the value on the same rules.
            brace_depth = 0
            inner_quote = 0
            while index < count:
                code = __lsl_text_byte(text, index)
                if code == 92:
                    if index + 1 >= count:
                        call diagnostics.fail(path, line, column, 1, source_line(lines, line), "E0002", "unfinished escape sequence", "add a character after the backslash")
                    end
                    decoded = decode_escape(path, lines, line, column, __lsl_text_byte(text, index + 1))
                    call value_bytes.append(decoded)
                    if brace_depth > 0 and (decoded == 34 or decoded == 39):
                        if inner_quote == decoded:
                            inner_quote = 0
                        elif inner_quote == 0:
                            inner_quote = decoded
                        end
                    end
                    value_length += 1
                    index += 2
                    column += 2
                elif brace_depth > 0 and code != 10:
                    if inner_quote != 0:
                        if code == inner_quote:
                            inner_quote = 0
                        end
                    elif code == 34 or code == 39:
                        inner_quote = code
                    elif code == 123:
                        brace_depth += 1
                    elif code == 125:
                        brace_depth -= 1
                    end
                    width = char_width(code)
                    stop = index + width
                    while index < stop:
                        call value_bytes.append(__lsl_text_byte(text, index))
                        index += 1
                    end
                    value_length += 1
                    column += 1
                elif code == quote:
                    index += 1
                    column += 1
                    closed = True
                    break
                elif lux_string and code == 123:
                    call value_bytes.append(123)
                    value_length += 1
                    index += 1
                    column += 1
                    if index < count and __lsl_text_byte(text, index) == 123:
                        call value_bytes.append(123)
                        value_length += 1
                        index += 1
                        column += 1
                    else:
                        brace_depth = 1
                        inner_quote = 0
                    end
                elif code == 10:
                    call diagnostics.fail(path, start_line, start_column, max(1, column - start_column), source_line(lines, start_line), "E0001", "unterminated String literal", "close the String before the end of the line")
                else:
                    width = char_width(code)
                    stop = index + width
                    while index < stop:
                        call value_bytes.append(__lsl_text_byte(text, index))
                        index += 1
                    end
                    value_length += 1
                    column += 1
                end
                if value_length > 1048576:
                    call diagnostics.fail(path, start_line, start_column, max(1, column - start_column), source_line(lines, start_line), "E0010", "String literal exceeds 1 MiB", "load large data from a file at runtime")
                end
            end
            if not closed:
                call diagnostics.fail(path, start_line, start_column, max(1, column - start_column), source_line(lines, start_line), "E0001", "unterminated String literal", "add the matching quote")
            end
            value = __lsl_text_from_bytes(value_bytes, 0, len(value_bytes))
            kind = "string"
            if lux_string:
                kind = "lux_string"
            end
            result.append(token(kind, value, start_line, start_column, column))
        elif code == 48 and index + 1 < count and (__lsl_text_byte(text, index + 1) == 120 or __lsl_text_byte(text, index + 1) == 88 or __lsl_text_byte(text, index + 1) == 98 or __lsl_text_byte(text, index + 1) == 66 or __lsl_text_byte(text, index + 1) == 111 or __lsl_text_byte(text, index + 1) == 79):
            start_column = column
            marker = __lsl_text_byte(text, index + 1)
            base = 16
            if marker == 98 or marker == 66:
                base = 2
            elif marker == 111 or marker == 79:
                base = 8
            end
            index += 2
            column += 2
            digits_start = index
            value = "0"
            digit_limit = 16
            if base == 2:
                digit_limit = 64
            elif base == 8:
                digit_limit = 22
            end
            while index < count and (is_alpha(__lsl_text_byte(text, index)) or is_digit(__lsl_text_byte(text, index))):
                if index - digits_start >= digit_limit:
                    call diagnostics.fail(path, line, start_column, max(1, column - start_column), source_line(lines, line), "E0011", "based numeric literal exceeds the Int64 width", "use at most " + String(digit_limit) + " digits for this base")
                end
                digit = digit_value(__lsl_text_byte(text, index))
                if digit < 0 or digit >= base:
                    call diagnostics.fail(path, line, column, 1, source_line(lines, line), "E0008", "digit is out of range for the literal base", "use only digits the 0b, 0o, or 0x prefix allows")
                end
                value = decimal_scale_add(value, base, digit)
                index += 1
                column += 1
            end
            if index == digits_start:
                call diagnostics.fail(path, line, start_column, max(1, column - start_column), source_line(lines, line), "E0009", "base prefix without digits", "add at least one digit after 0b, 0o, or 0x")
            end
            result.append(token("number", value, line, start_column, column))
        elif is_digit(code):
            start = index
            start_column = column
            dots = 0
            while index < count and (is_digit(__lsl_text_byte(text, index)) or __lsl_text_byte(text, index) == 46):
                if __lsl_text_byte(text, index) == 46:
                    dots += 1
                end
                index += 1
                column += 1
            end
            if index < count and (__lsl_text_byte(text, index) == 101 or __lsl_text_byte(text, index) == 69):
                index += 1
                column += 1
                if index < count and (__lsl_text_byte(text, index) == 43 or __lsl_text_byte(text, index) == 45):
                    index += 1
                    column += 1
                end
                exponent_start = index
                while index < count and is_digit(__lsl_text_byte(text, index)):
                    index += 1
                    column += 1
                end
                if index == exponent_start:
                    call diagnostics.fail(path, line, start_column, max(1, index - start), source_line(lines, line), "E0004", "invalid Float exponent", "add decimal digits after the exponent marker")
                end
            end
            value = text_slice(text, start, index, scratch)
            if len(value) > 4096:
                call diagnostics.fail(path, line, start_column, len(value), source_line(lines, line), "E0011", "numeric literal is too long", "use at most 4096 digits")
            end
            if dots > 1:
                call diagnostics.fail(path, line, start_column, len(value), source_line(lines, line), "E0004", "invalid numeric literal", "a Float may contain only one decimal point")
            end
            result.append(token("number", value, line, start_column, column))
        elif is_alpha(code):
            start = index
            start_column = column
            while index < count and (is_alpha(__lsl_text_byte(text, index)) or is_digit(__lsl_text_byte(text, index))):
                index += 1
                column += 1
                if index - start > 255:
                    call diagnostics.fail(path, line, start_column, max(1, column - start_column), source_line(lines, line), "E0013", "identifier exceeds 255 characters", "use a shorter identifier")
                end
            end
            result.append(token("name", text_slice(text, start, index, scratch), line, start_column, column))
        else:
            start_column = column
            width = char_width(code)
            value = text_slice(text, index, index + width, scratch)
            if width == 1 and index + 2 < count:
                triple = value + chr(__lsl_text_byte(text, index + 1)) + chr(__lsl_text_byte(text, index + 2))
                if triple == "<<=" or triple == ">>=":
                    value = triple
                end
            end
            if len(value) == 1 and width == 1 and index + 1 < count:
                pair = value + chr(__lsl_text_byte(text, index + 1))
                if pair == "==" or pair == "!=" or pair == "<=" or pair == ">=" or pair == "//" or pair == "+=" or pair == "-=" or pair == "*=" or pair == "/=" or pair == "%=" or pair == "<<" or pair == ">>" or pair == "&=" or pair == "|=" or pair == "~=" or pair == "++" or pair == "--":
                    value = pair
                end
            end
            if len(value) == 3:
                index += 3
                column += 3
            elif len(value) == 2:
                index += 2
                column += 2
            else:
                index += width
                column += 1
            end
            if value == "(" or value == "[" or value == "{":
                depth += 1
                if depth > 256:
                    call diagnostics.fail(path, line, start_column, len(value), source_line(lines, line), "E0012", "delimiter nesting exceeds 256 levels", "split the expression into smaller statements")
                end
            elif value == ")" or value == "]" or value == "}":
                depth -= 1
                if depth < 0:
                    call diagnostics.fail(path, line, start_column, len(value), source_line(lines, line), "E0005", "unexpected closing delimiter", "remove it or add the matching opening delimiter")
                end
            elif value != "+" and value != "-" and value != "*" and value != "/" and value != "%" and value != "^" and value != "=" and value != "<" and value != ">" and value != "!" and value != ":" and value != "," and value != "." and value != "&" and value != "|" and value != "~" and value != "==" and value != "!=" and value != "<=" and value != ">=" and value != "//" and value != "+=" and value != "-=" and value != "*=" and value != "/=" and value != "%=" and value != "<<" and value != ">>" and value != "&=" and value != "|=" and value != "~=" and value != "<<=" and value != ">>=" and value != "++" and value != "--":
                call diagnostics.fail(path, line, start_column, len(value), source_line(lines, line), "E0006", "unexpected character", "remove the character or put it inside a String")
            end
            result.append(token("symbol", value, line, start_column, column))
        end
        if len(result) > 500000:
            Error(CompileError: "source exceeds the 500000-token compiler limit: " + path)
        end
    end
    if depth != 0:
        last_line = line
        call diagnostics.fail(path, last_line, max(1, len(source_line(lines, last_line))), 1, source_line(lines, last_line), "E0007", "unclosed delimiter", "add the matching closing delimiter")
    end
    result.append(token("eof", "", line, column, column))
    return result
end
