load _platform as platform
load fd
load httpserver
load time

# Child mode: `<binary> <root> memory-server` serves MEMORY_REQUESTS requests
# of a garbage-allocating handler on its own MAIN thread (no workers), which
# is the topology the per-request gc() protects, then verifies its own RSS.
MEMORY_REQUESTS = 1200

listener_box = IntArray()
root_box = IntArray()
port_box = IntArray()

function server_worker():
    call httpserver.serve_listener(listener_box[0], root_box[0], None, 11, False)
    return None
end

handler_calls = IntArray()
handler_calls.append(0)

function recovering_handler(request):
    handler_calls[0] += 1
    if handler_calls[0] == 1:
        Error(TestHandlerError: "expected request-local failure")
    end
    return {"body": "recovered" + chr(10)}
end

function app_server_worker():
    call httpserver.serve_listener(listener_box[0], -1, recovering_handler, 2, False)
    return None
end

function echo_handler(request):
    text = request["body_text"]
    if text == None:
        return {"body": "binary:" + String(len(request["body"])) + chr(10)}
    end
    return {"body": String(request["method"]) + ":" + text + chr(10)}
end

function echo_server_worker():
    call httpserver.serve_listener(listener_box[0], -1, echo_handler, 6, False)
    return None
end

function roundtrip_handler(request):
    return {"body": request["body"], "content_type": "application/octet-stream"}
end

# Allocates a few hundred KB of garbage per request, like a dashboard page
# render. Regression for the allocator exhaustion of a long-running
# main-thread listener: serve_listener now reclaims per request.
function garbage_handler(request):
    rows = []
    row = 0
    while row < 900:
        rows.append("<tr><td>row-" + String(row) + "</td><td>payload-payload-payload-payload</td><td>" + String(request["target"]) + "</td></tr>")
        row += 1
    end
    return {"body": "<table>" + "".join(rows) + "</table>", "content_type": "text/html; charset=utf-8"}
end

function own_rss_kb():
    rss_line = ""
    for status_line in fd.read_text("/proc/self/status").split(chr(10)):
        if status_line.startswith("VmRSS"):
            rss_line = status_line
        end
    end
    value = 0
    for token in rss_line.split(" "):
        if len(token) > 0 and ord(token[0]) >= 48 and ord(token[0]) <= 57:
            value = Int(token)
        end
    end
    return value
end

function memory_server_child(root):
    listener = httpserver.listen_ipv4("127.0.0.1", 0, 16)
    call writefile(root + "/memory-port.txt", String(httpserver.local_port(listener)))
    call httpserver.serve_listener(listener, -1, garbage_handler, MEMORY_REQUESTS, False)
    rss_kb = own_rss_kb()
    if rss_kb <= 0:
        print "memory server cannot read VmRSS"
        exit(2)
    end
    if rss_kb >= 150000:
        print "memory server leaked: VmRSS " + String(rss_kb) + " kB"
        exit(3)
    end
    exit(0)
end

memory_child_status = IntArray()
memory_child_status.append(-1)

function memory_child_worker():
    status = run(executable_path(), [String(arg(1)), "memory-server"])
    memory_child_status[0] = status
    return None
end

# 0.9.1: sloučené opakované hlavičky a streamované odpovědi.
function header_handler(request):
    headers = request["headers"]
    return {"body": "via=" + headers.get("via", "-") + "|xff=" + headers.get("x-forwarded-for", "-") + "|cookie=" + headers.get("cookie", "-") + chr(10)}
end

function header_server_worker():
    call httpserver.serve_listener(listener_box[0], -1, header_handler, 5, False)
    return None
end

function stream_events(stream):
    call httpserver.sse_event(stream, "first")
    call httpserver.sse_event(stream, "two" + chr(10) + "lines", "update")
    call httpserver.stream_write(stream, "")
    call httpserver.stream_write(stream, httpserver.text_bytes(": raw" + chr(10) + chr(10)))
end

