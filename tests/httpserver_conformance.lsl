load fd
load httpserver

listener_box = IntArray()
root_box = IntArray()
port_box = IntArray()

function server_worker():
    call httpserver.serve_listener(listener_box[0], root_box[0], None, 10, False)
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

escape_path = String(arg(1)) + "/escape"
call unlink(escape_path)
fifo_path = String(arg(1)) + "/blocked.pipe"
call unlink(fifo_path)
if run_clean("/usr/bin/mkfifo", [fifo_path]) != 0:
    Error(TestFailure: "cannot create HTTP FIFO fixture")
end
escape_target = httpserver.cstring("/etc/passwd")
escape_name = httpserver.cstring(escape_path)
if __lsl_syscall(88, httpserver.data_address(escape_target), httpserver.data_address(escape_name), 0, 0) < 0:
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

call unlink(escape_path)
call unlink(fifo_path)
print "httpserver conformance ok"
