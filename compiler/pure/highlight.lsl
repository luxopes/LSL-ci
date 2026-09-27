# Syntax colouring for LSL source shown in the terminal (interactive prompt,
# lsl --tui). A line is scanned into spans [text, style] with SGR codes; the
# scanner mirrors the lexer's token classes but never fails: unterminated
# Strings or comments simply colour the rest of the line.

KEYWORDS = ["function", "end", "if", "elif", "else", "while", "for", "in", "loop", "break", "continue", "return", "class", "ctype", "try", "safe", "unsafe", "load", "from", "as", "del", "call", "print", "printl", "input", "and", "or", "not", "Error", "self"]
CONSTANTS = ["True", "False", "None"]
BUILTINS = ["len", "type", "String", "Int", "Float", "Bool", "List", "Tuple", "Dictionary", "IntArray", "FloatArray", "ByteArray", "RealArray", "rang", "range", "abs", "sqrt", "sum", "min", "max", "sorted", "chr", "ord", "readfile", "writefile", "exists", "exit", "arg", "help", "gc", "monotonic", "clock", "run", "capture", "system"]

STYLE_KEYWORD = "1;35"
STYLE_CONSTANT = "35"
STYLE_BUILTIN = "36"
STYLE_STRING = "32"
STYLE_NUMBER = "33"
STYLE_COMMENT = "2"
STYLE_CALL = "1;34"
STYLE_OPERATOR = "37"

function is_alpha(code):
    return (code >= 97 and code <= 122) or (code >= 65 and code <= 90) or code == 95
end

function is_digit(code):
    return code >= 48 and code <= 57
end

function word_style(word, next_character):
    if word in KEYWORDS:
        return STYLE_KEYWORD
    elif word in CONSTANTS:
        return STYLE_CONSTANT
    elif word in BUILTINS:
        return STYLE_BUILTIN
    elif next_character == "(":
        return STYLE_CALL
    end
    return ""
end

# Scan one line into spans. Strings track the Lux String interpolation braces
# so `l"{"a" * n}"` stays one String span.
function spans(line):
    text = String(line)
    result = []
    index = 0
    count = len(text)
    while index < count:
        character = text[index]
        code = ord(character)
        if character == "#":
            result.append([text[index:count], STYLE_COMMENT])
            break
        elif character == "\"" or character == "'" or (character == "l" and index + 1 < count and (text[index + 1] == "\"" or text[index + 1] == "'")):
            start = index
            if character == "l":
                index += 1
            end
            quote = text[index]
            index += 1
            depth = 0
            inner = ""
            while index < count:
                current = text[index]
                if current == "\\":
                    index += 2
                    continue
                elif depth > 0:
                    if inner != "":
                        if current == inner:
                            inner = ""
                        end
                    elif current == "\"" or current == "'":
                        inner = current
                    elif current == "{":
                        depth += 1
                    elif current == "}":
                        depth -= 1
                    end
                elif current == quote:
                    index += 1
                    break
                elif character == "l" and current == "{":
                    if index + 1 < count and text[index + 1] == "{":
                        index += 1
                    else:
                        depth = 1
                    end
                end
                index += 1
            end
            result.append([text[start:min(index, count)], STYLE_STRING])
        elif is_digit(code):
            start = index
            while index < count and (is_alpha(ord(text[index])) or is_digit(ord(text[index])) or text[index] == "."):
                index += 1
            end
            result.append([text[start:index], STYLE_NUMBER])
        elif is_alpha(code):
            start = index
            while index < count and (is_alpha(ord(text[index])) or is_digit(ord(text[index]))):
                index += 1
            end
            word = text[start:index]
            following = ""
            if index < count:
                following = text[index]
            end
            result.append([word, word_style(word, following)])
        elif character == " " or character == "\t":
            start = index
            while index < count and (text[index] == " " or text[index] == "\t"):
                index += 1
            end
            result.append([text[start:index], ""])
        else:
            result.append([character, STYLE_OPERATOR])
            index += 1
        end
    end
    return result
end

# The line with ANSI colours (when enabled) ready for a terminal.
function render(line, colors):
    if not colors:
        return String(line)
    end
    parts = []
    for item in spans(line):
        if item[1] == "":
            parts.append(String(item[0]))
        else:
            parts.append(chr(27) + "[" + String(item[1]) + "m" + String(item[0]) + chr(27) + "[0m")
        end
    end
    return "".join(parts)
end
