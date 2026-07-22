path = "/tmp/lsl-capture-large-input"
data = "x"
for index in rang(21):
    data += data
end
call writefile(path, data)
output = capture("/tmp/lsl-capture-large-server", [path])
call unlink(path)
print len(output), output[0], output[len(output) - 2], ord(output[len(output) - 1])
