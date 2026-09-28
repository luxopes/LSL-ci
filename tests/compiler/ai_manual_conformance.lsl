# Každý LSL blok aktuální kapitoly musí projít skutečným parserem.
load parser

source = readfile("docs/developer_guides/10-ai-applications.md")
inside = False
snippet = ""
count = 0
for line in source.split(chr(10)):
    if line == "```lsl":
        inside = True
        snippet = ""
    elif inside and line == "```":
        count += 1
        program = parser.parse("ai-manual-example-" + String(count) + ".lsl", snippet)
        check(len(program) > 0, "empty AI manual example")
        inside = False
    elif inside:
        snippet += line + chr(10)
    end
end
check(not inside and count >= 15, "AI manual examples are missing or unclosed")
print "AI manual LSL examples parse successfully"
