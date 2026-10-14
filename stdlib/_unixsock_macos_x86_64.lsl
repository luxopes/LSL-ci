# macOS: sockety Unixu s předáváním deskriptorů (SCM_RIGHTS) nad libSystem.
# Stejná logika jako na Linuxu, liší se struktury BSD: sockaddr_un má délku
# v prvním bajtu, msghdr 48 B (iovlen a controllen 32bitové), cmsghdr
# 12 B hlavičky se zarovnáním na 4 B. memfd je smazaný dočasný soubor,
# accept4 a pipe2 nahradí fcntl. Chyby mají hodnoty errno Linuxu (-11 =
# nic nečeká). Argumenty surových volání musí být Int.
load fd

# Linuxová čísla systémových volání veřejné fasády na macOS neexistují.
SYS_READ = -1
SYS_WRITE = -1
SYS_CLOSE = -1
SYS_LSEEK = -1
SYS_FCNTL = -1
SYS_FTRUNCATE = -1
SYS_UNLINK = -1
SYS_SOCKET = -1
SYS_ACCEPT = -1
SYS_ACCEPT4 = -1
SYS_SENDMSG = -1
SYS_RECVMSG = -1
SYS_BIND = -1
SYS_LISTEN = -1
SYS_SOCKETPAIR = -1
SYS_MEMFD_CREATE = -1
SYS_MUNMAP = -1
SYS_PIPE = -1
SYS_PIPE2 = -1
SYS_CHMOD = -1
SYS_CHOWN = -1
SYS_FCHMODAT = -1
SYS_FCHOWNAT = -1

AF_UNIX = 1
SOCK_STREAM = 1
SOCK_NONBLOCK = 0
SOCK_CLOEXEC = 0
SOL_SOCKET = 65535
SCM_RIGHTS = 1
MSG_DONTWAIT = 128
MSG_CMSG_CLOEXEC = 0
F_SETFL = 4
F_GETFL = 3
F_SETFD = 2
FD_CLOEXEC = 1
O_NONBLOCK = 4
O_CLOEXEC = 16777216
MFD_CLOEXEC = 0
EINVAL = 22

# Rozložení struktur macOS.
UNIX_PATH_MAX = 103
SOCKADDR_UN_BYTES = 106
SOCKADDR_UN_PATH = 2
INT_BYTES = 4
IOVEC_BYTES = 16
IOVEC_BASE = 0
IOVEC_LENGTH = 8
MSGHDR_BYTES = 48
MSGHDR_IOV = 16
MSGHDR_IOVLEN = 24
MSGHDR_CONTROL = 32
MSGHDR_CONTROLLEN = 40
CMSG_HEADER_BYTES = 12
CMSG_LENGTH = 0
CMSG_LEVEL = 4
CMSG_TYPE = 8
CMSG_DATA = 12
CMSG_FD_BYTES = 16
CMSG_FD_SPACE = 16
CMSG_ALIGNMENT = 4

function int32(value):
    number = Int(value) & 4294967295
    if number >= 2147483648:
        number -= 4294967296
    end
    return number
end

# errno macOS -> záporné errno Linuxu (1..34 jsou stejné).
function failure():
    code = int32(__lsl_qbe_load32(Int(__lsl_qbe_call0(__lsl_symbol("__error")))))
    if code >= 1 and code <= 34:
        return 0 - code
    end
    table = {35: 11, 36: 115, 37: 114, 38: 88, 48: 98, 49: 99, 54: 104, 57: 107, 60: 110, 61: 111, 62: 40, 63: 36}
    return 0 - table.get(code, 5)
end

# Výsledek int funkce libSystem: hodnota, nebo záporné errno Linuxu.
function checked(result):
    value = int32(result)
    if value == -1:
        return failure()
    end
    return value
end

# Výsledek ssize_t funkce (sendmsg, recvmsg).
function checked64(result):
    value = Int(result)
    if value == -1:
        return failure()
    end
    return value
end