function stream_broken(stream):
    call httpserver.stream_write(stream, "partial")
    Error(TestStreamError: "producer failed mid-stream")
end

function stream_handler(request):
    if request["target"] == "/broken":
        return {"content_type": "text/event-stream", "stream": stream_broken}
    elif request["target"] == "/invalid":
        return {"stream": "not a function"}
    end
    return {"content_type": "text/event-stream", "stream": stream_events}
end

function stream_server_worker():
    call httpserver.serve_listener(listener_box[0], -1, stream_handler, 5, False)
    return None
end

# 0.9.2: tchar v názvu hlavičky, CR v hodnotě, request-line a statusy bez těla.
function protocol_handler(request):
    if request["target"] == "/204":
        return {"status": 204, "body": "BADBODY"}
    elif request["target"] == "/304":
        return {"status": 304, "body": "BADBODY"}
    end
    return {"body": "dot=" + request["headers"].get("x.test", "-") + chr(10)}
end

function protocol_server_worker():
    call httpserver.serve_listener(listener_box[0], -1, protocol_handler, 7, False)
    return None
end

pool_active = IntArray()
pool_active.append(0)
pool_active.append(0)

function pool_handler(request):
    now = atomic_add(pool_active, 0, 1) + 1
    peak = pool_active[1]
    while now > peak:
        call atomic_cas(pool_active, 1, peak, now)
        peak = pool_active[1]
    end
    call time.sleep(0.2)
    call atomic_add(pool_active, 0, -1)
    return {"body": "pool " + request["target"] + chr(10)}
end

pool_served = IntArray()
pool_served.append(-1)

function pool_server_worker():
    pool_served[0] = httpserver.serve_listener_workers(listener_box[0], pool_handler, 4, 4)
    return None
end

pool_results = ["", "", "", ""]

function pool_client_0():
    pool_results[0] = exchange("GET /a HTTP/1.1" + chr(13) + chr(10) + "Host: localhost" + chr(13) + chr(10) + chr(13) + chr(10))
    return None
end

function pool_client_1():
    pool_results[1] = exchange("GET /b HTTP/1.1" + chr(13) + chr(10) + "Host: localhost" + chr(13) + chr(10) + chr(13) + chr(10))
    return None
end

function pool_client_2():
    pool_results[2] = exchange("GET /c HTTP/1.1" + chr(13) + chr(10) + "Host: localhost" + chr(13) + chr(10) + chr(13) + chr(10))
    return None
end

function pool_client_3():
    pool_results[3] = exchange("GET /d HTTP/1.1" + chr(13) + chr(10) + "Host: localhost" + chr(13) + chr(10) + chr(13) + chr(10))
    return None
end

function roundtrip_server_worker():
    call httpserver.serve_listener(listener_box[0], -1, roundtrip_handler, 3, False)
    return None
end

function exchange_raw(payload, read_limit):
    client = __lsl_fd_socket(httpserver.AF_INET, httpserver.SOCK_STREAM)
    if client < 0:
        Error(TestFailure: "HTTP client socket failed")
    end
    endpoint = httpserver.sockaddr_ipv4("127.0.0.1", port_box[0])
    if __lsl_fd_connect(client, endpoint, len(endpoint)) < 0:
        call fd.close(client)
        Error(TestFailure: "HTTP client connect failed")
    end
    call httpserver.set_socket_timeout(client, httpserver.SO_RCVTIMEO, 30)
    call httpserver.set_socket_timeout(client, httpserver.SO_SNDTIMEO, 30)
    # __lsl_fd_write completes the whole buffer internally and returns a
    # status: 0 on success, negative errno on failure.
    if __lsl_fd_write(client, payload, len(payload)) < 0:
        call fd.close(client)
        Error(TestFailure: "HTTP request write failed")
    end
    received = httpserver.read_handle_limit(client, read_limit)
    call fd.close(client)
    if not received["ok"]:
        Error(TestFailure: "HTTP response read failed")
    end
    return received["data"]
end

