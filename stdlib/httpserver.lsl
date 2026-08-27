# Bounded HTTP/1.1 server for Linux x86-64. The transport is syscall-only;
# static files are opened relative to one pinned directory descriptor through
# openat2(RESOLVE_BENEATH|NO_MAGICLINKS|NO_SYMLINKS), so URL traversal and
# symlink escapes fail in the kernel rather than relying on string checks.

load fd
load time

SYS_SOCKET = 41
SYS_SENDTO = 44
SYS_ACCEPT4 = 288
SYS_BIND = 49
SYS_LISTEN = 50
SYS_GETSOCKNAME = 51
SYS_SETSOCKOPT = 54
SYS_OPENAT2 = 437

AF_INET = 2
SOCK_STREAM = 1
SOCK_CLOEXEC = 524288
SOL_SOCKET = 1
SO_REUSEADDR = 2
SO_LINGER = 13
SO_RCVTIMEO = 20
SO_SNDTIMEO = 21
MSG_NOSIGNAL = 16384

O_RDONLY = 0
O_DIRECTORY = 65536
O_CLOEXEC = 524288
O_NOFOLLOW = 131072
RESOLVE_NO_MAGICLINKS = 2
RESOLVE_NO_SYMLINKS = 4
RESOLVE_BENEATH = 8

MAX_HEADER_BYTES = 16384
MAX_HEADER_COUNT = 64
MAX_TARGET_BYTES = 2048
MAX_BODY_BYTES = 8388608
SOCKET_TIMEOUT_SECONDS = 5

function put_u32(buffer, offset, value):
    target = ByteArray(buffer)
    number = Int(value)
    target[offset] = number % 256
    target[offset + 1] = number // 256 % 256
    target[offset + 2] = number // 65536 % 256
    target[offset + 3] = number // 16777216 % 256
    return None
end

function put_u64(buffer, offset, value):
    target = ByteArray(buffer)
    number = Int(value)
    target[offset] = number % 256
    target[offset + 1] = number // 256 % 256
    target[offset + 2] = number // 65536 % 256
    target[offset + 3] = number // 16777216 % 256
    target[offset + 4] = number // 4294967296 % 256
    target[offset + 5] = number // 1099511627776 % 256
    target[offset + 6] = number // 281474976710656 % 256
    target[offset + 7] = number // 72057594037927936 % 256
    return None
end

function data_address(buffer):
    return Int(__lsl_data_address(ByteArray(buffer)))
end

# Connected TCP writes use MSG_NOSIGNAL so one client reset cannot terminate
# the whole server with SIGPIPE. Keep the same complete-write contract as the
# runtime fd helper, including EINTR retry and bounded-socket EAGAIN/error
# propagation.
function socket_write(handle, payload):
    buffer = ByteArray(payload)
    offset = 0
    remaining = len(buffer)
    while remaining > 0:
        result = __lsl_syscall6(SYS_SENDTO, Int(handle), data_address(buffer) + offset, remaining, MSG_NOSIGNAL, 0, 0)
        if result > 0:
            offset += result
            remaining -= result
        elif result == -4:
            continue
        else:
            return result
        end
    end
    return 0
end

function text_bytes(value):
    text = String(value)
    length = __lsl_text_byte_length(text)
    result = __lsl_byte_zeros(length)
    index = 0
    while index < length:
        result[index] = __lsl_text_byte(text, index)
        index += 1
    end
    return result
end

function cstring(value):
    text = String(value)
    if len(text) == 0 or __lsl_text_byte_length(text) > 4095:
        Error(ServerError: "path must contain 1..4095 bytes")
    end
    result = __lsl_byte_zeros(__lsl_text_byte_length(text) + 1)
    index = 0
    while index < __lsl_text_byte_length(text):
        byte = __lsl_text_byte(text, index)
        if byte == 0:
            Error(ServerError: "path must not contain NUL")
        end
        result[index] = byte
        index += 1
    end
    return result
end

