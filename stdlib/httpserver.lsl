load _httpserver_transport as transport
# Společný HTTP/1.1 parser a obsluha požadavků. Sockety, bezpečné otevírání
# souborů a HTTPS deployment poskytuje vybraný transport.

load fd
load time

SYS_SOCKET = transport.SYS_SOCKET
SYS_FSTAT = transport.SYS_FSTAT
SYS_SENDTO = transport.SYS_SENDTO
SYS_ACCEPT4 = transport.SYS_ACCEPT4
SYS_BIND = transport.SYS_BIND
SYS_LISTEN = transport.SYS_LISTEN
SYS_GETSOCKNAME = transport.SYS_GETSOCKNAME
SYS_SETSOCKOPT = transport.SYS_SETSOCKOPT
SYS_OPENAT2 = transport.SYS_OPENAT2
AF_INET = transport.AF_INET
SOCK_STREAM = transport.SOCK_STREAM
SOCK_CLOEXEC = transport.SOCK_CLOEXEC
SOL_SOCKET = transport.SOL_SOCKET
SO_REUSEADDR = transport.SO_REUSEADDR
SO_LINGER = transport.SO_LINGER
SO_RCVTIMEO = transport.SO_RCVTIMEO
SO_SNDTIMEO = transport.SO_SNDTIMEO
MSG_NOSIGNAL = transport.MSG_NOSIGNAL
O_RDONLY = transport.O_RDONLY
O_NONBLOCK = transport.O_NONBLOCK
O_DIRECTORY = transport.O_DIRECTORY
O_CLOEXEC = transport.O_CLOEXEC
O_NOFOLLOW = transport.O_NOFOLLOW
RESOLVE_NO_MAGICLINKS = transport.RESOLVE_NO_MAGICLINKS
RESOLVE_NO_SYMLINKS = transport.RESOLVE_NO_SYMLINKS
RESOLVE_BENEATH = transport.RESOLVE_BENEATH
S_IFMT = transport.S_IFMT
S_IFREG = transport.S_IFREG

MAX_HEADER_BYTES = 16384
MAX_HEADER_COUNT = 64
MAX_TARGET_BYTES = 2048
MAX_BODY_BYTES = 8388608
SOCKET_TIMEOUT_SECONDS = 5
BODY_CHUNK_BYTES = 65536
BODY_INITIAL_CAPACITY = 16777216

# Dynamic request and response body limit in bytes; 0 means unlimited (the
# 0.7.3 default). MAX_BODY_BYTES keeps bounding only the static file server.
BODY_LIMIT = IntArray()
BODY_LIMIT.append(0)

function set_body_limit(limit):
    value = Int(limit)
    if value < 0:
        Error(ValueError: "body limit cannot be negative")
    end
    BODY_LIMIT[0] = value
    return None
end

function body_limit():
    return BODY_LIMIT[0]
end

function put_u32(buffer, offset, value):
    return transport.put_u32(buffer, offset, value)
end

function get_u32(buffer, offset):
    return transport.get_u32(buffer, offset)
end

function put_u64(buffer, offset, value):
    return transport.put_u64(buffer, offset, value)
end

function data_address(buffer):
    return transport.data_address(buffer)
end

# Connected TCP writes use MSG_NOSIGNAL so one client reset cannot terminate
# the whole server with SIGPIPE. Keep the same complete-write contract as the
# runtime fd helper, including EINTR retry and bounded-socket EAGAIN/error
# propagation.
function socket_write(handle, payload):
    return transport.socket_write(handle, payload)
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
    return transport.cstring(value)
end

function ipv4_octets(address):
    return transport.ipv4_octets(address)
end

function sockaddr_ipv4(address, port):
    return transport.sockaddr_ipv4(address, port)
end

function set_socket_option(handle, option, value):
    return transport.set_socket_option(handle, option, value)
end

function set_socket_timeout(handle, option, seconds):
    return transport.set_socket_timeout(handle, option, seconds)
end

function listen_ipv4(address, port, backlog):
    return transport.listen_ipv4(address, port, backlog)