function reset_before_response(request):
    client = __lsl_fd_socket(httpserver.AF_INET, httpserver.SOCK_STREAM)
    if client < 0:
        Error(TestFailure: "HTTP reset client socket failed")
    end
    endpoint = httpserver.sockaddr_ipv4("127.0.0.1", port_box[0])
    if __lsl_fd_connect(client, endpoint, len(endpoint)) < 0:
        call fd.close(client)
        Error(TestFailure: "HTTP reset client connect failed")
    end
    linger = __lsl_byte_zeros(8)
    call httpserver.put_u32(linger, 0, 1)
    if __lsl_syscall6(httpserver.SYS_SETSOCKOPT, client, httpserver.SOL_SOCKET, httpserver.SO_LINGER, httpserver.data_address(linger), len(linger), 0) < 0:
        call fd.close(client)
        Error(TestFailure: "HTTP reset client SO_LINGER failed")
    end
    payload = httpserver.text_bytes(request)
    if __lsl_fd_write(client, payload, len(payload)) < 0:
        call fd.close(client)
        Error(TestFailure: "HTTP reset request write failed")
    end
    call fd.close(client)
end

function require(value, message):
    if not value:
        Error(TestFailure: message)
    end
end

function exchange(request):
    client = __lsl_fd_socket(httpserver.AF_INET, httpserver.SOCK_STREAM)
    if client < 0:
        Error(TestFailure: "HTTP client socket failed")
    end
    endpoint = httpserver.sockaddr_ipv4("127.0.0.1", port_box[0])
    if __lsl_fd_connect(client, endpoint, len(endpoint)) < 0:
        call fd.close(client)
        Error(TestFailure: "HTTP client connect failed")
    end
    call httpserver.set_socket_timeout(client, httpserver.SO_RCVTIMEO, 5)
    call httpserver.set_socket_timeout(client, httpserver.SO_SNDTIMEO, 5)
    payload = httpserver.text_bytes(request)
    written = __lsl_fd_write(client, payload, len(payload))
    if written < 0:
        call fd.close(client)
        Error(TestFailure: "HTTP request write failed")
    end
    received = httpserver.read_handle_limit(client, 65536)
    call fd.close(client)
    if not received["ok"]:
        Error(TestFailure: "HTTP response read failed")
    end
    data = received["data"]
    return __lsl_text_from_bytes(data, 0, len(data))
end

function exchange_bytes(payload):
    client = __lsl_fd_socket(httpserver.AF_INET, httpserver.SOCK_STREAM)
    if client < 0:
        Error(TestFailure: "HTTP client socket failed")
    end
    endpoint = httpserver.sockaddr_ipv4("127.0.0.1", port_box[0])
    if __lsl_fd_connect(client, endpoint, len(endpoint)) < 0:
        call fd.close(client)
        Error(TestFailure: "HTTP client connect failed")
    end
    call httpserver.set_socket_timeout(client, httpserver.SO_RCVTIMEO, 5)
    call httpserver.set_socket_timeout(client, httpserver.SO_SNDTIMEO, 5)
    written = __lsl_fd_write(client, payload, len(payload))
    if written < 0:
        call fd.close(client)
        Error(TestFailure: "HTTP request write failed")
    end
    received = httpserver.read_handle_limit(client, 65536)
    call fd.close(client)
    if not received["ok"]:
        Error(TestFailure: "HTTP response read failed")
    end
    data = received["data"]
    return __lsl_text_from_bytes(data, 0, len(data))
end

