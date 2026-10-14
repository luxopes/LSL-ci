# macOS: HTTP server nad sockety libSystem (BSD). Adresa socketu má délku
# v prvním bajtu, SIGPIPE potlačí SO_NOSIGPIPE (MSG_NOSIGNAL macOS nemá),
# accept s limitem čeká přes poll. Statické soubory otevírá openat
# s O_NOFOLLOW_ANY (macOS 11+): jádro odmítne symbolický odkaz kdekoli
# v cestě. HTTPS obstará nginx (Homebrew, MacPorts) jako na Linuxu. Chyby
# mají hodnoty errno Linuxu jako zbytek runtime. Argumenty surových volání
# musí být Int.
load _platform as platform
load fd
load time

# Linuxová čísla systémových volání veřejné fasády na macOS neexistují.
SYS_SOCKET = -1
SYS_FSTAT = -1
SYS_SENDTO = -1
SYS_ACCEPT4 = -1
SYS_BIND = -1
SYS_LISTEN = -1
SYS_GETSOCKNAME = -1
SYS_SETSOCKOPT = -1
SYS_OPENAT2 = -1

AF_INET = 2
SOCK_STREAM = 1
SOCK_CLOEXEC = 0
SOL_SOCKET = 65535
SO_REUSEADDR = 4
SO_LINGER = 128
SO_RCVTIMEO = 4102
SO_SNDTIMEO = 4101
SO_NOSIGPIPE = 4130
MSG_NOSIGNAL = 0
POLLIN = 1

O_RDONLY = platform.O_RDONLY
O_NONBLOCK = platform.O_NONBLOCK
O_DIRECTORY = platform.O_DIRECTORY
O_CLOEXEC = platform.O_CLOEXEC
O_NOFOLLOW = platform.O_NOFOLLOW
RESOLVE_NO_MAGICLINKS = 2
RESOLVE_NO_SYMLINKS = 4
RESOLVE_BENEATH = 8
S_IFMT = 61440
S_IFREG = 32768

# Hodnoty macOS pro openat a fstat.
MAC_O_NONBLOCK = 4
MAC_O_NOFOLLOW = 256
MAC_O_DIRECTORY = 1048576
MAC_O_CLOEXEC = 16777216
MAC_O_NOFOLLOW_ANY = 536870912
F_SETFD = 2
FD_CLOEXEC = 1
STAT_BYTES = 256
STAT_MODE = 4

SOCKADDR_IN_BYTES = 16
SOCKADDR_IN_PORT = 2
SOCKADDR_IN_ADDRESS = 4
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

function get_u32(buffer, offset):
    source = ByteArray(buffer)
    return source[offset] + source[offset + 1] * 256 + source[offset + 2] * 65536 + source[offset + 3] * 16777216
end

function put_u64(buffer, offset, value):
    target = ByteArray(buffer)
    number = Int(value)
    for index in range(8):
        target[offset + index] = (number >> (index * 8)) & 255
    end
    return None
end

function data_address(buffer):
    return Int(__lsl_data_address(ByteArray(buffer)))
end

function int32(value):
    number = Int(value) & 4294967295
    if number >= 2147483648:
        number -= 4294967296
    end
    return number
end

# errno macOS -> záporné errno Linuxu (1..34 jsou stejné).
function last_error():
    code = int32(__lsl_qbe_load32(Int(__lsl_qbe_call0(__lsl_symbol("__error")))))
    if code >= 1 and code <= 34:
        return 0 - code
    end
    table = {35: 11, 36: 115, 48: 98, 54: 104, 57: 107, 60: 110, 61: 111, 62: 40, 63: 36}
    return 0 - table.get(code, 5)
end

# Výsledek int funkce: hodnota, nebo záporné errno Linuxu.
function checked(result):
    value = int32(result)
    if value == -1:
        return last_error()
    end
    return value
end

