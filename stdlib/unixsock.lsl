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
SYS_ACCEPT4 = 288
SYS_SENDMSG = 46
SYS_RECVMSG = 47
SYS_BIND = 49
SYS_LISTEN = 50
SYS_SOCKETPAIR = 53
SYS_MEMFD_CREATE = 319
SYS_MUNMAP = 11
SYS_PIPE2 = 293
SYS_CHMOD = 90
SYS_CHOWN = 92

AF_UNIX = 1
SOCK_STREAM = 1
SOCK_NONBLOCK = 2048
SOCK_CLOEXEC = 524288
SOL_SOCKET = 1
SCM_RIGHTS = 1
MSG_DONTWAIT = 64
MSG_CMSG_CLOEXEC = 1073741824
F_SETFL = 4
O_NONBLOCK = 2048
O_CLOEXEC = 524288
MFD_CLOEXEC = 1

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

function socket_path(path):
    p = String(path)
    if len(p) == 0 or len(p) > 107:
        Error(ValueError: "unix socket path must contain 1..107 ASCII bytes")
    end
    for character in p:
        code = ord(character)
        if code == 0 or code > 127:
            Error(ValueError: "unix socket path must not contain NUL or non-ASCII bytes")
        end
    end
    return p
end

# sockaddr_un for a filesystem path: family (2 bytes) + path + NUL.
function sockaddr_un(path):
    p = socket_path(path)
    sa = __lsl_byte_zeros(110)
    b = ByteArray(sa)
    b[0] = AF_UNIX
    b[1] = 0
    i = 0
    while i < len(p):
        b[2 + i] = ord(p[i])
        i = i + 1
    end
    return sa
end

# Listening server socket on `path`. Existing filesystem nodes are never
# removed implicitly; the owner must deliberately clean a stale socket.
# Returns the descriptor, or a negative errno.
function listen_unix(path, backlog):
    p = socket_path(path)
    s = __lsl_syscall(SYS_SOCKET, AF_UNIX, SOCK_STREAM + SOCK_NONBLOCK + SOCK_CLOEXEC, 0, 0)
    if s < 0:
        return s
    end
    sa = sockaddr_un(p)
    rc = __lsl_syscall(SYS_BIND, s, u_address(sa), 110, 0)
    if rc < 0:
        call __lsl_syscall(SYS_CLOSE, s, 0, 0, 0)
        return rc
    end
    queue = Int(backlog)
    if queue < 0:
        queue = 0
    elif queue > 4096:
        queue = 4096
    end
    rc = __lsl_syscall(SYS_LISTEN, s, queue, 0, 0)
    if rc < 0:
        call __lsl_syscall(SYS_CLOSE, s, 0, 0, 0)
        return rc
    end
    return s
end

# Mode bits on a path. A socket created under the default umask is
# srwxr-xr-x, and connect(2) needs WRITE permission — so every other user
# on the machine is locked out until this widens it.
function chmod_path(path, mode):
    p = socket_path(path)
    permissions = Int(mode)
    if permissions < 0 or permissions > 511:
        return -22
    end
    buf = ByteArray()
    i = 0
    while i < len(p):
        call buf.append(ord(p[i]))
        i = i + 1
    end
    call buf.append(0)
    return __lsl_syscall(SYS_CHMOD, u_address(buf), permissions, 0, 0)
end

function chown_path(path, user, group):
    p = socket_path(path)
    uid = Int(user)
    gid = Int(group)
    if uid < 0 or uid > 2147483647 or gid < 0 or gid > 2147483647:
        return -22
    end
    buf = ByteArray()
    for character in p:
        call buf.append(ord(character))
    end
    call buf.append(0)
    return __lsl_syscall(SYS_CHOWN, u_address(buf), uid, gid, 0)
end

function set_nonblocking(handle):
    return __lsl_syscall(SYS_FCNTL, Int(handle), F_SETFL, O_NONBLOCK, 0)
end

# Accept one pending connection; -11 (EAGAIN) when none is waiting.
function accept_unix(server):
    return __lsl_syscall(SYS_ACCEPT4, Int(server), 0, 0, SOCK_NONBLOCK + SOCK_CLOEXEC)
end

function close_fd(handle):
    return __lsl_syscall(SYS_CLOSE, Int(handle), 0, 0, 0)
end