function fcntl(handle, command, argument):
    return checked(__lsl_qbe_call3(__lsl_symbol("lsl_arch_fcntl"), Int(handle), Int(command), Int(argument)))
end

# Neblokující deskriptor s FD_CLOEXEC (accept4 a pipe2 Linuxu).
function prepare(handle):
    call fcntl(handle, F_SETFD, FD_CLOEXEC)
    flags = fcntl(handle, F_GETFL, 0)
    if flags < 0:
        return flags
    end
    return fcntl(handle, F_SETFL, flags | O_NONBLOCK)
end

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
    if len(p) == 0 or len(p) > UNIX_PATH_MAX:
        Error(ValueError: "unix socket path must contain 1..103 ASCII bytes")
    end
    for character in p:
        code = ord(character)
        if code == 0 or code > 127:
            Error(ValueError: "unix socket path must not contain NUL or non-ASCII bytes")
        end
    end
    return p
end

# sockaddr_un pro cestu: délka, rodina (po bajtu) + cesta + NUL.
function sockaddr_un(path):
    p = socket_path(path)
    sa = __lsl_byte_zeros(SOCKADDR_UN_BYTES)
    b = ByteArray(sa)
    b[0] = SOCKADDR_UN_BYTES
    b[1] = AF_UNIX
    i = 0
    while i < len(p):
        b[SOCKADDR_UN_PATH + i] = ord(p[i])
        i = i + 1
    end
    return sa
end

# Listening server socket on `path`. Existing filesystem nodes are never
# removed implicitly; the owner must deliberately clean a stale socket.
# Returns the descriptor, or a negative errno.
function listen_unix(path, backlog):
    p = socket_path(path)
    s = checked(__lsl_qbe_call3(__lsl_symbol("socket"), AF_UNIX, SOCK_STREAM, 0))
    if s < 0:
        return s
    end
    sa = sockaddr_un(p)
    call prepare(s)
    rc = checked(__lsl_qbe_call3(__lsl_symbol("bind"), s, u_address(sa), SOCKADDR_UN_BYTES))
    if rc < 0:
        call close_fd(s)
        return rc
    end
    queue = Int(backlog)
    if queue < 0:
        queue = 0
    elif queue > 4096:
        queue = 4096
    end
    rc = checked(__lsl_qbe_call2(__lsl_symbol("listen"), s, queue))
    if rc < 0:
        call close_fd(s)
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
        return -EINVAL
    end
    buf = ByteArray()
    i = 0
    while i < len(p):
        call buf.append(ord(p[i]))
        i = i + 1
    end
    call buf.append(0)
    return checked(__lsl_qbe_call2(__lsl_symbol("chmod"), u_address(buf), permissions))
end

function chown_path(path, user, group):
    p = socket_path(path)
    uid = Int(user)
    gid = Int(group)
    if uid < 0 or uid > 2147483647 or gid < 0 or gid > 2147483647:
        return -EINVAL
    end
    buf = ByteArray()
    for character in p:
        call buf.append(ord(character))
    end
    call buf.append(0)
    return checked(__lsl_qbe_call3(__lsl_symbol("chown"), u_address(buf), uid, gid))
end

function set_nonblocking(handle):
    return fcntl(handle, F_SETFL, O_NONBLOCK)
end

# Accept one pending connection; -11 (EAGAIN) when none is waiting.
function accept_unix(server):
    client = checked(__lsl_qbe_call3(__lsl_symbol("accept"), Int(server), 0, 0))
    if client >= 0:
        call prepare(client)
    end
    return client
end

function close_fd(handle):
    return checked(__lsl_qbe_call1(__lsl_symbol("close"), Int(handle)))
end