function socket_write(handle, payload):
    buffer = ByteArray(payload)
    socket = Int(handle)
    offset = 0
    remaining = len(buffer)
    while remaining > 0:
        result = Int(__lsl_qbe_call4(__lsl_symbol("send"), socket, data_address(buffer) + offset, remaining, 0))
        if result > 0:
            offset += result
            remaining -= result
        else:
            error = last_error()
            if error != -4:
                return error
            end
        end
    end
    return 0
end

# Počet bajtů, 0 na konci spojení, nebo záporné errno (-11 časový limit).
function socket_read(handle, buffer, count):
    target = ByteArray(buffer)
    amount = min(Int(count), len(target))
    result = Int(__lsl_qbe_call4(__lsl_symbol("recv"), Int(handle), data_address(target), amount, 0))
    if result >= 0:
        return result
    end
    return last_error()
end

function socket_close(handle):
    call fd.close(handle)
    return None
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

# sockaddr_in BSD: +0 délka, +1 rodina, +2 port (big-endian), +4 adresa.
function sockaddr_ipv4(address, port):
    number = Int(port)
    if number < 0 or number > 65535:
        Error(ServerError: "port must be between 0 and 65535")
    end
    octets = ipv4_octets(address)
    result = __lsl_byte_zeros(SOCKADDR_IN_BYTES)
    result[0] = SOCKADDR_IN_BYTES
    result[1] = AF_INET
    result[SOCKADDR_IN_PORT] = number // 256
    result[SOCKADDR_IN_PORT + 1] = number % 256
    index = 0
    while index < 4:
        result[SOCKADDR_IN_ADDRESS + index] = octets[index]
        index += 1
    end
    return result
end

function set_socket_option(handle, option, value):
    payload = __lsl_byte_zeros(4)
    call put_u32(payload, 0, value)
    return checked(__lsl_qbe_call5(__lsl_symbol("setsockopt"), Int(handle), SOL_SOCKET, Int(option), data_address(payload), 4))
end

# struct timeval macOS: +0 sekundy (64 bitů), +8 mikrosekundy (32 bitů).
function set_socket_timeout(handle, option, seconds):
    timeout = __lsl_byte_zeros(16)
    call put_u64(timeout, 0, seconds)
    return checked(__lsl_qbe_call5(__lsl_symbol("setsockopt"), Int(handle), SOL_SOCKET, Int(option), data_address(timeout), 16))
end

# Časový limit SO_RCVTIMEO socketu v ms (0 = bez limitu).
function receive_timeout(handle):
    timeout = __lsl_byte_zeros(16)
    size = __lsl_byte_zeros(4)
    call put_u32(size, 0, 16)
    if checked(__lsl_qbe_call5(__lsl_symbol("getsockopt"), Int(handle), SOL_SOCKET, SO_RCVTIMEO, data_address(timeout), data_address(size))) != 0:
        return 0
    end
    return get_u32(timeout, 0) * 1000 + get_u32(timeout, 8) // 1000
end

function close_on_exec(handle):
    call __lsl_qbe_call3(__lsl_symbol("lsl_arch_fcntl"), Int(handle), F_SETFD, FD_CLOEXEC)
    return None
end

function listen_ipv4(address, port, backlog):
    endpoint = sockaddr_ipv4(address, port)
    handle = Int(checked(__lsl_qbe_call3(__lsl_symbol("socket"), AF_INET, SOCK_STREAM, 0)))
    if handle < 0:
        Error(ServerError: "socket failed (" + String(handle) + ")")
    end
    call close_on_exec(handle)
    if set_socket_option(handle, SO_REUSEADDR, 1) < 0:
        call fd.close(handle)
        Error(ServerError: "cannot set SO_REUSEADDR")
    end
    if checked(__lsl_qbe_call3(__lsl_symbol("bind"), handle, data_address(endpoint), len(endpoint))) < 0:
        call fd.close(handle)
        Error(ServerError: "cannot bind " + String(address) + ":" + String(port))
    end
    queue = Int(backlog)
    if queue < 1:
        queue = 1
    elif queue > 4096:
        queue = 4096
    end
    if checked(__lsl_qbe_call2(__lsl_symbol("listen"), handle, queue)) < 0:
        call fd.close(handle)
        Error(ServerError: "listen failed")
    end
    return handle
