chunks = []
function receive(chunk):
    chunks.append(chunk)
end
output = capture_stream(arg(1) + "/capture-stream-server", [], receive)
print output.replace(chr(10), "|")
print "".join(chunks) == output, len(chunks) > 0, capture_status(), capture_stderr() == ""
function reject(chunk):
    Error(StreamError: "callback rejected chunk")
end
caught = ""
try:
    call capture_stream(arg(1) + "/capture-stream-server", [], reject)
else:
    caught = last_error()
end
print caught