# An anonymous shared-memory file of `size` bytes (the buffer transport a
# display protocol hands to its clients).
function memfd(name, size):
    n = ByteArray()
    t = String(name)
    if len(t) == 0 or len(t) > 249:
        return -EINVAL
    end
    i = 0
    while i < len(t):
        code = ord(t[i])
        if code == 0 or code > 127:
            return -EINVAL
        end
        call n.append(code)
        i = i + 1
    end
    call n.append(0)
    length = Int(size)
    if length < 0:
        return -EINVAL
    end
    # Dočasný soubor v $TMPDIR, hned smazaný (macOS nemá memfd).
    directory = __lsl_getenv("TMPDIR")
    if directory == None or String(directory) == "":
        directory = "/tmp"
    end
    template = ByteArray()
    for character in String(directory) + "/lsl-memfd.XXXXXX":
        call template.append(ord(character))
    end
    call template.append(0)
    h = checked(__lsl_qbe_call2(__lsl_symbol("mkostemp"), u_address(template), O_CLOEXEC))
    if h < 0:
        return h
    end
    call __lsl_qbe_call1(__lsl_symbol("unlink"), u_address(template))
    rc = checked(__lsl_qbe_call2(__lsl_symbol("ftruncate"), h, length))
    if rc < 0:
        call close_fd(h)
        return rc
    end
    return h
end

# Send bytes, optionally with ONE descriptor attached (fd < 0 = none).
function send_fd(handle, payload, count, descriptor):
    if type(payload) != "ByteArray":
        return -EINVAL
    end
    amount = Int(count)
    if amount < 0 or amount > len(payload):
        return -EINVAL
    end
    # Allocate every structure FIRST, then write the addresses, then call:
    # the LSL heap moves objects when it grows, so an address recorded
    # before another allocation can be stale by the time the kernel reads
    # it (the same trap that made DIRTYFB miss its damage rectangle).
    iov = __lsl_byte_zeros(IOVEC_BYTES)
    ctrl = __lsl_byte_zeros(CMSG_FD_SPACE)
    msg = __lsl_byte_zeros(MSGHDR_BYTES)
    call u_put64(iov, IOVEC_BASE, u_address(payload))
    call u_put64(iov, IOVEC_LENGTH, amount)
    call u_put64(msg, MSGHDR_IOV, u_address(iov))
    call u_put32(msg, MSGHDR_IOVLEN, 1)
    if Int(descriptor) >= 0:
        # cmsghdr: len 20 (header 16 + one int), SOL_SOCKET/SCM_RIGHTS.
        call u_put32(ctrl, CMSG_LENGTH, CMSG_FD_BYTES)
        call u_put32(ctrl, CMSG_LEVEL, SOL_SOCKET)
        call u_put32(ctrl, CMSG_TYPE, SCM_RIGHTS)
        call u_put32(ctrl, CMSG_DATA, Int(descriptor))
        call u_put64(msg, MSGHDR_CONTROL, u_address(ctrl))
        call u_put32(msg, MSGHDR_CONTROLLEN, CMSG_FD_SPACE)
    end
    return checked64(__lsl_qbe_call3(__lsl_symbol("sendmsg"), Int(handle), u_address(msg), 0))
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
        return -EINVAL
    end
    start = Int(offset)
    amount = Int(count)
    if start < 0 or amount < 0 or start > len(payload) or amount > len(payload) - start:
        return -EINVAL
    end
    iov = __lsl_byte_zeros(IOVEC_BYTES)
    ctrl = __lsl_byte_zeros(CMSG_FD_SPACE)
    msg = __lsl_byte_zeros(MSGHDR_BYTES)
    call u_put64(iov, IOVEC_BASE, u_address(payload) + start)
    call u_put64(iov, IOVEC_LENGTH, amount)
    call u_put64(msg, MSGHDR_IOV, u_address(iov))
    call u_put32(msg, MSGHDR_IOVLEN, 1)
    if Int(descriptor) >= 0:
        call u_put32(ctrl, CMSG_LENGTH, CMSG_FD_BYTES)
        call u_put32(ctrl, CMSG_LEVEL, SOL_SOCKET)
        call u_put32(ctrl, CMSG_TYPE, SCM_RIGHTS)
        call u_put32(ctrl, CMSG_DATA, Int(descriptor))
        call u_put64(msg, MSGHDR_CONTROL, u_address(ctrl))
        call u_put32(msg, MSGHDR_CONTROLLEN, CMSG_FD_SPACE)
    end
    return checked64(__lsl_qbe_call3(__lsl_symbol("sendmsg"), Int(handle), u_address(msg), 0))
