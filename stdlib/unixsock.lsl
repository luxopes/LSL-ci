# Unix-domain sockets with file-descriptor passing, in pure LSL on top of
# the raw syscall builtin. This is what a display server needs and a plain
# fd wrapper cannot express: clients hand over shared-memory buffers as
# descriptors inside the control message of sendmsg/recvmsg (SCM_RIGHTS).
#
# Everything here builds the kernel's structures (sockaddr_un, iovec,
# msghdr, cmsghdr) in ByteArrays and passes their data addresses, so no C
# helper and no libc are involved.

# Veřejné API; operace hostitele poskytuje modul vybraný cílem.

load _unixsock_platform as implementation

SYS_READ = implementation.SYS_READ
SYS_WRITE = implementation.SYS_WRITE
SYS_CLOSE = implementation.SYS_CLOSE
SYS_LSEEK = implementation.SYS_LSEEK
SYS_FCNTL = implementation.SYS_FCNTL
SYS_FTRUNCATE = implementation.SYS_FTRUNCATE
SYS_UNLINK = implementation.SYS_UNLINK
SYS_SOCKET = implementation.SYS_SOCKET
SYS_ACCEPT4 = implementation.SYS_ACCEPT4
SYS_SENDMSG = implementation.SYS_SENDMSG
SYS_RECVMSG = implementation.SYS_RECVMSG
SYS_BIND = implementation.SYS_BIND
SYS_LISTEN = implementation.SYS_LISTEN
SYS_SOCKETPAIR = implementation.SYS_SOCKETPAIR
SYS_MEMFD_CREATE = implementation.SYS_MEMFD_CREATE
SYS_MUNMAP = implementation.SYS_MUNMAP
SYS_PIPE2 = implementation.SYS_PIPE2
SYS_CHMOD = implementation.SYS_CHMOD
SYS_CHOWN = implementation.SYS_CHOWN
AF_UNIX = implementation.AF_UNIX
SOCK_STREAM = implementation.SOCK_STREAM
SOCK_NONBLOCK = implementation.SOCK_NONBLOCK
SOCK_CLOEXEC = implementation.SOCK_CLOEXEC
SOL_SOCKET = implementation.SOL_SOCKET
SCM_RIGHTS = implementation.SCM_RIGHTS
MSG_DONTWAIT = implementation.MSG_DONTWAIT
MSG_CMSG_CLOEXEC = implementation.MSG_CMSG_CLOEXEC
F_SETFL = implementation.F_SETFL
O_NONBLOCK = implementation.O_NONBLOCK
O_CLOEXEC = implementation.O_CLOEXEC
MFD_CLOEXEC = implementation.MFD_CLOEXEC

function u_put32(buffer, offset, value):
    return implementation.u_put32(buffer, offset, value)
end

function u_put64(buffer, offset, value):
    return implementation.u_put64(buffer, offset, value)
end

function u_get32(buffer, offset):
    return implementation.u_get32(buffer, offset)
end

function u_get64(buffer, offset):
    return implementation.u_get64(buffer, offset)
end

function u_address(buffer):
    return implementation.u_address(buffer)
end

function socket_path(path):
    return implementation.socket_path(path)
end

function sockaddr_un(path):
    return implementation.sockaddr_un(path)
end

function listen_unix(path, backlog):
    return implementation.listen_unix(path, backlog)
end

function chmod_path(path, mode):
    return implementation.chmod_path(path, mode)
end

function chown_path(path, user, group):
    return implementation.chown_path(path, user, group)
end

function set_nonblocking(handle):
    return implementation.set_nonblocking(handle)
end

function accept_unix(server):
    return implementation.accept_unix(server)
end

function close_fd(handle):
    return implementation.close_fd(handle)
end

function memfd(name, size):
    return implementation.memfd(name, size)
end

function send_fd(handle, payload, count, descriptor):
    return implementation.send_fd(handle, payload, count, descriptor)
end

function send_bytes(handle, payload, count):
    return implementation.send_bytes(handle, payload, count)
end

function send_from_fd(handle, payload, offset, count, descriptor):
    return implementation.send_from_fd(handle, payload, offset, count, descriptor)
end

function send_from(handle, payload, offset, count):
    return implementation.send_from(handle, payload, offset, count)
end

function munmap(address, size):
    return implementation.munmap(address, size)
end

function pipe_nonblock():
    return implementation.pipe_nonblock()
end

function recv_fds(handle, payload, count, fds):
    return implementation.recv_fds(handle, payload, count, fds)
end
