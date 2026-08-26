load json

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
# curl's --write-out value follows the response body without a trailing LF.
call input("200")
