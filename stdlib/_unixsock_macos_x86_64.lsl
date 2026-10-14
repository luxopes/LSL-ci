# macOS: sockety Unixu s předáváním deskriptorů (SCM_RIGHTS, memfd) zatím jen
# pro Linux. Konstanty zůstávají kvůli veřejné fasádě, operace hlásí chybu.


SYS_READ = -1
SYS_WRITE = -1
SYS_CLOSE = -1
SYS_LSEEK = -1
SYS_FCNTL = -1
SYS_FTRUNCATE = -1
SYS_UNLINK = -1
SYS_SOCKET = -1
SYS_ACCEPT4 = -1
SYS_SENDMSG = -1
SYS_RECVMSG = -1
SYS_BIND = -1
SYS_LISTEN = -1
SYS_SOCKETPAIR = -1
SYS_MEMFD_CREATE = -1
SYS_MUNMAP = -1
SYS_PIPE2 = -1
SYS_CHMOD = -1
SYS_CHOWN = -1
SYS_FCHMODAT = -1
SYS_FCHOWNAT = -1
AF_UNIX = -1
SOCK_STREAM = -1
SOCK_NONBLOCK = -1
SOCK_CLOEXEC = -1
SOL_SOCKET = -1
SCM_RIGHTS = -1
MSG_DONTWAIT = -1
MSG_CMSG_CLOEXEC = -1
F_SETFL = -1
O_NONBLOCK = -1
O_CLOEXEC = -1
MFD_CLOEXEC = -1

function u_put32(buffer, offset, value):
    Error(OSError: "unixsock: Unix sockets with descriptor passing are not yet available on macOS")
end

function u_put64(buffer, offset, value):
    Error(OSError: "unixsock: Unix sockets with descriptor passing are not yet available on macOS")
end

function u_get32(buffer, offset):
    Error(OSError: "unixsock: Unix sockets with descriptor passing are not yet available on macOS")
end

function u_get64(buffer, offset):
    Error(OSError: "unixsock: Unix sockets with descriptor passing are not yet available on macOS")
end

function u_address(buffer):
    Error(OSError: "unixsock: Unix sockets with descriptor passing are not yet available on macOS")
end

function socket_path(path):
    Error(OSError: "unixsock: Unix sockets with descriptor passing are not yet available on macOS")
end

function sockaddr_un(path):
    Error(OSError: "unixsock: Unix sockets with descriptor passing are not yet available on macOS")
end

function listen_unix(path, backlog):
    Error(OSError: "unixsock: Unix sockets with descriptor passing are not yet available on macOS")
end

function chmod_path(path, mode):
    Error(OSError: "unixsock: Unix sockets with descriptor passing are not yet available on macOS")
end

function chown_path(path, user, group):
    Error(OSError: "unixsock: Unix sockets with descriptor passing are not yet available on macOS")
end

function set_nonblocking(handle):
    Error(OSError: "unixsock: Unix sockets with descriptor passing are not yet available on macOS")
end

function accept_unix(server):
    Error(OSError: "unixsock: Unix sockets with descriptor passing are not yet available on macOS")
end

function close_fd(handle):
    Error(OSError: "unixsock: Unix sockets with descriptor passing are not yet available on macOS")
end

function memfd(name, size):
    Error(OSError: "unixsock: Unix sockets with descriptor passing are not yet available on macOS")
end

function send_fd(handle, payload, count, descriptor):
    Error(OSError: "unixsock: Unix sockets with descriptor passing are not yet available on macOS")
end

function send_bytes(handle, payload, count):
    Error(OSError: "unixsock: Unix sockets with descriptor passing are not yet available on macOS")
end

function send_from_fd(handle, payload, offset, count, descriptor):
    Error(OSError: "unixsock: Unix sockets with descriptor passing are not yet available on macOS")
end

function send_from(handle, payload, offset, count):
    Error(OSError: "unixsock: Unix sockets with descriptor passing are not yet available on macOS")
end

function munmap(address, size):
    Error(OSError: "unixsock: Unix sockets with descriptor passing are not yet available on macOS")
end

function pipe_nonblock():
    Error(OSError: "unixsock: Unix sockets with descriptor passing are not yet available on macOS")
end

function recv_fds(handle, payload, count, fds):
    Error(OSError: "unixsock: Unix sockets with descriptor passing are not yet available on macOS")
end
