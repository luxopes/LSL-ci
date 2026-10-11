load _platform_linux_x86_64 as platform
# Unix-domain sockets with file-descriptor passing, in pure LSL on top of
# the raw syscall builtin. This is what a display server needs and a plain
# fd wrapper cannot express: clients hand over shared-memory buffers as
# descriptors inside the control message of sendmsg/recvmsg (SCM_RIGHTS).
#
# Everything here builds the kernel's structures (sockaddr_un, iovec,
# msghdr, cmsghdr) in ByteArrays and passes their data addresses, so no C
# helper and no libc are involved.

load fd

SYS_READ = platform.SYS_READ
SYS_WRITE = platform.SYS_WRITE
SYS_CLOSE = platform.SYS_CLOSE
SYS_LSEEK = platform.SYS_LSEEK
SYS_FCNTL = platform.SYS_FCNTL
SYS_FTRUNCATE = platform.SYS_FTRUNCATE
SYS_UNLINK = platform.SYS_UNLINK
SYS_SOCKET = platform.SYS_SOCKET
SYS_ACCEPT4 = platform.SYS_ACCEPT4
SYS_SENDMSG = platform.SYS_SENDMSG
SYS_RECVMSG = platform.SYS_RECVMSG
SYS_BIND = platform.SYS_BIND
SYS_LISTEN = platform.SYS_LISTEN
SYS_SOCKETPAIR = platform.SYS_SOCKETPAIR
SYS_MEMFD_CREATE = platform.SYS_MEMFD_CREATE
SYS_MUNMAP = platform.SYS_MUNMAP
SYS_PIPE2 = platform.SYS_PIPE2
SYS_CHMOD = platform.SYS_CHMOD
SYS_CHOWN = platform.SYS_CHOWN

AF_UNIX = platform.AF_UNIX
SOCK_STREAM = platform.SOCK_STREAM
SOCK_NONBLOCK = platform.SOCK_NONBLOCK
SOCK_CLOEXEC = platform.SOCK_CLOEXEC
SOL_SOCKET = platform.SOL_SOCKET
SCM_RIGHTS = platform.SCM_RIGHTS
MSG_DONTWAIT = platform.MSG_DONTWAIT
MSG_CMSG_CLOEXEC = platform.MSG_CMSG_CLOEXEC
F_SETFL = platform.F_SETFL
O_NONBLOCK = platform.O_NONBLOCK
O_CLOEXEC = platform.O_CLOEXEC
MFD_CLOEXEC = platform.MFD_CLOEXEC

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
    if len(p) == 0 or len(p) > platform.UNIX_PATH_MAX:
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
    sa = __lsl_byte_zeros(platform.SOCKADDR_UN_BYTES)
    b = ByteArray(sa)
    b[0] = AF_UNIX
    b[1] = 0
    i = 0
    while i < len(p):
        b[platform.SOCKADDR_UN_PATH + i] = ord(p[i])
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
    rc = __lsl_syscall(SYS_BIND, s, u_address(sa), platform.SOCKADDR_UN_BYTES, 0)
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
        return -platform.EINVAL
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
        return -platform.EINVAL
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
        return -platform.EINVAL
    end
    i = 0
    while i < len(t):
        code = ord(t[i])
        if code == 0 or code > 127:
            return -platform.EINVAL
        end
        call n.append(code)
        i = i + 1
    end
    call n.append(0)
    length = Int(size)
    if length < 0:
        return -platform.EINVAL
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
        return -platform.EINVAL
    end
    amount = Int(count)
    if amount < 0 or amount > len(payload):
        return -platform.EINVAL
    end
    # Allocate every structure FIRST, then write the addresses, then call:
    # the LSL heap moves objects when it grows, so an address recorded
    # before another allocation can be stale by the time the kernel reads
    # it (the same trap that made DIRTYFB miss its damage rectangle).
    iov = __lsl_byte_zeros(platform.IOVEC_BYTES)
    ctrl = __lsl_byte_zeros(platform.CMSG_FD_SPACE)
    msg = __lsl_byte_zeros(platform.MSGHDR_BYTES)
    call u_put64(iov, platform.IOVEC_BASE, u_address(payload))
    call u_put64(iov, platform.IOVEC_LENGTH, amount)
    call u_put64(msg, platform.MSGHDR_IOV, u_address(iov))
    call u_put64(msg, platform.MSGHDR_IOVLEN, 1)
    if Int(descriptor) >= 0:
        # cmsghdr: len 20 (header 16 + one int), SOL_SOCKET/SCM_RIGHTS.
        call u_put64(ctrl, platform.CMSG_LENGTH, platform.CMSG_FD_BYTES)
        call u_put32(ctrl, platform.CMSG_LEVEL, SOL_SOCKET)
        call u_put32(ctrl, platform.CMSG_TYPE, SCM_RIGHTS)
        call u_put32(ctrl, platform.CMSG_DATA, Int(descriptor))
        call u_put64(msg, platform.MSGHDR_CONTROL, u_address(ctrl))
        call u_put64(msg, platform.MSGHDR_CONTROLLEN, platform.CMSG_FD_SPACE)
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
        return -platform.EINVAL
    end
    start = Int(offset)
    amount = Int(count)
    if start < 0 or amount < 0 or start > len(payload) or amount > len(payload) - start:
        return -platform.EINVAL
    end
    iov = __lsl_byte_zeros(platform.IOVEC_BYTES)
    ctrl = __lsl_byte_zeros(platform.CMSG_FD_SPACE)
    msg = __lsl_byte_zeros(platform.MSGHDR_BYTES)
    call u_put64(iov, platform.IOVEC_BASE, u_address(payload) + start)
    call u_put64(iov, platform.IOVEC_LENGTH, amount)
    call u_put64(msg, platform.MSGHDR_IOV, u_address(iov))
    call u_put64(msg, platform.MSGHDR_IOVLEN, 1)
    if Int(descriptor) >= 0:
        call u_put64(ctrl, platform.CMSG_LENGTH, platform.CMSG_FD_BYTES)
        call u_put32(ctrl, platform.CMSG_LEVEL, SOL_SOCKET)
        call u_put32(ctrl, platform.CMSG_TYPE, SCM_RIGHTS)
        call u_put32(ctrl, platform.CMSG_DATA, Int(descriptor))
        call u_put64(msg, platform.MSGHDR_CONTROL, u_address(ctrl))
        call u_put64(msg, platform.MSGHDR_CONTROLLEN, platform.CMSG_FD_SPACE)
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
        return -platform.EINVAL
    end
    return __lsl_syscall(SYS_MUNMAP, pointer, length, 0, 0)