function exchange_half_close(request):
    client = __lsl_fd_socket(httpserver.AF_INET, httpserver.SOCK_STREAM)
    if client < 0:
        Error(TestFailure: "HTTP client socket failed")
    end
    endpoint = httpserver.sockaddr_ipv4("127.0.0.1", port_box[0])
    if __lsl_fd_connect(client, endpoint, len(endpoint)) < 0:
        call fd.close(client)
        Error(TestFailure: "HTTP client connect failed")
    end
    call httpserver.set_socket_timeout(client, httpserver.SO_RCVTIMEO, 5)
    call httpserver.set_socket_timeout(client, httpserver.SO_SNDTIMEO, 5)
    payload = httpserver.text_bytes(request)
    if __lsl_fd_write(client, payload, len(payload)) < 0:
        call fd.close(client)
        Error(TestFailure: "HTTP request write failed")
    end
    if __lsl_syscall(platform.SYS_SHUTDOWN, client, 1, 0, 0) < 0:
        call fd.close(client)
        Error(TestFailure: "HTTP client shutdown failed")
    end
    received = httpserver.read_handle_limit(client, 65536)
    call fd.close(client)
    if not received["ok"]:
        Error(TestFailure: "HTTP response read failed")
    end
    data = received["data"]
    return __lsl_text_from_bytes(data, 0, len(data))
end

if arg_count() >= 3 and arg(2) == "memory-server":
    call memory_server_child(String(arg(1)))
end

escape_path = String(arg(1)) + "/escape"
call unlink(escape_path)
fifo_path = String(arg(1)) + "/blocked.pipe"
call unlink(fifo_path)
if run_clean("/usr/bin/mkfifo", [fifo_path]) != 0:
    Error(TestFailure: "cannot create HTTP FIFO fixture")
end
escape_target = httpserver.cstring("/etc/passwd")
escape_name = httpserver.cstring(escape_path)
if __lsl_syscall(platform.SYS_SYMLINKAT, httpserver.data_address(escape_target), platform.AT_FDCWD, httpserver.data_address(escape_name), 0) < 0:
    Error(TestFailure: "cannot create HTTP symlink fixture")
end

listener = httpserver.listen_ipv4("127.0.0.1", 0, 16)
root = httpserver.open_root(arg(1))
listener_box.append(listener)
root_box.append(root)
port_box.append(httpserver.local_port(listener))
worker = thread_spawn(server_worker)

separator = chr(13) + chr(10)
call reset_before_response("GET /large.txt HTTP/1.1" + separator + "Host: localhost" + separator + separator)
get_response = exchange("GET / HTTP/1.1" + separator + "Host: localhost" + separator + separator)
call require(get_response.startswith("HTTP/1.1 200 OK"), "GET status differs")
call require(get_response.endswith("hello-http" + chr(10)), "GET body differs")
call require("X-Content-Type-Options: nosniff" in get_response, "GET hardening header missing")

head_response = exchange("HEAD /index.html HTTP/1.1" + separator + "Host: localhost" + separator + separator)
call require(head_response.startswith("HTTP/1.1 200 OK"), "HEAD status differs")
call require(head_response.endswith(separator + separator), "HEAD unexpectedly returned a body")

traversal_response = exchange("GET /../secret HTTP/1.1" + separator + "Host: localhost" + separator + separator)
call require(traversal_response.startswith("HTTP/1.1 403 Forbidden"), "path traversal was not rejected")

method_response = exchange("POST / HTTP/1.1" + separator + "Host: localhost" + separator + "Content-Length: 0" + separator + separator)
call require(method_response.startswith("HTTP/1.1 405 Method Not Allowed"), "unsupported method was not rejected")

host_response = exchange("GET / HTTP/1.1" + separator + separator)
call require(host_response.startswith("HTTP/1.1 400 Bad Request"), "missing Host was not rejected")

empty_host_response = exchange("GET / HTTP/1.1" + separator + "Host:" + separator + separator)
call require(empty_host_response.startswith("HTTP/1.1 400 Bad Request"), "empty Host was not rejected")

symlink_response = exchange("GET /escape HTTP/1.1" + separator + "Host: localhost" + separator + separator)
call require(symlink_response.startswith("HTTP/1.1 404 Not Found"), "symlink escape was not rejected")

fifo_response = exchange("GET /blocked.pipe HTTP/1.1" + separator + "Host: localhost" + separator + separator)
call require(fifo_response.startswith("HTTP/1.1 404 Not Found"), "non-regular static file was not rejected")

