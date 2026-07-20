# Structured source diagnostics for the direct LSL backend.

function repeat_text(value, count):
    result = ""
    for index in rang(count):
        result += value
    end
    return result
end

function fail(path, line_number, column, width, source_line, code, message, help_text):
    if column < 1:
        column = 1
    end
    if width < 1:
        width = 1
    end
    gutter = String(line_number)
    print "error[" + code + "]: " + message
    print " --> " + path + ":" + String(line_number) + ":" + String(column)
    print repeat_text(" ", len(gutter) + 1) + "|"
    print gutter + " | " + source_line
    print repeat_text(" ", len(gutter) + 1) + "| " + repeat_text(" ", column - 1) + "^" + repeat_text("~", width - 1)
    if help_text != "":
        print " help: " + help_text
    end
    exit(1)
end