function ipv4_octets(address):
    text = String(address)
    parts = text.split(".")
    if len(parts) != 4:
        Error(ServerError: "bind address must be numeric IPv4")
    end
    result = IntArray()
    for part in parts:
        if len(part) == 0 or len(part) > 3:
            Error(ServerError: "bind address must be numeric IPv4")
        end
        for character in part:
            code = ord(character)
            if code < 48 or code > 57:
                Error(ServerError: "bind address must be numeric IPv4")
            end
        end
        octet = Int(part)
        if octet < 0 or octet > 255:
            Error(ServerError: "bind address octet is outside 0..255")
        end
        result.append(octet)
    end
    return result
end

function sockaddr_ipv4(address, port):
    number = Int(port)
    if number < 0 or number > 65535:
        Error(ServerError: "port must be between 0 and 65535")
    end
    octets = ipv4_octets(address)
    result = __lsl_byte_zeros(16)
    result[0] = AF_INET
    result[1] = 0
    result[2] = number // 256
    result[3] = number % 256
    index = 0
    while index < 4:
        result[4 + index] = octets[index]
        index += 1
    end
    return result
end

function set_socket_option(handle, option, value):
    payload = __lsl_byte_zeros(4)
    call put_u32(payload, 0, value)
    return __lsl_syscall6(SYS_SETSOCKOPT, Int(handle), SOL_SOCKET, Int(option), data_address(payload), 4, 0)
end

function set_socket_timeout(handle, option, seconds):
    timeout = __lsl_byte_zeros(16)
    call put_u64(timeout, 0, seconds)
    return __lsl_syscall6(SYS_SETSOCKOPT, Int(handle), SOL_SOCKET, Int(option), data_address(timeout), 16, 0)
end

function listen_ipv4(address, port, backlog):
    endpoint = sockaddr_ipv4(address, port)
    handle = __lsl_syscall(SYS_SOCKET, AF_INET, SOCK_STREAM + SOCK_CLOEXEC, 0, 0)
    if handle < 0:
        Error(ServerError: "socket failed (" + String(handle) + ")")
    end
    if set_socket_option(handle, SO_REUSEADDR, 1) < 0:
        call fd.close(handle)
        Error(ServerError: "cannot set SO_REUSEADDR")
    end
    if __lsl_syscall(SYS_BIND, handle, data_address(endpoint), len(endpoint), 0) < 0:
        call fd.close(handle)
        Error(ServerError: "cannot bind " + String(address) + ":" + String(port))
    end
    queue = Int(backlog)
    if queue < 1:
        queue = 1
    elif queue > 4096:
        queue = 4096
    end
    if __lsl_syscall(SYS_LISTEN, handle, queue, 0, 0) < 0:
        call fd.close(handle)
        Error(ServerError: "listen failed")
    end
    return handle
end

function local_port(listener):
    endpoint = __lsl_byte_zeros(16)
    endpoint_length = __lsl_byte_zeros(4)
    call put_u32(endpoint_length, 0, 16)
    result = __lsl_syscall(SYS_GETSOCKNAME, Int(listener), data_address(endpoint), data_address(endpoint_length), 0)
    if result < 0 or endpoint[0] != AF_INET:
        Error(ServerError: "getsockname failed")
    end
    return endpoint[2] * 256 + endpoint[3]
end

function accept_client(listener):
    client = __lsl_syscall(SYS_ACCEPT4, Int(listener), 0, 0, SOCK_CLOEXEC)
    if client < 0:
        return client
    end
    receive = set_socket_timeout(client, SO_RCVTIMEO, SOCKET_TIMEOUT_SECONDS)
    send = set_socket_timeout(client, SO_SNDTIMEO, SOCKET_TIMEOUT_SECONDS)
    if receive < 0 or send < 0:
        call fd.close(client)
        return -22
    end
    return client
end

function open_root(path):
    handle = __lsl_fd_open(String(path), O_RDONLY + O_DIRECTORY)
    if handle < 0:
        Error(ServerError: "cannot open server root: " + String(path))
    end
    return handle