maximum_headers_request = "GET / HTTP/1.1" + separator + "Host: localhost"
header_index = 0
while header_index < 63:
    maximum_headers_request += separator + "X-LSL-" + String(header_index) + ": value"
    header_index += 1
end
maximum_headers_response = exchange(maximum_headers_request + separator + separator)
call require(maximum_headers_response.startswith("HTTP/1.1 200 OK"), "documented 64-header limit was rejected")

static_body_response = exchange("POST / HTTP/1.1" + separator + "Host: localhost" + separator + "Content-Length: 5" + separator + separator + "hello")
call require(static_body_response.startswith("HTTP/1.1 413 Content Too Large"), "static server accepted a request body")

call require(thread_join(worker) == 0, "HTTP server worker did not exit cleanly")

app_listener = httpserver.listen_ipv4("127.0.0.1", 0, 16)
listener_box[0] = app_listener
port_box[0] = httpserver.local_port(app_listener)
app_worker = thread_spawn(app_server_worker)
failed_handler_response = exchange("GET / HTTP/1.1" + separator + "Host: localhost" + separator + separator)
call require(failed_handler_response.startswith("HTTP/1.1 500 Internal Server Error"), "handler failure did not become an isolated 500 response")
recovered_handler_response = exchange("GET / HTTP/1.1" + separator + "Host: localhost" + separator + separator)
call require(recovered_handler_response.startswith("HTTP/1.1 200 OK") and recovered_handler_response.endswith("recovered" + chr(10)), "server did not recover after a handler failure")
call require(thread_join(app_worker) == 0, "HTTP application server worker did not exit cleanly")

echo_listener = httpserver.listen_ipv4("127.0.0.1", 0, 16)
listener_box[0] = echo_listener
port_box[0] = httpserver.local_port(echo_listener)
echo_worker = thread_spawn(echo_server_worker)

utf8_body = "ahoj " + chr(382) + "lu" + chr(357) + chr(10) + "druhy radek"
utf8_length = len(httpserver.text_bytes(utf8_body))
utf8_response = exchange("POST /submit HTTP/1.1" + separator + "Host: localhost" + separator + "Content-Length: " + String(utf8_length) + separator + separator + utf8_body)
call require(utf8_response.startswith("HTTP/1.1 200 OK"), "UTF-8 POST body was rejected")
call require(utf8_response.endswith("POST:" + utf8_body + chr(10)), "UTF-8 POST body did not round-trip")

binary_request = httpserver.text_bytes("POST /binary HTTP/1.1" + separator + "Host: localhost" + separator + "Content-Length: 4" + separator + separator)
binary_request.append(255)
binary_request.append(254)
binary_request.append(1)
binary_request.append(2)
binary_response = exchange_bytes(binary_request)
call require(binary_response.startswith("HTTP/1.1 200 OK") and binary_response.endswith("binary:4" + chr(10)), "invalid UTF-8 body did not stay binary-only")

continue_response = exchange("POST /expect HTTP/1.1" + separator + "Host: localhost" + separator + "Content-Length: 4" + separator + "Expect: 100-continue" + separator + separator + "cont")
call require(continue_response.startswith("HTTP/1.1 100 Continue"), "Expect: 100-continue got no interim response")
call require("HTTP/1.1 200 OK" in continue_response and continue_response.endswith("POST:cont" + chr(10)), "body after 100-continue was lost")

incomplete_response = exchange_half_close("POST /incomplete HTTP/1.1" + separator + "Host: localhost" + separator + "Content-Length: 10" + separator + separator + "four")
call require(incomplete_response.startswith("HTTP/1.1 400 Bad Request"), "incomplete request body was not rejected")

call httpserver.set_body_limit(1024)
oversized_response = exchange("POST /huge HTTP/1.1" + separator + "Host: localhost" + separator + "Content-Length: 9388608" + separator + separator)
call require(oversized_response.startswith("HTTP/1.1 413 Content Too Large"), "configured body limit was not enforced")
call httpserver.set_body_limit(0)