end

function local_port(listener):
    return transport.local_port(listener)
end

function accept_client(listener):
    return transport.accept_client(listener)
end

function open_root(path):
    return transport.open_root(path)
end

function open_static(root_handle, relative_path):
    return transport.open_static(root_handle, relative_path)
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

# token podle RFC 9110 §5.6.2: 1*tchar.
TOKEN_SYMBOLS = "!#$%&'*+-.^_`|~"

function valid_token(text, limit):
    if len(text) == 0 or len(text) > limit:
        return False
    end
    for character in text:
        code = ord(character)
        if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or TOKEN_SYMBOLS.find(character) >= 0):
            return False
        end
    end
    return True
end

function valid_header_name(name):
    return valid_token(name, 64)
end

# request-target bez mezer a řídicích znaků (RFC 9112 §3.2): jen VCHAR.
function valid_target(target):
    for character in target:
        code = ord(character)
        if code <= 32 or code >= 127:
            return False
        end
    end
    return True
end

# field-value bez CR, LF a NUL (RFC 9110 §5.5); TAB a mezera jsou povolené.
function valid_field_value(value):
    for character in value:
        code = ord(character)
        if code == 13 or code == 10 or code == 0 or (code < 32 and code != 9) or code == 127:
            return False
        end
    end
    return True
end

# Odpovědi 1xx, 204 a 304 nesmějí mít tělo (RFC 9110 §6.4.1, §15.3.5, §15.4.5).
function status_without_body(status):
    return (status >= 100 and status < 200) or status == 204 or status == 304
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

# RFC 3629 well-formedness over raw bytes: no overlongs, no surrogates,
# nothing above U+10FFFF. The raw byte copy in __lsl_text_from_bytes does not
# validate, so the server checks before exposing a request body as text.
function utf8_valid(buffer):
    length = len(buffer)
    index = 0
    while index < length:
        byte = buffer[index]
        if byte < 128:
            index += 1
            continue
        end
        follow = 0
        low = 128
        high = 191
        if byte >= 194 and byte <= 223:
            follow = 1
        elif byte == 224:
            follow = 2
            low = 160
        elif (byte >= 225 and byte <= 236) or byte == 238 or byte == 239:
            follow = 2
        elif byte == 237:
            follow = 2
            high = 159
        elif byte == 240:
            follow = 3
            low = 144
        elif byte >= 241 and byte <= 243:
            follow = 3
        elif byte == 244:
            follow = 3
            high = 143
        else:
            return False
        end
        if index + follow >= length:
            return False
        end
        second = buffer[index + 1]
        if second < low or second > high:
            return False
        end
        offset = 2
        while offset <= follow:
            trailer = buffer[index + offset]
            if trailer < 128 or trailer > 191:
                return False
            end
            offset += 1
        end
        index += follow + 1
    end
    return True
end

# Read a declared request body: leftover header-buffer bytes first, then the
# socket until content_length bytes arrived. Capacity grows with the bytes
# that actually arrive, so a hostile declared Content-Length cannot allocate
# memory up front; the declared length only caps the final size.
function read_body(client, collected, finish, total, content_length):
    capacity = content_length
    if capacity > BODY_INITIAL_CAPACITY:
        capacity = BODY_INITIAL_CAPACITY
    end
    body = __lsl_byte_zeros(capacity)
    have = total - finish
    if have > content_length:
        return error_request(400, "Bad Request", "request body exceeds its declared length")
    end
    if have > 0:
        call __lsl_byte_copy(body, collected, 0, finish, have)
    end
    chunk = __lsl_byte_zeros(BODY_CHUNK_BYTES)
    while have < content_length:
        if have == capacity:
            capacity = capacity * 2
            if capacity > content_length:
                capacity = content_length
            end
            grown = __lsl_byte_zeros(capacity)
            call __lsl_byte_copy(grown, body, 0, 0, have)
            body = grown
        end
        count = __lsl_fd_read(Int(client), chunk, len(chunk))
        if count == -4:
            continue
        elif count == -11 or count == -110:
            return error_request(408, "Request Timeout", "request body timed out")
        elif count <= 0:
            return error_request(400, "Bad Request", "request body is incomplete")
        elif count > content_length - have:
            return error_request(400, "Bad Request", "request body exceeds its declared length")
        end
        if have + count > capacity:
            capacity = have + count
            if capacity * 2 <= content_length:
                capacity = capacity * 2
            end
            grown = __lsl_byte_zeros(capacity)
            call __lsl_byte_copy(grown, body, 0, 0, have)
            body = grown
        end
        call __lsl_byte_copy(body, chunk, have, 0, count)
        have += count
    end
    if capacity != content_length:
        exact = __lsl_byte_zeros(content_length)
        call __lsl_byte_copy(exact, body, 0, 0, content_length)
        body = exact
    end
    return {"ok": True, "data": body}
