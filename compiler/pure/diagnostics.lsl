# Structured source diagnostics for the direct LSL backend.
load console

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