end

function open_static(root_handle, relative_path):
    path = cstring(relative_path)
    how = __lsl_byte_zeros(24)
    call put_u64(how, 0, O_RDONLY + O_CLOEXEC + O_NOFOLLOW)
    call put_u64(how, 16, RESOLVE_NO_MAGICLINKS + RESOLVE_NO_SYMLINKS + RESOLVE_BENEATH)
    return __lsl_syscall(SYS_OPENAT2, Int(root_handle), data_address(path), data_address(how), 24)
end

function read_handle_limit(handle, limit):
    maximum = Int(limit)
    chunk = __lsl_byte_zeros(4096)
    capacity = min(4096, maximum)
    collected = __lsl_byte_zeros(capacity)
    total = 0
    loop:
        count = __lsl_fd_read(Int(handle), chunk, len(chunk))
        if count == -4:
            continue
        elif count < 0:
            return {"ok": False, "too_large": False, "data": ByteArray()}
        elif count == 0:
            break
        elif count > maximum - total:
            return {"ok": False, "too_large": True, "data": ByteArray()}
        end
        required = total + count
        if required > capacity:
            next_capacity = max(1, capacity)
            while next_capacity < required:
                next_capacity = min(maximum, next_capacity * 2)
            end
            grown = __lsl_byte_zeros(next_capacity)
            call __lsl_byte_copy(grown, collected, 0, 0, total)
            collected = grown
            capacity = next_capacity
        end
        call __lsl_byte_copy(collected, chunk, total, 0, count)
        total += count
    end
    exact = __lsl_byte_zeros(total)
    call __lsl_byte_copy(exact, collected, 0, 0, total)
    return {"ok": True, "too_large": False, "data": exact}
end

function header_end(buffer, length):
    index = 3
    while index < length:
        if buffer[index - 3] == 13 and buffer[index - 2] == 10 and buffer[index - 1] == 13 and buffer[index] == 10:
            return index + 1
        end
        index += 1
    end
    return -1
end

function error_request(status, reason, message):
    return {"ok": False, "status": status, "reason": reason, "message": message}
end

function valid_header_name(name):
    if len(name) == 0 or len(name) > 64:
        return False
    end
    for character in name:
        code = ord(character)
        if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or character == "-"):
            return False
        end
    end
    return True
end

function decimal_header(value):
    if len(value) == 0 or len(value) > 19:
        return -1
    end
    result = 0
    for character in value:
        code = ord(character)
        if code < 48 or code > 57:
            return -1
        end
        digit = code - 48
        if result > 922337203685477580 or (result == 922337203685477580 and digit > 7):
            return -1
        end
        result = result * 10 + digit
    end
    return result
end

