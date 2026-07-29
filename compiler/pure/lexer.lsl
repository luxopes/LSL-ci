# Full token-span lexer for the direct compiler.

load diagnostics

function is_space(character):
    return character == " " or character == "\t" or character == "\r"
end

function is_digit(character):
    code = ord(character)
    return code >= 48 and code <= 57
end

function is_alpha(character):
    code = ord(character)
    return (code >= 97 and code <= 122) or (code >= 65 and code <= 90) or code == 95
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

function decode_escape(path, lines, line, column, escaped):
    if escaped == "n":
        return chr(10)
    elif escaped == "r":
        return chr(13)
    elif escaped == "t":
        return chr(9)
    elif escaped == "0":
        return chr(0)
    elif escaped == "\"":
        return "\""
    elif escaped == "'":
        return "'"
    elif escaped == "\\":
        return "\\"
    end
    call diagnostics.fail(path, line, column, 2, source_line(lines, line), "E0003", "unknown escape sequence", "supported escapes: n, r, t, 0, quote, backslash")
    return ""
end

function join_chars(chars, start, stop):
    result = ""
    index = start
    while index < stop:
        result += chars[index]
        index += 1
    end
    return result
end

function tokenize(path, source):
    result = []
    chars = __lsl_string_chars(source)
    count = len(chars)
    # Diagnostics materialize lines only on failure.
    lines = source
    newline = chr(10)
    index = 0
    line = 1
    column = 1
    depth = 0
    while index < count:
        character = chars[index]
        if character == newline:
            if depth == 0:
                result.append(token("newline", newline, line, column, column + 1))
            end
            index += 1
            line += 1
            column = 1
        elif is_space(character):
            index += 1
            column += 1
        elif character == "#":
            while index < count and chars[index] != newline:
                index += 1
                column += 1
            end
        elif character == "\"" or character == "'" or (character == "l" and index + 1 < count and (chars[index + 1] == "\"" or chars[index + 1] == "'")):
            lux_string = character == "l"
            start_line = line
            start_column = column
            value = ""
            if lux_string:
                index += 1
                column += 1
                character = chars[index]
            end
            quote = character
            index += 1
            column += 1
            closed = False
            while index < count:
                character = chars[index]
                if character == quote:
                    index += 1
                    column += 1
                    closed = True
                    break
                elif character == "\\":
                    if index + 1 >= count:
                        call diagnostics.fail(path, line, column, 1, source_line(lines, line), "E0002", "unfinished escape sequence", "add a character after the backslash")
                    end
                    escaped = chars[index + 1]
                    value += decode_escape(path, lines, line, column, escaped)
                    index += 2
                    column += 2
                elif character == newline:
                    call diagnostics.fail(path, start_line, start_column, max(1, column - start_column), source_line(lines, start_line), "E0001", "unterminated String literal", "close the String before the end of the line")
                else:
                    value += character
                    index += 1
                    column += 1
                end
            end
            if not closed:
                call diagnostics.fail(path, start_line, start_column, max(1, column - start_column), source_line(lines, start_line), "E0001", "unterminated String literal", "add the matching quote")
            end
            kind = "string"
            if lux_string:
                kind = "lux_string"
            end
            result.append(token(kind, value, start_line, start_column, column))
        elif is_digit(character):
            start = index
            start_column = column
            dots = 0
            while index < count and (is_digit(chars[index]) or chars[index] == "."):
                if chars[index] == ".":
                    dots += 1
                end
                index += 1
                column += 1
            end
            if index < count and (chars[index] == "e" or chars[index] == "E"):
                index += 1
                column += 1
                if index < count and (chars[index] == "+" or chars[index] == "-"):
                    index += 1
                    column += 1
                end
                exponent_start = index
                while index < count and is_digit(chars[index]):
                    index += 1
                    column += 1
                end
                if index == exponent_start:
                    call diagnostics.fail(path, line, start_column, max(1, index - start), source_line(lines, line), "E0004", "invalid Float exponent", "add decimal digits after the exponent marker")
                end
            end
            value = join_chars(chars, start, index)
            if dots > 1:
                call diagnostics.fail(path, line, start_column, len(value), source_line(lines, line), "E0004", "invalid numeric literal", "a Float may contain only one decimal point")
            end
            result.append(token("number", value, line, start_column, column))
        elif is_alpha(character):
            start = index
            start_column = column
            while index < count and (is_alpha(chars[index]) or is_digit(chars[index])):
                index += 1
                column += 1
            end
            result.append(token("name", join_chars(chars, start, index), line, start_column, column))
        else:
            start_column = column
            value = character
            if index + 1 < count:
                pair = character + chars[index + 1]
                if pair == "==" or pair == "!=" or pair == "<=" or pair == ">=" or pair == "//" or pair == "+=" or pair == "-=" or pair == "*=" or pair == "/=" or pair == "%=":
                    value = pair
                end
            end
            if len(value) == 2:
                index += 2
                column += 2
            else:
                index += 1
                column += 1
            end
            if value == "(" or value == "[" or value == "{":
                depth += 1
            elif value == ")" or value == "]" or value == "}":
                depth -= 1
                if depth < 0:
                    call diagnostics.fail(path, line, start_column, len(value), source_line(lines, line), "E0005", "unexpected closing delimiter", "remove it or add the matching opening delimiter")
                end
            elif value != "+" and value != "-" and value != "*" and value != "/" and value != "%" and value != "^" and value != "=" and value != "<" and value != ">" and value != "!" and value != ":" and value != "," and value != "." and value != "==" and value != "!=" and value != "<=" and value != ">=" and value != "//" and value != "+=" and value != "-=" and value != "*=" and value != "/=" and value != "%=":
                call diagnostics.fail(path, line, start_column, len(value), source_line(lines, line), "E0006", "unexpected character", "remove the character or put it inside a String")
            end
            result.append(token("symbol", value, line, start_column, column))
        end
    end
    if depth != 0:
        last_line = line
        call diagnostics.fail(path, last_line, max(1, len(source_line(lines, last_line))), 1, source_line(lines, last_line), "E0007", "unclosed delimiter", "add the matching closing delimiter")
    end
    result.append(token("eof", "", line, column, column))
    return result
end