end

function local_port(listener):
    endpoint = __lsl_byte_zeros(SOCKADDR_IN_BYTES)
    endpoint_length = __lsl_byte_zeros(4)
    call put_u32(endpoint_length, 0, SOCKADDR_IN_BYTES)
    result = checked(__lsl_qbe_call3(__lsl_symbol("getsockname"), Int(listener), data_address(endpoint), data_address(endpoint_length)))
    if result < 0 or endpoint[1] != AF_INET:
        Error(ServerError: "getsockname failed")
    end
    return endpoint[SOCKADDR_IN_PORT] * 256 + endpoint[SOCKADDR_IN_PORT + 1]
end

# Accept s limitem SO_RCVTIMEO naslouchajícího socketu (-11 po vypršení),
# klient dostane limity čtení a zápisu a SO_NOSIGPIPE.
function accept_client(listener):
    socket = Int(listener)
    timeout = receive_timeout(socket)
    if timeout > 0:
        # struct pollfd: +0 fd, +4 events, +6 revents.
        descriptor = __lsl_byte_zeros(8)
        call put_u32(descriptor, 0, socket)
        descriptor[4] = POLLIN
        ready = checked(__lsl_qbe_call3(__lsl_symbol("poll"), data_address(descriptor), 1, timeout))
        if ready == 0:
            return -11
        elif ready < 0:
            return ready
        end
    end
    client = Int(checked(__lsl_qbe_call3(__lsl_symbol("accept"), socket, 0, 0)))
    if client < 0:
        return client
    end
    call close_on_exec(client)
    receive = set_socket_timeout(client, SO_RCVTIMEO, SOCKET_TIMEOUT_SECONDS)
    send = set_socket_timeout(client, SO_SNDTIMEO, SOCKET_TIMEOUT_SECONDS)
    quiet = set_socket_option(client, SO_NOSIGPIPE, 1)
    if receive < 0 or send < 0 or quiet < 0:
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

# Soubor pod kořenem: relativní cesta bez "..", bez symbolického odkazu
# kdekoli v cestě (O_NOFOLLOW_ANY), jen obyčejný soubor. HANDLE, nebo
# záporné errno.
function open_static(root_handle, relative_path):
    path = cstring(relative_path)
    text = String(relative_path)
    if text.startswith("/"):
        return -22
    end
    for component in text.split("/"):
        if component == "..":
            return -22
        end
    end
    flags = MAC_O_NONBLOCK + MAC_O_CLOEXEC + MAC_O_NOFOLLOW + MAC_O_NOFOLLOW_ANY
    handle = Int(checked(__lsl_qbe_call4(__lsl_symbol("lsl_arch_openat"), Int(root_handle), data_address(path), flags, 0)))
    if handle < 0:
        return handle
    end
    metadata = __lsl_byte_zeros(STAT_BYTES)
    if checked(__lsl_qbe_call2(__lsl_symbol("lsl_arch_fstat"), handle, data_address(metadata))) < 0 or ((metadata[STAT_MODE] + metadata[STAT_MODE + 1] * 256) & S_IFMT) != S_IFREG:
        call fd.close(handle)
        return -22
    end
    return handle
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
    process = String(int32(__lsl_qbe_call0(__lsl_symbol("getpid"))))
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
    # BSD realpath nezná -e; neexistující cestu odmítne i bez něj.
    realpath = system_tool("/bin/realpath", "/usr/bin/realpath", "realpath")
    result = capture_clean(realpath, ["--", String(path)])
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

# nginx z Homebrew (Apple Silicon, Intel) nebo MacPorts.
function nginx_tool():
    for candidate in ["/opt/homebrew/bin/nginx", "/usr/local/bin/nginx", "/opt/local/sbin/nginx"]:
        if exists(candidate):
            return candidate
        end
    end
    Error(ServerError: "trusted nginx executable is required (Homebrew or MacPorts)")
end


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
    nginx = nginx_tool()
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

function interrupted(result):
    return result == -4
end