function read_request(client):
    collected = __lsl_byte_zeros(MAX_HEADER_BYTES)
    chunk = __lsl_byte_zeros(4096)
    total = 0
    finish = -1
    while finish < 0:
        count = __lsl_fd_read(Int(client), chunk, len(chunk))
        if count == -4:
            continue
        elif count == -11 or count == -110:
            return error_request(408, "Request Timeout", "request header timed out")
        elif count < 0 or count == 0:
            return error_request(400, "Bad Request", "request header is incomplete")
        elif count > MAX_HEADER_BYTES - total:
            return error_request(431, "Request Header Fields Too Large", "request header exceeds 16 KiB")
        end
        call __lsl_byte_copy(collected, chunk, total, 0, count)
        total += count
        finish = header_end(collected, total)
        if finish < 0 and total == MAX_HEADER_BYTES:
            return error_request(431, "Request Header Fields Too Large", "request header exceeds 16 KiB")
        end
    end
    index = 0
    while index < finish:
        byte = collected[index]
        if byte > 127 or (byte < 32 and byte != 9 and byte != 10 and byte != 13) or byte == 127:
            return error_request(400, "Bad Request", "request header contains an invalid byte")
        end
        index += 1
    end
    text = __lsl_text_from_bytes(collected, 0, finish)
    lines = text.split(chr(13) + chr(10))
    if len(lines) < 3 or len(lines) > MAX_HEADER_COUNT + 2:
        return error_request(400, "Bad Request", "request header has an invalid line count")
    end
    request_line = lines[0].split(" ")
    if len(request_line) != 3 or request_line[0] == "" or request_line[1] == "":
        return error_request(400, "Bad Request", "request line is invalid")
    end
    method = String(request_line[0])
    target = String(request_line[1])
    version = String(request_line[2])
    if version != "HTTP/1.1" and version != "HTTP/1.0":
        return error_request(505, "HTTP Version Not Supported", "only HTTP/1.0 and HTTP/1.1 are supported")
    elif __lsl_text_byte_length(target) > MAX_TARGET_BYTES:
        return error_request(414, "URI Too Long", "request target exceeds 2048 bytes")
    end
    headers = {}
    line_index = 1
    while line_index < len(lines):
        line = lines[line_index]
        if line == "":
            break
        elif line[0] == " " or line[0] == chr(9):
            return error_request(400, "Bad Request", "folded headers are not supported")
        end
        separator = line.find(":")
        if separator <= 0:
            return error_request(400, "Bad Request", "header field is invalid")
        end
        name = line[0:separator]
        if not valid_header_name(name):
            return error_request(400, "Bad Request", "header name is invalid")
        end
        name = name.lower()
        if name in headers:
            return error_request(400, "Bad Request", "duplicate header: " + name)
        end
        headers[name] = line[separator + 1:len(line)].strip()
        line_index += 1
    end
    if version == "HTTP/1.1" and "host" not in headers:
        return error_request(400, "Bad Request", "HTTP/1.1 requires Host")
    elif "transfer-encoding" in headers:
        return error_request(400, "Bad Request", "Transfer-Encoding is not accepted")
    elif "content-length" in headers:
        content_length = decimal_header(headers["content-length"])
        if content_length < 0:
            return error_request(400, "Bad Request", "Content-Length is invalid")
        elif content_length != 0:
            return error_request(413, "Content Too Large", "request bodies are not accepted")
        end
    end
    return {"ok": True, "method": method, "target": target, "version": version, "headers": headers}
end

function safe_relative_target(target):
    raw = String(target)
    query = raw.find("?")
    if query >= 0:
        raw = raw[0:query]
    end
    if len(raw) == 0 or raw[0] != "/" or "#" in raw or "%" in raw or chr(92) in raw:
        return None
    end
    if raw == "/":
        return "index.html"
    end
    relative = raw[1:len(raw)]
    if len(relative) == 0 or len(relative) > MAX_TARGET_BYTES:
        return None
    end
    for component in relative.split("/"):
        if component == "" or component == "." or component == "..":
            return None
        end
        for character in component:
            code = ord(character)
            if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or character == "-" or character == "_" or character == "."):
                return None
            end
        end
    end
    return relative
end

function content_type(path):
    lower = String(path).lower()
    if lower.endswith(".html") or lower.endswith(".htm"):
        return "text/html; charset=utf-8"
    elif lower.endswith(".css"):
        return "text/css; charset=utf-8"
    elif lower.endswith(".js"):
        return "text/javascript; charset=utf-8"
    elif lower.endswith(".json"):
        return "application/json"
    elif lower.endswith(".txt") or lower.endswith(".md"):
        return "text/plain; charset=utf-8"
    elif lower.endswith(".svg"):
        return "image/svg+xml"
    elif lower.endswith(".png"):
        return "image/png"
    elif lower.endswith(".jpg") or lower.endswith(".jpeg"):
        return "image/jpeg"
    elif lower.endswith(".gif"):
        return "image/gif"
    elif lower.endswith(".wasm"):
        return "application/wasm"
    end
    return "application/octet-stream"
end

