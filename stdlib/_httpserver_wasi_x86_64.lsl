# WebAssembly (WASI): HTTP server potřebuje sockety, které WASI preview1
# nemá. Konstanty zůstávají kvůli fasádě, operace hlásí chybu.

SYS_SOCKET = -1
SYS_FSTAT = -1
SYS_SENDTO = -1
SYS_ACCEPT4 = -1
SYS_BIND = -1
SYS_LISTEN = -1
SYS_GETSOCKNAME = -1
SYS_SETSOCKOPT = -1
SYS_OPENAT2 = -1
AF_INET = -1
SOCK_STREAM = -1
SOCK_CLOEXEC = -1
SOL_SOCKET = -1
SO_REUSEADDR = -1
SO_LINGER = -1
SO_RCVTIMEO = -1
SO_SNDTIMEO = -1
MSG_NOSIGNAL = -1
O_RDONLY = -1
O_NONBLOCK = -1
O_DIRECTORY = -1
O_CLOEXEC = -1
O_NOFOLLOW = -1
RESOLVE_NO_MAGICLINKS = -1
RESOLVE_NO_SYMLINKS = -1
RESOLVE_BENEATH = -1
S_IFMT = -1
S_IFREG = -1
SOCKET_TIMEOUT_SECONDS = -1

function put_u32(buffer, offset, value):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function get_u32(buffer, offset):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function put_u64(buffer, offset, value):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function data_address(buffer):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function socket_write(handle, payload):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function socket_read(handle, buffer, count):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function socket_close(handle):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function cstring(value):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function ipv4_octets(address):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function sockaddr_ipv4(address, port):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function set_socket_option(handle, option, value):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function set_socket_timeout(handle, option, seconds):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function listen_ipv4(address, port, backlog):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function local_port(listener):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function accept_client(listener):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function open_root(path):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function open_static(root_handle, relative_path):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function system_tool(primary, fallback, label):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function runtime_directory():
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function canonical_path(path, label):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function nginx_quote(value):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function serve_static_tls(root, address, port, certificate, private_key, maximum_requests):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function interrupted(result):
    return result == -4
end

function socket_read(handle, buffer, count):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end

function socket_close(handle):
    Error(ServerError: "HTTP server sockets are not available in WebAssembly (WASI)")
end
