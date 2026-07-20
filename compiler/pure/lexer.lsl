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

function source_line(lines, line_number):
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

function tokenize(path, source):
    result = []
    lines = source.split(chr(10))
    index = 0
    line = 1
    column = 1
    depth = 0
    while index < len(source):
        character = source[index]
        if character == chr(10):
            if depth == 0:
                result.append(token("newline", chr(10), line, column, column + 1))
            end
            index += 1
            line += 1
            column = 1
        elif is_space(character):
            index += 1
            column += 1
        elif character == "#":
            while index < len(source) and source[index] != chr(10):
                index += 1
                column += 1
            end
        elif character == "\"" or character == "'":
            quote = character
            start_line = line
            start_column = column
            value = ""
            index += 1
            column += 1
            closed = False
            while index < len(source):
                character = source[index]
                if character == quote:
                    index += 1
                    column += 1
                    closed = True
                    break
                elif character == "\\":
                    if index + 1 >= len(source):
                        call diagnostics.fail(path, line, column, 1, source_line(lines, line), "E0002", "unfinished escape sequence", "add a character after the backslash")
                    end
                    escaped = source[index + 1]
                    value += decode_escape(path, lines, line, column, escaped)
                    index += 2
                    column += 2
                elif character == chr(10):
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
            result.append(token("string", value, start_line, start_column, column))
        elif is_digit(character):
            start = index
            start_column = column
            dots = 0
            while index < len(source) and (is_digit(source[index]) or source[index] == "."):
                if source[index] == ".":
                    dots += 1
                end
                index += 1
                column += 1
            end
            if index < len(source) and (source[index] == "e" or source[index] == "E"):
                index += 1
                column += 1
                if index < len(source) and (source[index] == "+" or source[index] == "-"):
                    index += 1
                    column += 1
                end
                exponent_start = index
                while index < len(source) and is_digit(source[index]):
                    index += 1
                    column += 1
                end
                if index == exponent_start:
                    call diagnostics.fail(path, line, start_column, max(1, index - start), source_line(lines, line), "E0004", "invalid Float exponent", "add decimal digits after the exponent marker")
                end
            end
            value = source[start:index]
            if dots > 1:
                call diagnostics.fail(path, line, start_column, len(value), source_line(lines, line), "E0004", "invalid numeric literal", "a Float may contain only one decimal point")
            end
            result.append(token("number", value, line, start_column, column))
        elif is_alpha(character):
            start = index
            start_column = column
            while index < len(source) and (is_alpha(source[index]) or is_digit(source[index])):
                index += 1
                column += 1
            end
            result.append(token("name", source[start:index], line, start_column, column))
        else:
            start_column = column
            value = character
            if index + 1 < len(source):
                pair = character + source[index + 1]
                if pair == "==" or pair == "!=" or pair == "<=" or pair == ">=" or pair == "//" or pair == "**" or pair == "+=" or pair == "-=" or pair == "*=" or pair == "/=" or pair == "%=":
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
            elif value != "+" and value != "-" and value != "*" and value != "/" and value != "%" and value != "=" and value != "<" and value != ">" and value != "!" and value != ":" and value != "," and value != "." and value != "==" and value != "!=" and value != "<=" and value != ">=" and value != "//" and value != "**" and value != "+=" and value != "-=" and value != "*=" and value != "/=" and value != "%=":
                call diagnostics.fail(path, line, start_column, len(value), source_line(lines, line), "E0006", "unexpected character", "remove the character or put it inside a String")
            end
            result.append(token("symbol", value, line, start_column, column))
        end
    end
    if depth != 0:
        last_line = len(lines)
        call diagnostics.fail(path, last_line, max(1, len(source_line(lines, last_line))), 1, source_line(lines, last_line), "E0007", "unclosed delimiter", "add the matching closing delimiter")
    end
    result.append(token("eof", "", line, column, column))
    return result
end