function valid_content_type(value):
    text = String(value)
    if len(text) == 0 or len(text) > 128:
        return False
    end
    for character in text:
        code = ord(character)
        if code < 32 or code > 126 or character == chr(13) or character == chr(10):
            return False
        end
    end
    return True
end

function status_reason(status):
    if status == 200:
        return "OK"
    elif status == 400:
        return "Bad Request"
    elif status == 403:
        return "Forbidden"
    elif status == 404:
        return "Not Found"
    elif status == 405:
        return "Method Not Allowed"
    elif status == 408:
        return "Request Timeout"
    elif status == 413:
        return "Content Too Large"
    elif status == 414:
        return "URI Too Long"
    elif status == 431:
        return "Request Header Fields Too Large"
    elif status == 500:
        return "Internal Server Error"
    elif status == 505:
        return "HTTP Version Not Supported"
    end
    return "Response"
end

function send_response(client, status, reason, body, body_type, head_only):
    payload = body
    if type(payload) == "String":
        payload = text_bytes(payload)
    elif type(payload) != "ByteArray":
        payload = text_bytes(String(payload))
    end
    mime = String(body_type)
    if not valid_content_type(mime):
        mime = "application/octet-stream"
    end
    header = "HTTP/1.1 " + String(status) + " " + String(reason) + chr(13) + chr(10)
    header += "Content-Length: " + String(len(payload)) + chr(13) + chr(10)
    header += "Content-Type: " + mime + chr(13) + chr(10)
    header += "Connection: close" + chr(13) + chr(10)
    header += "X-Content-Type-Options: nosniff" + chr(13) + chr(10)
    header += "Referrer-Policy: no-referrer" + chr(13) + chr(10) + chr(13) + chr(10)
    header_bytes = text_bytes(header)
    result = socket_write(client, header_bytes)
    if result >= 0 and not Bool(head_only) and len(payload) > 0:
        result = socket_write(client, payload)
    end
    return result
end

function send_error(client, request):
    status = Int(request["status"])
    reason = String(request["reason"])
    body = String(status) + " " + reason + chr(10) + String(request["message"]) + chr(10)
    return send_response(client, status, reason, body, "text/plain; charset=utf-8", False)
end

function static_response(root_handle, request):
    if request["method"] != "GET" and request["method"] != "HEAD":
        return {"status": 405, "reason": "Method Not Allowed", "body": "405 Method Not Allowed" + chr(10), "content_type": "text/plain; charset=utf-8"}
    end
    relative = safe_relative_target(request["target"])
    if relative == None:
        return {"status": 403, "reason": "Forbidden", "body": "403 Forbidden" + chr(10), "content_type": "text/plain; charset=utf-8"}
    end
    handle = open_static(root_handle, relative)
    if handle < 0:
        return {"status": 404, "reason": "Not Found", "body": "404 Not Found" + chr(10), "content_type": "text/plain; charset=utf-8"}
    end
    file = read_handle_limit(handle, MAX_BODY_BYTES)
    call fd.close(handle)
    if not file["ok"]:
        if file["too_large"]:
            return {"status": 413, "reason": "Content Too Large", "body": "413 Content Too Large" + chr(10), "content_type": "text/plain; charset=utf-8"}
        end
        return {"status": 404, "reason": "Not Found", "body": "404 Not Found" + chr(10), "content_type": "text/plain; charset=utf-8"}
    end
    return {"status": 200, "reason": "OK", "body": file["data"], "content_type": content_type(relative)}
end

function normalize_app_response(value):
    if type(value) == "String" or type(value) == "ByteArray":
        return {"status": 200, "reason": "OK", "body": value, "content_type": "text/plain; charset=utf-8"}
    elif type(value) != "Dictionary":
        return {"status": 500, "reason": "Internal Server Error", "body": "500 Internal Server Error" + chr(10), "content_type": "text/plain; charset=utf-8"}
    end
    status = Int(value.get("status", 200))
    if status < 100 or status > 599:
        status = 500
    end
    reason = value.get("reason", status_reason(status))
    body = value.get("body", "")
    mime = value.get("content_type", "text/plain; charset=utf-8")
    if type(reason) != "String" or not valid_content_type(reason) or type(mime) != "String" or not valid_content_type(mime):
        return {"status": 500, "reason": "Internal Server Error", "body": "500 Internal Server Error" + chr(10), "content_type": "text/plain; charset=utf-8"}
    end
    return {"status": status, "reason": reason, "body": body, "content_type": mime}