end

function read_request(client, allow_body):
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
    # split(CRLF) keeps the two empty entries after the terminating CRLFCRLF:
    # request line + up to 64 fields + two terminators.
    if len(lines) < 3 or len(lines) > MAX_HEADER_COUNT + 3:
        return error_request(400, "Bad Request", "request header has an invalid line count")
    end
    request_line = lines[0].split(" ")
    if len(request_line) != 3 or request_line[0] == "" or request_line[1] == "":
        return error_request(400, "Bad Request", "request line is invalid")
    end
    method = String(request_line[0])
    target = String(request_line[1])
    version = String(request_line[2])
    if not valid_token(method, 32):
        return error_request(400, "Bad Request", "request method is invalid")
    elif not valid_target(target):
        return error_request(400, "Bad Request", "request target contains an invalid character")
    elif version != "HTTP/1.1" and version != "HTTP/1.0":
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
        raw_value = line[separator + 1:len(line)]
        value = raw_value.strip()
        if not valid_field_value(raw_value):
            return error_request(400, "Bad Request", "header value contains CR, LF or a control character")
        end
        if name in headers:
            # RFC 9110 §5.3: opakované řádky se slučují čárkou (Cookie
            # středníkem). Hlavičky rámující tělo nebo cíl se kvůli request
            # smugglingu nesmí opakovat.
            if name == "content-length" or name == "transfer-encoding" or name == "host":
                return error_request(400, "Bad Request", "duplicate header: " + name)
            elif name == "cookie":
                headers[name] = headers[name] + "; " + value
            else:
                headers[name] = headers[name] + ", " + value
            end
        else:
            headers[name] = value
        end
        line_index += 1
    end
    if version == "HTTP/1.1" and ("host" not in headers or headers["host"] == ""):
        return error_request(400, "Bad Request", "HTTP/1.1 requires a non-empty Host")
    elif "transfer-encoding" in headers:
        return error_request(400, "Bad Request", "Transfer-Encoding is not accepted")
    end
    content_length = 0
    if "content-length" in headers:
        content_length = decimal_header(headers["content-length"])
        if content_length < 0:
            return error_request(400, "Bad Request", "Content-Length is invalid")
        end
    end
    if content_length != 0 and not Bool(allow_body):
        return error_request(413, "Content Too Large", "request bodies are not accepted")
    elif BODY_LIMIT[0] > 0 and content_length > BODY_LIMIT[0]:
        return error_request(413, "Content Too Large", "request body exceeds the configured limit of " + String(BODY_LIMIT[0]) + " bytes")
    end
    body = ByteArray()
    if content_length > 0:
        if "expect" in headers and headers["expect"].lower() == "100-continue":
            interim = "HTTP/1.1 100 Continue" + chr(13) + chr(10) + chr(13) + chr(10)
            if socket_write(client, text_bytes(interim)) < 0:
                return error_request(400, "Bad Request", "client closed before sending the body")
            end
        end
        filled = read_body(client, collected, finish, total, content_length)
        if not filled["ok"]:
            return filled
        end
        body = filled["data"]
    end
    body_text = None
    if utf8_valid(body):
        body_text = __lsl_text_from_bytes(body, 0, len(body))
    end
    return {"ok": True, "method": method, "target": target, "version": version, "headers": headers, "body": body, "body_text": body_text}
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
    elif status == 201:
        return "Created"
    elif status == 202:
        return "Accepted"
    elif status == 204:
        return "No Content"
    elif status == 301:
        return "Moved Permanently"
    elif status == 302:
        return "Found"
    elif status == 303:
        return "See Other"
    elif status == 304:
        return "Not Modified"
    elif status == 307:
        return "Temporary Redirect"
    elif status == 308:
        return "Permanent Redirect"
    elif status == 401:
        return "Unauthorized"
    elif status == 409:
        return "Conflict"
    elif status == 422:
        return "Unprocessable Content"
    elif status == 429:
        return "Too Many Requests"
    elif status == 502:
        return "Bad Gateway"
    elif status == 503:
        return "Service Unavailable"
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
    no_body = status_without_body(Int(status))
    header = "HTTP/1.1 " + String(status) + " " + String(reason) + chr(13) + chr(10)
    if not no_body:
        header += "Content-Length: " + String(len(payload)) + chr(13) + chr(10)
        header += "Content-Type: " + mime + chr(13) + chr(10)
    end
    header += "Connection: close" + chr(13) + chr(10)
    header += "X-Content-Type-Options: nosniff" + chr(13) + chr(10)
    header += "Referrer-Policy: no-referrer" + chr(13) + chr(10) + chr(13) + chr(10)
    header_bytes = text_bytes(header)
    result = socket_write(client, header_bytes)
    if result >= 0 and not no_body and not Bool(head_only) and len(payload) > 0:
        result = socket_write(client, payload)
    end
    return result