empty_body_response = exchange("GET /empty HTTP/1.1" + separator + "Host: localhost" + separator + separator)
call require(empty_body_response.startswith("HTTP/1.1 200 OK") and empty_body_response.endswith("GET:" + chr(10)), "empty body_text is not the empty string")

call require(thread_join(echo_worker) == 0, "HTTP echo server worker did not exit cleanly")

roundtrip_listener = httpserver.listen_ipv4("127.0.0.1", 0, 16)
listener_box[0] = roundtrip_listener
port_box[0] = httpserver.local_port(roundtrip_listener)
roundtrip_worker = thread_spawn(roundtrip_server_worker)

big_size = 9437184
big_header = httpserver.text_bytes("POST /big HTTP/1.1" + separator + "Host: localhost" + separator + "Content-Length: " + String(big_size) + separator + separator)
big_request = __lsl_byte_zeros(len(big_header) + big_size)
call __lsl_byte_copy(big_request, big_header, 0, 0, len(big_header))
fill_index = len(big_header)
while fill_index < len(big_request):
    big_request[fill_index] = 65
    fill_index += 1
end
big_response = exchange_raw(big_request, 10485760)
big_text_head = __lsl_text_from_bytes(big_response, 0, 200)
call require(big_text_head.startswith("HTTP/1.1 200 OK"), "9 MiB body was not accepted by default")
call require("Content-Length: " + String(big_size) in big_text_head, "9 MiB body did not round-trip in full")
call require(big_response[len(big_response) - 1] == 65, "9 MiB response payload is corrupted")

call httpserver.set_body_limit(1024)
limited_response = exchange("POST /limited HTTP/1.1" + separator + "Host: localhost" + separator + "Content-Length: 2048" + separator + separator + ("x" * 2048))
call require(limited_response.startswith("HTTP/1.1 413 Content Too Large"), "runtime-configured limit was not enforced")
call httpserver.set_body_limit(0)

restored_response = exchange("POST /restored HTTP/1.1" + separator + "Host: localhost" + separator + "Content-Length: 5" + separator + separator + "small")
call require(restored_response.startswith("HTTP/1.1 200 OK") and restored_response.endswith("small"), "limit reset did not restore unlimited bodies")

call require(thread_join(roundtrip_worker) == 0, "HTTP roundtrip server worker did not exit cleanly")

# Memory endurance: a child process serves MEMORY_REQUESTS garbage-allocating
# requests on its own main thread and verifies its RSS stays flat — the
# per-request gc() in serve_listener is what keeps it flat. The child runs in
# a separate process because that is the supported topology for a
# long-running listener; see the known-issue note in the 0.7.5 release notes
# about gc() while worker threads are running.
memory_port_path = String(arg(1)) + "/memory-port.txt"
call unlink(memory_port_path)
memory_child = thread_spawn(memory_child_worker)
memory_wait = 0
while not exists(memory_port_path):
    call time.sleep(0.05)
    memory_wait += 1
    if memory_wait > 200:
        Error(TestFailure: "memory server child did not publish its port")
    end
end
memory_port = Int(readfile(memory_port_path).strip())
memory_separator = chr(13) + chr(10)
memory_index = 0
while memory_index < MEMORY_REQUESTS:
    memory_client = __lsl_fd_socket(httpserver.AF_INET, httpserver.SOCK_STREAM)
    if memory_client < 0:
        Error(TestFailure: "memory endurance socket failed at " + String(memory_index))
    end
    memory_endpoint = httpserver.sockaddr_ipv4("127.0.0.1", memory_port)
    if __lsl_fd_connect(memory_client, memory_endpoint, len(memory_endpoint)) < 0:
        Error(TestFailure: "memory endurance connect failed at " + String(memory_index))
    end
    call httpserver.set_socket_timeout(memory_client, httpserver.SO_RCVTIMEO, 5)
    call httpserver.set_socket_timeout(memory_client, httpserver.SO_SNDTIMEO, 5)
    memory_payload = httpserver.text_bytes("GET /memory HTTP/1.1" + memory_separator + "Host: localhost" + memory_separator + memory_separator)
    if __lsl_fd_write(memory_client, memory_payload, len(memory_payload)) < 0:
        Error(TestFailure: "memory endurance write failed at " + String(memory_index))
    end
    memory_received = httpserver.read_handle_limit(memory_client, 500000)
    call fd.close(memory_client)
    if not memory_received["ok"]:
        Error(TestFailure: "memory endurance read failed at " + String(memory_index))
    end
    memory_index += 1
