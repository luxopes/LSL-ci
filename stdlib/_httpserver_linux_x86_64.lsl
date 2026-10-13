load _platform as platform
load fd
load time

SYS_SOCKET = platform.SYS_SOCKET
SYS_FSTAT = platform.SYS_FSTAT
SYS_SENDTO = platform.SYS_SENDTO
SYS_ACCEPT4 = platform.SYS_ACCEPT4
SYS_BIND = platform.SYS_BIND
SYS_LISTEN = platform.SYS_LISTEN
SYS_GETSOCKNAME = platform.SYS_GETSOCKNAME
SYS_SETSOCKOPT = platform.SYS_SETSOCKOPT
SYS_OPENAT2 = platform.SYS_OPENAT2

AF_INET = platform.AF_INET
SOCK_STREAM = platform.SOCK_STREAM
SOCK_CLOEXEC = platform.SOCK_CLOEXEC
SOL_SOCKET = platform.SOL_SOCKET
SO_REUSEADDR = platform.SO_REUSEADDR
SO_LINGER = platform.SO_LINGER
SO_RCVTIMEO = platform.SO_RCVTIMEO
SO_SNDTIMEO = platform.SO_SNDTIMEO
MSG_NOSIGNAL = platform.MSG_NOSIGNAL

O_RDONLY = platform.O_RDONLY
O_NONBLOCK = platform.O_NONBLOCK
O_DIRECTORY = platform.O_DIRECTORY
O_CLOEXEC = platform.O_CLOEXEC
O_NOFOLLOW = platform.O_NOFOLLOW
RESOLVE_NO_MAGICLINKS = platform.RESOLVE_NO_MAGICLINKS
RESOLVE_NO_SYMLINKS = platform.RESOLVE_NO_SYMLINKS
RESOLVE_BENEATH = platform.RESOLVE_BENEATH
S_IFMT = platform.S_IFMT
S_IFREG = platform.S_IFREG

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

function socket_write(handle, payload):
    buffer = ByteArray(payload)
    offset = 0
    remaining = len(buffer)
    while remaining > 0:
        result = __lsl_syscall6(SYS_SENDTO, Int(handle), data_address(buffer) + offset, remaining, MSG_NOSIGNAL, 0, 0)
        if result > 0:
            offset += result
            remaining -= result
        elif result == -platform.EINTR:
            continue
        else:
            return result
        end
    end
    return 0
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
    result = __lsl_byte_zeros(platform.SOCKADDR_IN_BYTES)
    result[0] = AF_INET
    result[1] = 0
    result[platform.SOCKADDR_IN_PORT] = number // 256
    result[platform.SOCKADDR_IN_PORT + 1] = number % 256
    index = 0
    while index < 4:
        result[platform.SOCKADDR_IN_ADDRESS + index] = octets[index]
        index += 1
    end
    return result
end

function set_socket_option(handle, option, value):
    payload = __lsl_byte_zeros(platform.INT_BYTES)
    call put_u32(payload, 0, value)
    return __lsl_syscall6(SYS_SETSOCKOPT, Int(handle), SOL_SOCKET, Int(option), data_address(payload), platform.INT_BYTES, 0)
end

function set_socket_timeout(handle, option, seconds):
    timeout = __lsl_byte_zeros(platform.TIMEVAL_BYTES)
    call put_u64(timeout, platform.TIMEVAL_SECONDS, seconds)
    return __lsl_syscall6(SYS_SETSOCKOPT, Int(handle), SOL_SOCKET, Int(option), data_address(timeout), platform.TIMEVAL_BYTES, 0)
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
    endpoint = __lsl_byte_zeros(platform.SOCKADDR_IN_BYTES)
    endpoint_length = __lsl_byte_zeros(platform.INT_BYTES)
    call put_u32(endpoint_length, 0, platform.SOCKADDR_IN_BYTES)
    result = __lsl_syscall(SYS_GETSOCKNAME, Int(listener), data_address(endpoint), data_address(endpoint_length), 0)
    if result < 0 or endpoint[0] != AF_INET:
        Error(ServerError: "getsockname failed")
    end
    return endpoint[platform.SOCKADDR_IN_PORT] * 256 + endpoint[platform.SOCKADDR_IN_PORT + 1]
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
        return -platform.EINVAL
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
    how = __lsl_byte_zeros(platform.OPEN_HOW_BYTES)
    # O_NONBLOCK prevents a named pipe in an otherwise valid document root
    # from hanging the single-threaded server before it can inspect the file.
    call put_u64(how, platform.OPEN_HOW_FLAGS, O_RDONLY + O_NONBLOCK + O_CLOEXEC + O_NOFOLLOW)
    call put_u64(how, platform.OPEN_HOW_RESOLVE, RESOLVE_NO_MAGICLINKS + RESOLVE_NO_SYMLINKS + RESOLVE_BENEATH)
    handle = __lsl_syscall(SYS_OPENAT2, Int(root_handle), data_address(path), data_address(how), platform.OPEN_HOW_BYTES)
    if handle < 0:
        return handle
    end
    metadata = __lsl_byte_zeros(platform.STAT_BYTES)
    if __lsl_syscall(SYS_FSTAT, handle, data_address(metadata), 0, 0) < 0 or (get_u32(metadata, platform.STAT_MODE) & S_IFMT) != S_IFREG:
        call fd.close(handle)
        return -platform.EINVAL
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
    process = String(__lsl_syscall(platform.SYS_GETPID, 0, 0, 0, 0))
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

function interrupted(result):
    return result == -platform.EINTR
end
