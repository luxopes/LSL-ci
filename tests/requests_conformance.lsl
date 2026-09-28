# Skutečný lokální server ověřuje metody, těla, hlavičky a streamování.

load httpserver
load requests
load json
load fd

function require(condition, message):
    if not condition:
        Error(TestFailure: message)
    end
end

listener_box = IntArray()
listener_box.append(httpserver.listen_ipv4("127.0.0.1", 0, 16))
port_box = IntArray()
port_box.append(httpserver.local_port(listener_box[0]))

function handler(request):
    if request["target"] == "/json":
        return {"body": "{\"method\": \"" + request["method"] + "\"}", "content_type": "application/json"}
    elif request["target"] == "/echo":
        return {"body": String(request["method"]) + ":" + String(request["body_text"]) + chr(10)}
    elif request["target"] == "/status":
        return {"status": 418, "body": "teapot"}
    elif request["target"] == "/headers":
        return {"body": json.encode(request["headers"]), "content_type": "application/json"}
    end
    return {"status": 404, "body": "missing"}
end

function server_worker():
    call httpserver.serve_listener(listener_box[0], -1, handler, 16, False)
    return None
end

worker = thread_spawn(server_worker)
base = "http://127.0.0.1:" + String(port_box[0])

first = requests.get(base + "/json")
call require(first.status == 200 and first.status_code == 200 and first.ok, "GET status")
print first.status, first.ok, first.json()["method"]

echo = requests.post(base + "/echo", {"a": 1}, {"X-Test": "yes"}, 30)
call require(echo.text == "POST:{\"a\":1}" + chr(10), "POST JSON body")
print echo.text.strip()

removed = requests.delete(base + "/echo", "payload", {}, 30)
call require(removed.text == "DELETE:payload" + chr(10), "DELETE body")
print removed.text.strip()

placed = requests.put(base + "/json", None, {}, 30)
call require(placed.json()["method"] == "PUT", "PUT method")
print placed.json()["method"]

patched = requests.request("PATCH", base + "/echo", "p", {}, 30)
call require(patched.text == "PATCH:p" + chr(10), "PATCH method")
print patched.text.strip()

headed = requests.head(base + "/json", {}, 30)
call require(headed.status == 200 and headed.ok and headed.text == "", "HEAD status and empty body")
print headed.status, len(headed.text)

chunks = []
function receive(chunk):
    chunks.append(chunk)
end
streamed = requests.post_stream(base + "/echo", "stream-body", {}, 30, receive)
call require(streamed.text == "POST:stream-body" + chr(10), "streamed response")
print streamed.status, streamed.text.strip(), "".join(chunks) == streamed.text

teapot = requests.get(base + "/status", {}, 30)
caught = ""
try:
    call teapot.raise_for_status()
else:
    caught = last_error()
end
call require(caught == "HTTPStatusError: HTTP 418: teapot", "raise_for_status message")
print caught

missing = requests.get(base + "/missing", {}, 30)
call require(missing.status == 404 and not missing.ok, "404 status")
caught = ""
try:
    call missing.json()
else:
    caught = last_error()
end
call require(caught == "JsonError: invalid value", "non-JSON body message")
print caught

empty = requests.Response(200, "")
caught = ""
try:
    call empty.json()
else:
    caught = last_error()
end
print caught

direct = requests.Response(200, "{\"x\":1}")
print direct.status, direct.ok, direct.json()["x"]

failed = requests.Response(0, "curl failed")
caught = ""
try:
    call failed.raise_for_status()
else:
    caught = last_error()
end
print caught

caught = ""
try:
    requests.get(base + "/json", {"Bad Header": "x"}, 30)
else:
    caught = last_error()
end
print caught

lowercase = requests.request("get", base + "/json")
call require(lowercase.json()["method"] == "GET", "lowercase request method")
patch_result = requests.patch(base + "/json", "payload")
call require(patch_result.json()["method"] == "PATCH", "patch convenience method")
options_result = requests.request("OPTIONS", base + "/json")
call require(options_result.json()["method"] == "OPTIONS", "generic request method")
headers_result = requests.get(base + "/headers", headers={"X-Test": "custom"}, timeout=5)
call require(headers_result.json()["x-test"] == "custom", "GET custom headers and named arguments")
json_headers = requests.post(base + "/headers", {"key": "value"})
call require(json_headers.json()["content-type"] == "application/json", "automatic JSON content type")
original_headers = {"content-type": "application/custom", "X-Test": "unchanged"}
custom_headers = requests.post(base + "/headers", [1, 2], original_headers)
call require(custom_headers.json()["content-type"] == "application/custom" and len(original_headers) == 2, "explicit headers preserved without mutation")
unicode_result = requests.post(base + "/echo", "žlutý" + chr(10) + chr(10))
call require(unicode_result.text == "POST:žlutý" + chr(10) * 3, "Unicode and trailing response newlines")

for invalid_method in ["", "GET" + chr(10) + "Injected", "bad method", "X" * 33]:
    caught = ""
    try:
        call requests.request(invalid_method, base + "/json")
    else:
        caught = last_error()
    end
    call require(caught.startswith("HTTPError:"), "invalid method rejected before transport")
end
for timeout in [0, -1, 3601]:
    caught = ""
    try:
        call requests.get(base + "/json", timeout=timeout)
    else:
        caught = last_error()
    end
    call require(caught == "HTTPError: HTTP timeout must be between 1 and 3600 seconds", "invalid timeout rejected")
end
for headers in [{"X-Test": "x" + chr(13) + chr(10) + "Injected: yes"}, [], {"Bad Header": "x"}]:
    caught = ""
    try:
        call requests.get(base + "/json", headers=headers)
    else:
        caught = last_error()
    end
    call require(caught.startswith("HTTPError:"), "invalid headers rejected")
end
call require(thread_join(worker) == 0, "requests server worker did not exit cleanly")
closed_listener = httpserver.listen_ipv4("127.0.0.1", 0, 1)
closed_port = httpserver.local_port(closed_listener)
call fd.close(closed_listener)
connection_failure = requests.get("http://127.0.0.1:" + String(closed_port), timeout=1)
call require(connection_failure.status == 0 and not connection_failure.ok, "real connection failure")
caught = ""
try:
    call connection_failure.raise_for_status()
else:
    caught = last_error()
end
call require(caught.startswith("ConnectionError:"), "real transport failure exception")
print "requests conformance passed"