end
call require(thread_join(memory_child) == 0, "memory server thread join failed")
call require(memory_child_status[0] == 0, "memory endurance server failed with status " + String(memory_child_status[0]))

header_listener = httpserver.listen_ipv4("127.0.0.1", 0, 16)
listener_box[0] = header_listener
port_box[0] = httpserver.local_port(header_listener)
header_worker = thread_spawn(header_server_worker)
merged_response = exchange("GET / HTTP/1.1" + separator + "Host: localhost" + separator + "Via: 1.1 cdn" + separator + "via: 1.1 caddy" + separator + "X-Forwarded-For: 10.0.0.1" + separator + "X-Forwarded-For: 10.0.0.2, 10.0.0.3" + separator + "Cookie: a=1" + separator + "Cookie: b=2" + separator + separator)
call require(merged_response.startswith("HTTP/1.1 200 OK"), "repeated list headers were rejected")
call require(merged_response.endswith("via=1.1 cdn, 1.1 caddy|xff=10.0.0.1, 10.0.0.2, 10.0.0.3|cookie=a=1; b=2" + chr(10)), "repeated headers were not merged: " + merged_response)
for smuggling in ["Content-Length: 0" + separator + "Content-Length: 0", "Host: other", "Transfer-Encoding: chunked" + separator + "Transfer-Encoding: chunked"]:
    smuggling_response = exchange("GET / HTTP/1.1" + separator + "Host: localhost" + separator + smuggling + separator + separator)
    call require(smuggling_response.startswith("HTTP/1.1 400 Bad Request") and "duplicate header: " in smuggling_response, "duplicate framing header was accepted: " + smuggling)
end
single_response = exchange("GET / HTTP/1.1" + separator + "Host: localhost" + separator + separator)
call require(single_response.endswith("via=-|xff=-|cookie=-" + chr(10)), "single request headers changed")
call require(thread_join(header_worker) == 0, "HTTP header server worker did not exit cleanly")

stream_listener = httpserver.listen_ipv4("127.0.0.1", 0, 16)
listener_box[0] = stream_listener
port_box[0] = httpserver.local_port(stream_listener)
stream_worker = thread_spawn(stream_server_worker)
chunked_response = exchange("GET /events HTTP/1.1" + separator + "Host: localhost" + separator + separator)
stream_head = chunked_response[0:chunked_response.find(separator + separator)]
stream_body = chunked_response[chunked_response.find(separator + separator) + 4:len(chunked_response)]
call require(stream_head.startswith("HTTP/1.1 200 OK") and "Transfer-Encoding: chunked" in stream_head and "Content-Type: text/event-stream" in stream_head and "Content-Length" not in stream_head, "streamed response head is wrong: " + stream_head)
expected_events = "d" + separator + "data: first" + chr(10) + chr(10) + separator + "25" + separator + "event: update" + chr(10) + "data: two" + chr(10) + "data: lines" + chr(10) + chr(10) + separator + "7" + separator + ": raw" + chr(10) + chr(10) + separator + "0" + separator + separator
call require(stream_body == expected_events, "chunked SSE body differs: " + stream_body)
plain_response = exchange("GET /events HTTP/1.0" + separator + separator)
call require(plain_response.startswith("HTTP/1.1 200 OK") and "Transfer-Encoding" not in plain_response and plain_response.endswith(separator + separator + "data: first" + chr(10) + chr(10) + "event: update" + chr(10) + "data: two" + chr(10) + "data: lines" + chr(10) + chr(10) + ": raw" + chr(10) + chr(10)), "HTTP/1.0 stream is not close-delimited: " + plain_response)
broken_response = exchange("GET /broken HTTP/1.1" + separator + "Host: localhost" + separator + separator)
call require(broken_response.endswith("7" + separator + "partial" + separator), "failed producer must end without the final chunk: " + broken_response)
head_stream_response = exchange("HEAD /events HTTP/1.1" + separator + "Host: localhost" + separator + separator)
call require(head_stream_response.endswith(separator + separator) and "data:" not in head_stream_response, "HEAD streamed a body")
invalid_stream_response = exchange("GET /invalid HTTP/1.1" + separator + "Host: localhost" + separator + separator)
call require(invalid_stream_response.startswith("HTTP/1.1 500 Internal Server Error"), "non-Function stream was accepted")
call require(thread_join(stream_worker) == 0, "HTTP stream server worker did not exit cleanly")