end

function serve_listener(listener, root_handle, handler, maximum_requests, announce):
    served = 0
    limit = maximum_requests
    if limit < 0:
        Error(ServerError: "maximum request count cannot be negative")
    end
    loop:
        if limit > 0 and served >= limit:
            break
        end
        client = accept_client(listener)
        if client == -4:
            continue
        elif client < 0:
            call fd.close(listener)
            if root_handle >= 0:
                call fd.close(root_handle)
            end
            Error(ServerError: "accept failed (" + String(client) + ")")
        end
        request = read_request(client)
        if not request["ok"]:
            call send_error(client, request)
        else:
            if handler == None:
                response = static_response(root_handle, request)
            else:
                response = normalize_app_response(handler(request))
            end
            head_only = request["method"] == "HEAD"
            call send_response(client, response["status"], response["reason"], response["body"], response["content_type"], head_only)
        end
        call fd.close(client)
        served += 1
    end
    call fd.close(listener)
    if root_handle >= 0:
        call fd.close(root_handle)
    end
    return served
end

function serve_static(root, address, port, maximum_requests):
    listener = listen_ipv4(address, port, 128)
    root_handle = open_root(root)
    print "LSL HTTP server listening on http://" + String(address) + ":" + String(port) + "/"
    return serve_listener(listener, root_handle, None, maximum_requests, True)
end

function serve(handler, address, port, maximum_requests):
    if type(handler) != "Function":
        Error(TypeError: "HTTP handler must be a Function")
    end
    listener = listen_ipv4(address, port, 128)
    print "LSL HTTP server listening on http://" + String(address) + ":" + String(port) + "/"
    return serve_listener(listener, -1, handler, maximum_requests, True)
end

function system_tool(primary, fallback, label):
    if exists(primary):
        return primary
    elif exists(fallback):
        return fallback
    end
    Error(ServerError: "trusted " + String(label) + " executable is required")
end

function runtime_directory():
    process = String(__lsl_syscall(39, 0, 0, 0, 0))
    attempt = 0
    directory = "/tmp/lsl-https-" + process
    while __lsl_mkdir_private(directory) != 0:
        attempt += 1
        if attempt > 100:
            Error(ServerError: "cannot create a private HTTPS runtime directory")
        end
        directory = "/tmp/lsl-https-" + process + "-" + String(attempt)
    end
    return directory
end

function canonical_path(path, label):
    realpath = system_tool("/usr/bin/realpath", "/bin/realpath", "realpath")
    result = capture_clean(realpath, ["-e", "--", String(path)])
    if capture_status() != 0 or not result.endswith(chr(10)):
        Error(ServerError: "cannot resolve " + String(label) + ": " + String(path))
    end
    result = result[0:len(result) - 1]
    if len(result) == 0 or chr(10) in result or chr(13) in result:
        Error(ServerError: String(label) + " has an unsupported path")
    end
    return result
end

function nginx_quote(value):
    result = "\""
    for character in String(value):
        if character == chr(92) or character == "\"" or character == "$":
            result += chr(92)
        end
        result += character
    end
    return result + "\""
end

