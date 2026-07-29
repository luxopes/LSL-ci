# Unix-domain sockets with file-descriptor passing, in pure LSL on top of
# the raw syscall builtin. This is what a display server needs and a plain
# fd wrapper cannot express: clients hand over shared-memory buffers as
# descriptors inside the control message of sendmsg/recvmsg (SCM_RIGHTS).
#
# Everything here builds the kernel's structures (sockaddr_un, iovec,
# msghdr, cmsghdr) in ByteArrays and passes their data addresses, so no C
# helper and no libc are involved.

load fd

SYS_READ = 0
SYS_WRITE = 1
SYS_CLOSE = 3
SYS_LSEEK = 8
SYS_FCNTL = 72
SYS_FTRUNCATE = 77
SYS_UNLINK = 87
SYS_SOCKET = 41
SYS_ACCEPT = 43
SYS_SENDMSG = 46
SYS_RECVMSG = 47
SYS_BIND = 49
SYS_LISTEN = 50
SYS_SOCKETPAIR = 53
SYS_MEMFD_CREATE = 319
SYS_MUNMAP = 11
SYS_PIPE2 = 293
SYS_CHMOD = 90

AF_UNIX = 1
SOCK_STREAM = 1
SOCK_NONBLOCK = 2048
SOL_SOCKET = 1
SCM_RIGHTS = 1
MSG_DONTWAIT = 64
F_SETFL = 4
O_NONBLOCK = 2048

function u_put32(buffer, offset, value):
    b = ByteArray(buffer)
    v = Int(value)
    b[offset] = v % 256
    b[offset + 1] = v // 256 % 256
    b[offset + 2] = v // 65536 % 256
    b[offset + 3] = v // 16777216 % 256
    return None
end

