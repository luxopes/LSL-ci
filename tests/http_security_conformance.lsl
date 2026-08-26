load http
load json

transport = arg(1) + "/http-transport-server"
secret = "Bearer lsl-secret-067"
body = "quoted \"value\"" + chr(10) + "back\\slash"
result = http.post_with(transport, "https://api.example.test/v1", body, {"Authorization": secret, "X-LSL": "safe"}, 17)
request = json.decode(result["text"])
argv = chr(0).join(request["arguments"])
config = request["config"]
print result["status"], result["ok"]
print request["arguments"] == ["--config", "-"]
print secret not in argv, body not in argv
print "Authorization: " + secret in config
escaped_body = "data-raw = " + chr(34) + "quoted " + chr(92) + chr(34) + "value" + chr(92) + chr(34) + chr(92) + "nback" + chr(92) + chr(92) + "slash" + chr(34)
print escaped_body in config
print "url = \"https://api.example.test/v1\"" in config

chunks = []
function receive(chunk):
    chunks.append(chunk)
end
streamed = http.post_stream_with(transport, "https://api.example.test/stream", "payload", {}, 9, receive)
print streamed["status"], streamed["ok"], len(chunks) > 0

try:
    call http.get_with(transport, "http://example.test/plain")
else:
    print last_error()
end
try:
    call http.post_with(transport, "https://example.test", "x", {"Good\nInjected": "bad"}, 3)
else:
    print last_error()
end
try:
    call http.post_with(transport, "https://example.test", "x", {"Good": "bad\r\nInjected: yes"}, 3)
else:
    print last_error()
end

failed = http.get_with(arg(1) + "/missing-http-transport", "https://example.test")
print failed["status"], failed["ok"], len(failed["text"]) > 0