end

# Streamovaná odpověď: hlavičky hned, tělo po částech přes stream_write.
# HTTP/1.1 používá chunked kódování, HTTP/1.0 tělo ukončí zavřením spojení.
function send_stream_head(client, status, reason, body_type, chunked):
    mime = String(body_type)
    if not valid_content_type(mime):
        mime = "application/octet-stream"
    end
    header = "HTTP/1.1 " + String(status) + " " + String(reason) + chr(13) + chr(10)
    if chunked:
        header += "Transfer-Encoding: chunked" + chr(13) + chr(10)
    end
    header += "Content-Type: " + mime + chr(13) + chr(10)
    header += "Cache-Control: no-cache" + chr(13) + chr(10)
    header += "Connection: close" + chr(13) + chr(10)
    header += "X-Accel-Buffering: no" + chr(13) + chr(10)
    header += "X-Content-Type-Options: nosniff" + chr(13) + chr(10)
    header += "Referrer-Policy: no-referrer" + chr(13) + chr(10) + chr(13) + chr(10)
    return socket_write(client, text_bytes(header))
end

function hex_length(value):
    digits = "0123456789abcdef"
    if value == 0:
        return "0"
    end
    text = ""
    rest = value
    while rest > 0:
        text = digits[rest % 16] + text
        rest = rest // 16
    end
    return text
end

# Pošle část streamované odpovědi; False, když klient spojení zavřel.
function stream_write(stream, data):
    if type(stream) != "Dictionary" or not ("client" in stream):
        Error(TypeError: "stream_write expects the stream passed to the response stream function")
    end
    state = stream["state"]
    if state[0] != 0:
        return False
    end
    payload = data
    if type(payload) == "String":
        payload = text_bytes(payload)
    elif type(payload) != "ByteArray":
        Error(TypeError: "stream data must be String or ByteArray, got " + type(payload))
    end
    if len(payload) == 0:
        return True
    end
    client = stream["client"]
    if stream["chunked"]:
        if socket_write(client, text_bytes(hex_length(len(payload)) + chr(13) + chr(10))) < 0:
            state[0] = 1
            return False
        end
    end
    if socket_write(client, payload) < 0:
        state[0] = 1
        return False
    end
    if stream["chunked"]:
        if socket_write(client, text_bytes(chr(13) + chr(10))) < 0:
            state[0] = 1
            return False
        end
    end
    return True