function u_put64(buffer, offset, value):
    call u_put32(buffer, offset, Int(value) % 4294967296)
    call u_put32(buffer, offset + 4, Int(value) // 4294967296)
    return None
end

function u_get32(buffer, offset):
    b = ByteArray(buffer)
    return Int(b[offset]) + Int(b[offset + 1]) * 256 + Int(b[offset + 2]) * 65536 + Int(b[offset + 3]) * 16777216
end

function u_get64(buffer, offset):
    return u_get32(buffer, offset) + u_get32(buffer, offset + 4) * 4294967296
end

function u_address(buffer):
    return Int(__lsl_data_address(buffer))
end

# sockaddr_un for a filesystem path: family (2 bytes) + path + NUL.
function sockaddr_un(path):
    p = String(path)
    sa = __lsl_byte_zeros(110)
    b = ByteArray(sa)
    b[0] = AF_UNIX
    b[1] = 0
    i = 0
    while i < len(p) and i < 107:
        b[2 + i] = ord(p[i])
        i = i + 1
    end
    return sa
end

# Listening server socket on `path` (the stale node is removed first).
# Returns the descriptor, or a negative errno.
function listen_unix(path, backlog):
    call unlink(String(path))
    s = __lsl_syscall(SYS_SOCKET, AF_UNIX, SOCK_STREAM, 0, 0)
    if s < 0:
        return s
    end
    sa = sockaddr_un(path)
    rc = __lsl_syscall(SYS_BIND, s, u_address(sa), 110, 0)
    if rc < 0:
        call __lsl_syscall(SYS_CLOSE, s, 0, 0, 0)
        return rc
    end
    rc = __lsl_syscall(SYS_LISTEN, s, Int(backlog), 0, 0)
    if rc < 0:
        call __lsl_syscall(SYS_CLOSE, s, 0, 0, 0)
        return rc
    end
    call set_nonblocking(s)
    return s
end

# Mode bits on a path. A socket created under the default umask is
# srwxr-xr-x, and connect(2) needs WRITE permission — so every other user
# on the machine is locked out until this widens it.
function chmod_path(path, mode):
    p = String(path)
    buf = ByteArray()
    i = 0
    while i < len(p):
        call buf.append(ord(p[i]))
        i = i + 1
    end
    call buf.append(0)
    return __lsl_syscall(SYS_CHMOD, u_address(buf), Int(mode), 0, 0)
end

function set_nonblocking(handle):
    return __lsl_syscall(SYS_FCNTL, Int(handle), F_SETFL, O_NONBLOCK, 0)
end

# Accept one pending connection; -11 (EAGAIN) when none is waiting.
function accept_unix(server):
    c = __lsl_syscall(SYS_ACCEPT, Int(server), 0, 0, 0)
    if c >= 0:
        call set_nonblocking(c)
    end
    return c
end

function close_fd(handle):
    return __lsl_syscall(SYS_CLOSE, Int(handle), 0, 0, 0)
end

# An anonymous shared-memory file of `size` bytes (the buffer transport a
# display protocol hands to its clients).
function memfd(name, size):
    n = ByteArray()
    t = String(name)
    i = 0
    while i < len(t):
        call n.append(ord(t[i]))
        i = i + 1
    end
    call n.append(0)
    h = __lsl_syscall(SYS_MEMFD_CREATE, u_address(n), 0, 0, 0)
    if h < 0:
        return h
    end
    rc = __lsl_syscall(SYS_FTRUNCATE, h, Int(size), 0, 0)
    if rc < 0:
        call close_fd(h)
        return rc
    end
    return h
end

# Send bytes, optionally with ONE descriptor attached (fd < 0 = none).
function send_fd(handle, payload, count, descriptor):
    # Allocate every structure FIRST, then write the addresses, then call:
    # the LSL heap moves objects when it grows, so an address recorded
    # before another allocation can be stale by the time the kernel reads
    # it (the same trap that made DIRTYFB miss its damage rectangle).
    iov = __lsl_byte_zeros(16)
    ctrl = __lsl_byte_zeros(24)
    msg = __lsl_byte_zeros(56)
    call u_put64(iov, 0, u_address(payload))
    call u_put64(iov, 8, Int(count))
    call u_put64(msg, 16, u_address(iov))
    call u_put64(msg, 24, 1)
    if Int(descriptor) >= 0:
        # cmsghdr: len 20 (header 16 + one int), SOL_SOCKET/SCM_RIGHTS.
        call u_put64(ctrl, 0, 20)
        call u_put32(ctrl, 8, SOL_SOCKET)
        call u_put32(ctrl, 12, SCM_RIGHTS)
        call u_put32(ctrl, 16, Int(descriptor))
        call u_put64(msg, 32, u_address(ctrl))
        call u_put64(msg, 40, 24)
    end
    return __lsl_syscall(SYS_SENDMSG, Int(handle), u_address(msg), 0, 0)
end

function send_bytes(handle, payload, count):
    return send_fd(handle, payload, count, 0 - 1)
end

# Send `count` bytes starting at `offset` inside the payload, optionally
# with ONE descriptor attached (descriptor < 0 = none). This is what a
# buffered writer needs after a short send on a nonblocking socket, and
# what keeps an fd-carrying message in its proper place in the stream.
function send_from_fd(handle, payload, offset, count, descriptor):
    iov = __lsl_byte_zeros(16)
    ctrl = __lsl_byte_zeros(24)
    msg = __lsl_byte_zeros(56)
    call u_put64(iov, 0, u_address(payload) + Int(offset))
    call u_put64(iov, 8, Int(count))
    call u_put64(msg, 16, u_address(iov))
    call u_put64(msg, 24, 1)
    if Int(descriptor) >= 0:
        call u_put64(ctrl, 0, 20)
        call u_put32(ctrl, 8, SOL_SOCKET)
        call u_put32(ctrl, 12, SCM_RIGHTS)
        call u_put32(ctrl, 16, Int(descriptor))
        call u_put64(msg, 32, u_address(ctrl))
        call u_put64(msg, 40, 24)
    end
    return __lsl_syscall(SYS_SENDMSG, Int(handle), u_address(msg), 0, 0)
end

function send_from(handle, payload, offset, count):
    return send_from_fd(handle, payload, offset, count, 0 - 1)
end

# Unmap a shared-memory pool once no buffer references it.
function munmap(address, size):
    return __lsl_syscall(SYS_MUNMAP, Int(address), Int(size), 0, 0)
end

# A pipe with a nonblocking read end: [read, write], or [] on failure.
# This is the transport a clipboard uses — the owner writes the selection
# into the write end and we read it without ever blocking the frame loop.
function pipe_nonblock():
    fds = __lsl_byte_zeros(8)
    rc = __lsl_syscall(SYS_PIPE2, u_address(fds), O_NONBLOCK, 0, 0)
    if rc < 0:
        return []
    end
    return [Int(u_get32(fds, 0)), Int(u_get32(fds, 4))]
end

# Receive up to `count` bytes into `payload`. Any descriptors that arrive
# are appended to the `fds` list. Returns the byte count, or a negative
# errno (-11 EAGAIN when nothing is pending).
function recv_fds(handle, payload, count, fds):
    # Same allocation-before-addresses rule as send_fd.
    iov = __lsl_byte_zeros(16)
    ctrl = __lsl_byte_zeros(256)
    msg = __lsl_byte_zeros(56)
    call u_put64(iov, 0, u_address(payload))
    call u_put64(iov, 8, Int(count))
    call u_put64(msg, 16, u_address(iov))
    call u_put64(msg, 24, 1)
    call u_put64(msg, 32, u_address(ctrl))
    call u_put64(msg, 40, 256)
    n = __lsl_syscall(SYS_RECVMSG, Int(handle), u_address(msg), MSG_DONTWAIT, 0)
    if n < 0:
        return n
    end
    # Walk the control messages: each cmsghdr is 8-byte aligned.
    total = Int(u_get64(msg, 40))
    off = 0
    while off + 16 <= total:
        clen = Int(u_get64(ctrl, off))
        if clen < 16:
            off = total
        else:
            if u_get32(ctrl, off + 8) == SOL_SOCKET and u_get32(ctrl, off + 12) == SCM_RIGHTS:
                nfd = (clen - 16) // 4
                k = 0
                while k < nfd:
                    call fds.append(u_get32(ctrl, off + 16 + k * 4))
                    k = k + 1
                end
            end
            off = off + (clen + 7) // 8 * 8
        end
    end
    return n
end
