chunks = []
function receive(chunk):
    chunks.append(chunk)
end
input_text = "abc" + chr(10) + "second" + chr(10)
expected = "3 a c second" + chr(10)
server = arg(1) + "/input-server"
print capture_input_clean(server, [], input_text) == expected, capture_status()
chunks.clear()
output = capture_input_stream(server, [], input_text, receive)
print output == expected, "".join(chunks) == output, capture_status()
chunks.clear()
output = capture_input_stream_clean(server, [], input_text, receive)
print output == expected, "".join(chunks) == output, capture_status()
chunks.clear()
output = capture_stream_clean(arg(1) + "/capture-stream-server", [], receive)
print output.replace(chr(10), "|"), "".join(chunks) == output, capture_status()