# An anonymous shared-memory file of `size` bytes (the buffer transport a
# display protocol hands to its clients).
function memfd(name, size):
    n = ByteArray()
    t = String(name)
    if len(t) == 0 or len(t) > 249:
        return -22
    end
    i = 0
    while i < len(t):
        code = ord(t[i])
        if code == 0 or code > 127:
            return -22
        end
        call n.append(code)
        i = i + 1
    end
    call n.append(0)
    length = Int(size)
    if length < 0:
        return -22
    end
    h = __lsl_syscall(SYS_MEMFD_CREATE, u_address(n), MFD_CLOEXEC, 0, 0)
    if h < 0:
        return h
    end
    rc = __lsl_syscall(SYS_FTRUNCATE, h, length, 0, 0)
    if rc < 0:
        call close_fd(h)
        return rc
    end
    return h
end

# Send bytes, optionally with ONE descriptor attached (fd < 0 = none).
function send_fd(handle, payload, count, descriptor):
    if type(payload) != "ByteArray":
        return -22
    end
    amount = Int(count)
    if amount < 0 or amount > len(payload):
        return -22
    end
    # Allocate every structure FIRST, then write the addresses, then call:
    # the LSL heap moves objects when it grows, so an address recorded
    # before another allocation can be stale by the time the kernel reads
    # it (the same trap that made DIRTYFB miss its damage rectangle).
    iov = __lsl_byte_zeros(16)
    ctrl = __lsl_byte_zeros(24)
    msg = __lsl_byte_zeros(56)
    call u_put64(iov, 0, u_address(payload))
    call u_put64(iov, 8, amount)
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
    if type(payload) != "ByteArray":
        return -22
    end
    start = Int(offset)
    amount = Int(count)
    if start < 0 or amount < 0 or start > len(payload) or amount > len(payload) - start:
        return -22
    end
    iov = __lsl_byte_zeros(16)
    ctrl = __lsl_byte_zeros(24)
    msg = __lsl_byte_zeros(56)
    call u_put64(iov, 0, u_address(payload) + start)
    call u_put64(iov, 8, amount)
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
    pointer = Int(address)
    length = Int(size)
    if pointer <= 0 or length <= 0:
        return -22
    end
    return __lsl_syscall(SYS_MUNMAP, pointer, length, 0, 0)
end

# A pipe with a nonblocking read end: [read, write], or [] on failure.
# This is the transport a clipboard uses — the owner writes the selection
# into the write end and we read it without ever blocking the frame loop.
function pipe_nonblock():
    fds = __lsl_byte_zeros(8)
    rc = __lsl_syscall(SYS_PIPE2, u_address(fds), O_NONBLOCK + O_CLOEXEC, 0, 0)
    if rc < 0:
        return []
    end
    return [Int(u_get32(fds, 0)), Int(u_get32(fds, 4))]
end

# Receive up to `count` bytes into `payload`. Any descriptors that arrive
# are appended to the `fds` list. Returns the byte count, or a negative
# errno (-11 EAGAIN when nothing is pending).
function recv_fds(handle, payload, count, fds):
    if type(payload) != "ByteArray" or type(fds) != "List":
        return -22
    end
    amount = Int(count)
    if amount < 0 or amount > len(payload):
        return -22
    end
    # Same allocation-before-addresses rule as send_fd.
    iov = __lsl_byte_zeros(16)
    ctrl = __lsl_byte_zeros(256)
    msg = __lsl_byte_zeros(56)
    call u_put64(iov, 0, u_address(payload))
    call u_put64(iov, 8, amount)
    call u_put64(msg, 16, u_address(iov))
    call u_put64(msg, 24, 1)
    call u_put64(msg, 32, u_address(ctrl))
    call u_put64(msg, 40, 256)
    n = __lsl_syscall(SYS_RECVMSG, Int(handle), u_address(msg), MSG_DONTWAIT + MSG_CMSG_CLOEXEC, 0)
    if n < 0:
        return n
    end
    # Walk the control messages: each cmsghdr is 8-byte aligned.
    total = Int(u_get64(msg, 40))
    if total < 0:
        return -22
    elif total > 256:
        total = 256
    end
    off = 0
    while off <= total - 16:
        clen = Int(u_get64(ctrl, off))
        if clen < 16 or clen > total - off:
            off = total
        else:
            if u_get32(ctrl, off + 8) == SOL_SOCKET and u_get32(ctrl, off + 12) == SCM_RIGHTS:
                nfd = (clen - 16) // 4
                k = 0
                while k < nfd:
                    received = Int(u_get32(ctrl, off + 16 + k * 4))
                    # Bound descriptors retained for one peer. A client can
                    # otherwise send SCM_RIGHTS forever and exhaust the
                    # compositor's process-wide fd table.
                    if len(fds) < 64:
                        call fds.append(received)
                    else:
                        call close_fd(received)
                    end
                    k = k + 1
                end
            end
            off = off + (clen + 7) // 8 * 8
        end
    end
    return n
end