# HTTPS intentionally delegates cryptography and protocol negotiation to the
# host's maintained nginx/OpenSSL stack. LSL supplies a private, generated
# configuration and never interpolates an unquoted caller-controlled token.
# This frontend serves static files only; application handlers should normally
# run on loopback behind the deployment's existing TLS reverse proxy.
function serve_static_tls(root, address, port, certificate, private_key, maximum_requests):
    if maximum_requests != 0:
        Error(ServerError: "HTTPS mode does not support --max-requests")
    end
    number = port
    if number < 1 or number > 65535:
        Error(ServerError: "HTTPS port must be between 1 and 65535")
    end
    # Validate the address using the same strict numeric parser as native HTTP.
    call ipv4_octets(address)
    root_path = canonical_path(root, "server root")
    certificate_path = canonical_path(certificate, "TLS certificate")
    key_path = canonical_path(private_key, "TLS private key")
    directory = runtime_directory()
    config_path = directory + "/nginx.conf"
    config = "worker_processes 1;" + chr(10)
    config += "master_process off;" + chr(10)
    config += "daemon off;" + chr(10)
    config += "pid " + nginx_quote(directory + "/nginx.pid") + ";" + chr(10)
    config += "error_log stderr warn;" + chr(10)
    config += "events { worker_connections 128; }" + chr(10)
    config += "http {" + chr(10)
    config += "  access_log off;" + chr(10)
    config += "  server_tokens off;" + chr(10)
    config += "  client_body_temp_path " + nginx_quote(directory + "/client-body") + ";" + chr(10)
    config += "  proxy_temp_path " + nginx_quote(directory + "/proxy") + ";" + chr(10)
    config += "  fastcgi_temp_path " + nginx_quote(directory + "/fastcgi") + ";" + chr(10)
    config += "  uwsgi_temp_path " + nginx_quote(directory + "/uwsgi") + ";" + chr(10)
    config += "  scgi_temp_path " + nginx_quote(directory + "/scgi") + ";" + chr(10)
    config += "  sendfile on;" + chr(10)
    config += "  client_header_timeout 5s;" + chr(10)
    config += "  client_body_timeout 5s;" + chr(10)
    config += "  send_timeout 5s;" + chr(10)
    config += "  keepalive_timeout 0;" + chr(10)
    config += "  client_max_body_size 1k;" + chr(10)
    config += "  large_client_header_buffers 2 8k;" + chr(10)
    config += "  default_type application/octet-stream;" + chr(10)
    config += "  types { text/html html htm; text/css css; text/javascript js; application/json json; text/plain txt md; image/svg+xml svg; image/png png; image/jpeg jpg jpeg; image/gif gif; application/wasm wasm; }" + chr(10)
    config += "  server {" + chr(10)
    config += "    listen " + String(address) + ":" + String(number) + " ssl;" + chr(10)
    config += "    server_name _;" + chr(10)
    config += "    ssl_certificate " + nginx_quote(certificate_path) + ";" + chr(10)
    config += "    ssl_certificate_key " + nginx_quote(key_path) + ";" + chr(10)
    config += "    ssl_protocols TLSv1.2 TLSv1.3;" + chr(10)
    config += "    ssl_session_tickets off;" + chr(10)
    config += "    root " + nginx_quote(root_path) + ";" + chr(10)
    config += "    autoindex off;" + chr(10)
    config += "    disable_symlinks on from=$document_root;" + chr(10)
    config += "    add_header X-Content-Type-Options nosniff always;" + chr(10)
    config += "    add_header Referrer-Policy no-referrer always;" + chr(10)
    config += "    if ($request_method !~ ^(GET|HEAD)$) { return 405; }" + chr(10)
    config += "    location / { try_files $uri =404; }" + chr(10)
    config += "  }" + chr(10)
    config += "}" + chr(10)
    call writefile(config_path, config)
    nginx = system_tool("/usr/sbin/nginx", "/usr/bin/nginx", "nginx")
    print "LSL HTTPS server listening on https://" + String(address) + ":" + String(number) + "/"
    status = run_clean(nginx, ["-p", directory + "/", "-c", config_path])
    call unlink(directory + "/nginx.pid")
    call unlink(config_path)
    call rmdir(directory + "/client-body")
    call rmdir(directory + "/proxy")
    call rmdir(directory + "/fastcgi")
    call rmdir(directory + "/uwsgi")
    call rmdir(directory + "/scgi")
    call rmdir(directory)
    return status
end