end

function send_from(handle, payload, offset, count):
    return send_from_fd(handle, payload, offset, count, 0 - 1)
end

# Unmap a shared-memory pool once no buffer references it.
function munmap(address, size):
    pointer = Int(address)
    length = Int(size)
    if pointer <= 0 or length <= 0:
        return -EINVAL
    end
    return checked(__lsl_qbe_call2(__lsl_symbol("munmap"), pointer, length))
end

# A pipe with a nonblocking read end: [read, write], or [] on failure.
# This is the transport a clipboard uses — the owner writes the selection
# into the write end and we read it without ever blocking the frame loop.
function pipe_nonblock():
    fds = __lsl_byte_zeros(2 * INT_BYTES)
    rc = checked(__lsl_qbe_call1(__lsl_symbol("pipe"), u_address(fds)))
    if rc < 0:
        return []
    end
    call prepare(Int(u_get32(fds, 0)))
    call fcntl(Int(u_get32(fds, INT_BYTES)), F_SETFD, FD_CLOEXEC)
    return [Int(u_get32(fds, 0)), Int(u_get32(fds, INT_BYTES))]
end

# Receive up to `count` bytes into `payload`. Any descriptors that arrive
# are appended to the `fds` list. Returns the byte count, or a negative
# errno (-11 EAGAIN when nothing is pending).
function recv_fds(handle, payload, count, fds):
    if type(payload) != "ByteArray" or type(fds) != "List":
        return -EINVAL
    end
    amount = Int(count)
    if amount < 0 or amount > len(payload):
        return -EINVAL
    end
    # Same allocation-before-addresses rule as send_fd.
    iov = __lsl_byte_zeros(IOVEC_BYTES)
    ctrl = __lsl_byte_zeros(256)
    msg = __lsl_byte_zeros(MSGHDR_BYTES)
    call u_put64(iov, IOVEC_BASE, u_address(payload))
    call u_put64(iov, IOVEC_LENGTH, amount)
    call u_put64(msg, MSGHDR_IOV, u_address(iov))
    call u_put32(msg, MSGHDR_IOVLEN, 1)
    call u_put64(msg, MSGHDR_CONTROL, u_address(ctrl))
    call u_put32(msg, MSGHDR_CONTROLLEN, 256)
    n = checked64(__lsl_qbe_call3(__lsl_symbol("recvmsg"), Int(handle), u_address(msg), MSG_DONTWAIT))
    if n < 0:
        return n
    end
    # Walk the control messages: each cmsghdr is 4-byte aligned on macOS.
    total = Int(u_get32(msg, MSGHDR_CONTROLLEN))
    if total < 0:
        return -EINVAL
    elif total > 256:
        total = 256
    end
    off = 0
    while off <= total - CMSG_HEADER_BYTES:
        clen = Int(u_get32(ctrl, off))
        if clen < CMSG_HEADER_BYTES or clen > total - off:
            off = total
        else:
            if u_get32(ctrl, off + CMSG_LEVEL) == SOL_SOCKET and u_get32(ctrl, off + CMSG_TYPE) == SCM_RIGHTS:
                nfd = (clen - CMSG_HEADER_BYTES) // INT_BYTES
                k = 0
                while k < nfd:
                    received = Int(u_get32(ctrl, off + CMSG_DATA + k * INT_BYTES))
                    # Bound descriptors retained for one peer. A client can
                    # otherwise send SCM_RIGHTS forever and exhaust the
                    # compositor's process-wide fd table.
                    if len(fds) < 64:
                        call fcntl(received, F_SETFD, FD_CLOEXEC)
                        call fds.append(received)
                    else:
                        call close_fd(received)
                    end
                    k = k + 1
                end
            end
            off = off + (clen + CMSG_ALIGNMENT - 1) // CMSG_ALIGNMENT * CMSG_ALIGNMENT
        end
    end
    return n
end
