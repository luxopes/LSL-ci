load json
load fd

arguments = []
index = 1
while index < arg_count():
    arguments.append(arg(index))
    index += 1
end

lines = []
loop:
    line = input("")
    eof = __lsl_stdin_eof()
    if eof and line == "":
        break
    end
    lines.append(line)
    if eof:
        break
    end
end

config = ""
if len(lines) > 0:
    config = chr(10).join(lines) + chr(10)
end
print json.encode({"arguments": arguments, "config": config})
# Skutečný curl odděluje tělo na stdout a stavový kód na stderr.
# Varování na stderr nesmí klient připojit k tělu odpovědi.
status_text = "test warning" + chr(10) + "200"
status_bytes = ByteArray()
for character in status_text:
    status_bytes.append(ord(character))
end
call fd.write(2, status_bytes, len(status_bytes))
