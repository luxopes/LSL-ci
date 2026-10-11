# Structured source diagnostics for the direct LSL backend.
load console

function repeat_text(value, count):
    result = ""
    for index in rang(count):
        result += value
    end
    return result
end

# Varování jde na stderr, aby se nemíchalo s výstupem spuštěného programu.
function warn(path, line_number, column, width, source_line, code, message, help_text):
    if column < 1:
        column = 1
    end
    if width < 1:
        width = 1
    end
    colored = console.colors_fd(2)
    gutter = String(line_number)
    escape = chr(27) + "["
    lines = [["warning[" + code + "]: " + console.clean(message), "1;33"], [" --> " + console.clean(path) + ":" + String(line_number) + ":" + String(column), "1;34"], [repeat_text(" ", len(gutter) + 1) + "|", "34"], [gutter + " | " + console.clean(source_line), ""], [repeat_text(" ", len(gutter) + 1) + "| " + repeat_text(" ", column - 1) + "^" + repeat_text("~", width - 1), "1;33"]]
    if help_text != "":
        lines.append([" help: " + console.clean(help_text), "36"])
    end
    text = ""
    for entry in lines:
        if colored and entry[1] != "":
            text += escape + entry[1] + "m" + entry[0] + escape + "0m" + chr(10)
        else:
            text += entry[0] + chr(10)
        end
    end
    bytes = __lsl_byte_zeros(__lsl_text_byte_length(text))
    for index in rang(len(bytes)):
        bytes[index] = __lsl_text_byte(text, index)
    end
    call __lsl_fd_write(2, bytes, len(bytes))
end

function fail(path, line_number, column, width, source_line, code, message, help_text):
    if column < 1:
        column = 1
    end
    if width < 1:
        width = 1
    end
    gutter = String(line_number)
    print console.style("error[" + code + "]: " + console.clean(message), "1;31")
    print console.style(" --> " + console.clean(path) + ":" + String(line_number) + ":" + String(column), "1;34")
    print console.style(repeat_text(" ", len(gutter) + 1) + "|", "34")
    print console.style(gutter + " | ", "34") + console.clean(source_line)
    print console.style(repeat_text(" ", len(gutter) + 1) + "| ", "34") + repeat_text(" ", column - 1) + console.style("^" + repeat_text("~", width - 1), "1;31")
    if help_text != "":
        print console.style(" help: " + console.clean(help_text), "36")
    end
    exit(1)
end