end

# A pipe with a nonblocking read end: [read, write], or [] on failure.
# This is the transport a clipboard uses — the owner writes the selection
# into the write end and we read it without ever blocking the frame loop.
function pipe_nonblock():
    fds = __lsl_byte_zeros(2 * platform.INT_BYTES)
    rc = __lsl_syscall(SYS_PIPE2, u_address(fds), O_NONBLOCK + O_CLOEXEC, 0, 0)
    if rc < 0:
        return []
    end
    return [Int(u_get32(fds, 0)), Int(u_get32(fds, platform.INT_BYTES))]
end

# Receive up to `count` bytes into `payload`. Any descriptors that arrive
# are appended to the `fds` list. Returns the byte count, or a negative
# errno (-11 EAGAIN when nothing is pending).
function recv_fds(handle, payload, count, fds):
    if type(payload) != "ByteArray" or type(fds) != "List":
        return -platform.EINVAL
    end
    amount = Int(count)
    if amount < 0 or amount > len(payload):
        return -platform.EINVAL
    end
    # Same allocation-before-addresses rule as send_fd.
    iov = __lsl_byte_zeros(platform.IOVEC_BYTES)
    ctrl = __lsl_byte_zeros(256)
    msg = __lsl_byte_zeros(platform.MSGHDR_BYTES)
    call u_put64(iov, platform.IOVEC_BASE, u_address(payload))
    call u_put64(iov, platform.IOVEC_LENGTH, amount)
    call u_put64(msg, platform.MSGHDR_IOV, u_address(iov))
    call u_put64(msg, platform.MSGHDR_IOVLEN, 1)
    call u_put64(msg, platform.MSGHDR_CONTROL, u_address(ctrl))
    call u_put64(msg, platform.MSGHDR_CONTROLLEN, 256)
    n = __lsl_syscall(SYS_RECVMSG, Int(handle), u_address(msg), MSG_DONTWAIT + MSG_CMSG_CLOEXEC, 0)
    if n < 0:
        return n
    end
    # Walk the control messages: each cmsghdr is 8-byte aligned.
    total = Int(u_get64(msg, platform.MSGHDR_CONTROLLEN))
    if total < 0:
        return -platform.EINVAL
    elif total > 256:
        total = 256
    end
    off = 0
    while off <= total - platform.CMSG_HEADER_BYTES:
        clen = Int(u_get64(ctrl, off))
        if clen < platform.CMSG_HEADER_BYTES or clen > total - off:
            off = total
        else:
            if u_get32(ctrl, off + platform.CMSG_LEVEL) == SOL_SOCKET and u_get32(ctrl, off + platform.CMSG_TYPE) == SCM_RIGHTS:
                nfd = (clen - platform.CMSG_HEADER_BYTES) // platform.INT_BYTES
                k = 0
                while k < nfd:
                    received = Int(u_get32(ctrl, off + platform.CMSG_DATA + k * platform.INT_BYTES))
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
            off = off + (clen + platform.CMSG_ALIGNMENT - 1) // platform.CMSG_ALIGNMENT * platform.CMSG_ALIGNMENT
        end
    end
    return n
end