protocol_listener = httpserver.listen_ipv4("127.0.0.1", 0, 16)
listener_box[0] = protocol_listener
port_box[0] = httpserver.local_port(protocol_listener)
protocol_worker = thread_spawn(protocol_server_worker)
dot_response = exchange("GET / HTTP/1.1" + separator + "Host: localhost" + separator + "X.Test: ok" + separator + separator)
call require(dot_response.startswith("HTTP/1.1 200 OK") and dot_response.endswith("dot=ok" + chr(10)), "tchar header name was rejected: " + dot_response)
for invalid_request in ["GET / HTTP/1.1" + separator + "Host: localhost" + separator + "X-Test: one" + chr(13) + "two" + separator + separator, "GET / HTTP/1.1" + separator + "Host: localhost" + separator + "X-Test: one" + chr(13) + separator + separator, "G" + chr(9) + "ET / HTTP/1.1" + separator + "Host: localhost" + separator + separator, "GET /one" + chr(13) + "two HTTP/1.1" + separator + "Host: localhost" + separator + separator]:
    invalid_response = exchange(invalid_request)
    call require(invalid_response.startswith("HTTP/1.1 400 Bad Request"), "invalid request reached the handler: " + invalid_response)
end
for empty_status in ["204", "304"]:
    empty_response = exchange("GET /" + empty_status + " HTTP/1.1" + separator + "Host: localhost" + separator + separator)
    call require(empty_response.startswith("HTTP/1.1 " + empty_status + " ") and empty_response.endswith(separator + separator) and "BADBODY" not in empty_response and "Content-Length" not in empty_response, "status " + empty_status + " sent a body: " + empty_response)
end
call require(thread_join(protocol_worker) == 0, "HTTP protocol server worker did not exit cleanly")

pool_listener = httpserver.listen_ipv4("127.0.0.1", 0, 16)
listener_box[0] = pool_listener
port_box[0] = httpserver.local_port(pool_listener)
pool_worker = thread_spawn(pool_server_worker)
pool_started = time.monotonic()
pool_clients = [thread_spawn(pool_client_0), thread_spawn(pool_client_1), thread_spawn(pool_client_2), thread_spawn(pool_client_3)]
for pool_client in pool_clients:
    call thread_join(pool_client)
end
pool_elapsed = time.monotonic() - pool_started
call require(thread_join(pool_worker) == 0 and pool_served[0] == 4, "HTTP worker pool did not serve exactly four requests")
for pool_index in rang(4):
    call require(pool_results[pool_index].startswith("HTTP/1.1 200 OK") and pool_results[pool_index].endswith("pool /" + "abcd"[pool_index] + chr(10)), "HTTP worker pool response differs")
end
call require(pool_active[1] >= 2, "HTTP worker pool did not handle requests concurrently")

call unlink(escape_path)
call unlink(fifo_path)
print "httpserver conformance ok"
