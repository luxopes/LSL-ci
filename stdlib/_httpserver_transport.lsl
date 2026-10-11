# Veřejné API; operace hostitele poskytuje modul vybraný cílem.

load _httpserver_linux_x86_64 as implementation

SYS_SOCKET = implementation.SYS_SOCKET
SYS_FSTAT = implementation.SYS_FSTAT
SYS_SENDTO = implementation.SYS_SENDTO
SYS_ACCEPT4 = implementation.SYS_ACCEPT4
SYS_BIND = implementation.SYS_BIND
SYS_LISTEN = implementation.SYS_LISTEN
SYS_GETSOCKNAME = implementation.SYS_GETSOCKNAME
SYS_SETSOCKOPT = implementation.SYS_SETSOCKOPT
SYS_OPENAT2 = implementation.SYS_OPENAT2
AF_INET = implementation.AF_INET
SOCK_STREAM = implementation.SOCK_STREAM
SOCK_CLOEXEC = implementation.SOCK_CLOEXEC
SOL_SOCKET = implementation.SOL_SOCKET
SO_REUSEADDR = implementation.SO_REUSEADDR
SO_LINGER = implementation.SO_LINGER
SO_RCVTIMEO = implementation.SO_RCVTIMEO
SO_SNDTIMEO = implementation.SO_SNDTIMEO
MSG_NOSIGNAL = implementation.MSG_NOSIGNAL
O_RDONLY = implementation.O_RDONLY
O_NONBLOCK = implementation.O_NONBLOCK
O_DIRECTORY = implementation.O_DIRECTORY
O_CLOEXEC = implementation.O_CLOEXEC
O_NOFOLLOW = implementation.O_NOFOLLOW
RESOLVE_NO_MAGICLINKS = implementation.RESOLVE_NO_MAGICLINKS
RESOLVE_NO_SYMLINKS = implementation.RESOLVE_NO_SYMLINKS
RESOLVE_BENEATH = implementation.RESOLVE_BENEATH
S_IFMT = implementation.S_IFMT
S_IFREG = implementation.S_IFREG
SOCKET_TIMEOUT_SECONDS = implementation.SOCKET_TIMEOUT_SECONDS

function put_u32(buffer, offset, value):
    return implementation.put_u32(buffer, offset, value)
end

function get_u32(buffer, offset):
    return implementation.get_u32(buffer, offset)
end

function put_u64(buffer, offset, value):
    return implementation.put_u64(buffer, offset, value)
end

function data_address(buffer):
    return implementation.data_address(buffer)
end

function socket_write(handle, payload):
    return implementation.socket_write(handle, payload)
end

function cstring(value):
    return implementation.cstring(value)
end

function ipv4_octets(address):
    return implementation.ipv4_octets(address)
end

function sockaddr_ipv4(address, port):
    return implementation.sockaddr_ipv4(address, port)
end

function set_socket_option(handle, option, value):
    return implementation.set_socket_option(handle, option, value)
end

function set_socket_timeout(handle, option, seconds):
    return implementation.set_socket_timeout(handle, option, seconds)
end

function listen_ipv4(address, port, backlog):
    return implementation.listen_ipv4(address, port, backlog)
end

function local_port(listener):
    return implementation.local_port(listener)
end

function accept_client(listener):
    return implementation.accept_client(listener)
end

function open_root(path):
    return implementation.open_root(path)
end

function open_static(root_handle, relative_path):
    return implementation.open_static(root_handle, relative_path)
end

function system_tool(primary, fallback, label):
    return implementation.system_tool(primary, fallback, label)
end

function runtime_directory():
    return implementation.runtime_directory()
end

function canonical_path(path, label):
    return implementation.canonical_path(path, label)
end

function nginx_quote(value):
    return implementation.nginx_quote(value)
end

function serve_static_tls(root, address, port, certificate, private_key, maximum_requests):
    return implementation.serve_static_tls(root, address, port, certificate, private_key, maximum_requests)
end

function interrupted(result):
    return implementation.interrupted(result)
end