end

# Jedna událost Server-Sent Events; víceřádková data dostanou více řádků data:.
function sse_event(stream, data, event=None):
    text = ""
    if event != None:
        name = String(event)
        if name.find(chr(10)) >= 0 or name.find(chr(13)) >= 0:
            Error(ValueError: "SSE event name cannot contain line breaks")
        end
        text += "event: " + name + chr(10)
    end
    for line in String(data).replace(chr(13) + chr(10), chr(10)).replace(chr(13), chr(10)).split(chr(10)):
        text += "data: " + line + chr(10)
    end
    return stream_write(stream, text + chr(10))
end

function serve_stream(client, request, response):
    if status_without_body(Int(response["status"])):
        # Status bez těla: jen hlavičky, stream funkce se nevolá.
        return send_response(client, response["status"], response["reason"], "", response["content_type"], True)
    end
    chunked = request["version"] == "HTTP/1.1"
    if send_stream_head(client, response["status"], response["reason"], response["content_type"], chunked) < 0:
        return -1
    end
    if request["method"] == "HEAD":
        return 0
    end
    state = IntArray()
    state.append(0)
    stream = {"client": client, "chunked": chunked, "request": request, "state": state}
    producer = response["stream"]
    failed = False
    try:
        call producer(stream)
    else:
        failed = True
    end
    # Po chybě producenta se stream neukončí řádně (bez koncového chunku),
    # klient tak pozná neúplnou odpověď místo tiše zkráceného těla.
    if chunked and not failed and state[0] == 0:
        if socket_write(client, text_bytes("0" + chr(13) + chr(10) + chr(13) + chr(10))) < 0:
            return -1
        end
    end
    return 0
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
    elif "stream" in value:
        if type(value["stream"]) != "Function":
            return {"status": 500, "reason": "Internal Server Error", "body": "500 Internal Server Error" + chr(10), "content_type": "text/plain; charset=utf-8"}
        end
        return {"status": status, "reason": reason, "body": "", "content_type": mime, "stream": value["stream"]}
    elif type(body) != "String" and type(body) != "ByteArray":
        return {"status": 500, "reason": "Internal Server Error", "body": "500 Internal Server Error" + chr(10), "content_type": "text/plain; charset=utf-8"}
    elif BODY_LIMIT[0] > 0 and ((type(body) == "String" and __lsl_text_byte_length(String(body)) > BODY_LIMIT[0]) or (type(body) == "ByteArray" and len(body) > BODY_LIMIT[0])):
        return {"status": 500, "reason": "Internal Server Error", "body": "500 Internal Server Error" + chr(10), "content_type": "text/plain; charset=utf-8"}
    end
    return {"status": status, "reason": reason, "body": body, "content_type": mime}
end

# Obslouží jedno přijaté spojení a zavře ho.
function serve_client(client, root_handle, handler):
    request = read_request(client, handler != None)
    if not request["ok"]:
        call send_error(client, request)
    else:
        if handler == None:
            response = static_response(root_handle, request)
        else:
            # Application failures are request-local. Always close the
            # client and keep the bounded listener usable for later work.
            try:
                response = normalize_app_response(handler(request))
            else:
                response = {"status": 500, "reason": "Internal Server Error", "body": "500 Internal Server Error" + chr(10), "content_type": "text/plain; charset=utf-8"}
            end
        end
        head_only = request["method"] == "HEAD"
        if "stream" in response:
            call serve_stream(client, request, response)
        else:
            call send_response(client, response["status"], response["reason"], response["body"], response["content_type"], head_only)
        end
    end
    call fd.close(client)
end

# Worker pool: vlákna přijímají spojení ze sdíleného listeneru, takže pomalý
# nebo streamovaný požadavek neblokuje ostatní. Stav pool je v modulu (vlákno
# nemá parametry); běží nejvýš jeden pool najednou.
POOL_HANDLER = [None]
POOL_STATE = IntArray()
for pool_slot in rang(6):
    POOL_STATE.append(0)
end
# POOL_STATE: 0 listener, 1 limit, 2 vydané lístky, 3 obsloužené, 4 hotová
# vlákna, 5 stop/zámek pool (1 = běží)

function pool_worker():
    listener = POOL_STATE[0]
    handler = POOL_HANDLER[0]
    loop:
        if atomic_add(POOL_STATE, 5, 0) == 2:
            break
        end
        limit = POOL_STATE[1]
        if limit > 0:
            ticket = atomic_add(POOL_STATE, 2, 1)
            if ticket >= limit:
                break
            end
        end
        client = -11
        while client == -11 or client == -4:
            # Accept s časovým limitem kontroluje zastavení pool.
            if atomic_add(POOL_STATE, 5, 0) == 2:
                break
            end
            client = accept_client(listener)
        end
        if client < 0:
            break
        end
        call serve_client(client, -1, handler)
        call atomic_add(POOL_STATE, 3, 1)
    end
    call atomic_add(POOL_STATE, 4, 1)
    return None
end

function serve_workers(handler, address, port, workers, maximum_requests):
    if type(handler) != "Function":
        Error(TypeError: "HTTP handler must be a Function")
    elif type(workers) != "Int" or workers < 1 or workers > 64:
        Error(ValueError: "worker count must be an Int between 1 and 64")
    elif maximum_requests < 0:
        Error(ServerError: "maximum request count cannot be negative")
    end
    listener = listen_ipv4(address, port, 128)
    print "LSL HTTP server listening on http://" + String(address) + ":" + String(port) + "/ with " + String(workers) + " workers"
    return serve_listener_workers(listener, handler, workers, maximum_requests)
end

function serve_listener_workers(listener, handler, workers, maximum_requests):
    if atomic_cas(POOL_STATE, 5, 0, 1) != 0:
        Error(ServerError: "another HTTP worker pool is already running")
    end
    call set_socket_timeout(listener, SO_RCVTIMEO, 1)
    POOL_HANDLER[0] = handler
    POOL_STATE[0] = listener
    POOL_STATE[1] = maximum_requests
    POOL_STATE[2] = 0
    POOL_STATE[3] = 0
    POOL_STATE[4] = 0
    threads = []
    for index in rang(workers):
        tid = thread_spawn(pool_worker)
        if tid < 0:
            call atomic_xchg(POOL_STATE, 5, 2)
            break
        end
        threads.append(tid)
    end
    # Hlavní vlákno uklízí paměť (gc() ve vláknech nic nedělá).
    while atomic_add(POOL_STATE, 4, 0) < len(threads):
        call time.sleep(0.05)
        call gc()
    end
    for tid in threads:
        call thread_join(tid)
    end
    served = POOL_STATE[3]
    call fd.close(listener)
    call atomic_xchg(POOL_STATE, 5, 0)
    if len(threads) < workers:
        Error(ServerError: "cannot start HTTP worker threads")
    end
    return served
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
        call serve_client(client, root_handle, handler)
        served += 1
        # Reclaim per-request garbage. The allocator's automatic heuristic
        # does not keep up with a long-running request loop, which exhausted
        # the allocator after enough requests. gc() is a no-op in worker
        # threads, so threaded listeners are unaffected; a listener on the
        # main thread stays flat.
        call gc()
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
    return transport.system_tool(primary, fallback, label)
end

function runtime_directory():
    return transport.runtime_directory()
end

function canonical_path(path, label):
    return transport.canonical_path(path, label)
end

function nginx_quote(value):
    return transport.nginx_quote(value)
end

# HTTPS intentionally delegates cryptography and protocol negotiation to the
# host's maintained nginx/OpenSSL stack. LSL supplies a private, generated
# configuration and never interpolates an unquoted caller-controlled token.
# This frontend serves static files only; application handlers should normally
# run on loopback behind the deployment's existing TLS reverse proxy.
function serve_static_tls(root, address, port, certificate, private_key, maximum_requests):
    return transport.serve_static_tls(root, address, port, certificate, private_key, maximum_requests)
end
