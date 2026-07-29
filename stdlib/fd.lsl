# Raw file-descriptor I/O over the __lsl_fd_* runtime builtins. Device
# nodes (framebuffer, evdev) need a persistent descriptor, byte-level
# reads and nonblocking mode, which the path-based readbytes/writebytes
# builtins cannot express.

read_only = 0
write_only = 1
read_write = 2
create = 64
truncate = 512
nonblock = 2048

# Negative result the runtime returns when a nonblocking read has no data.
again = -11

# socket(2) domains and types.
af_unix = 1
sock_stream = 1

function socket(domain, kind):
    handle = __lsl_fd_socket(domain, kind)
    if handle < 0:
        Error(FileError: "cannot create socket (" + String(handle) + ")")
    end
    return handle
end

# Connect to a unix stream socket path; returns a nonblocking handle.
function connect_unix(path):
    handle = socket(af_unix, sock_stream + nonblock)
    address = ByteArray()
    address.append(af_unix)
    address.append(0)
    for character in path:
        address.append(ord(character))
    end
    address.append(0)
    result = __lsl_fd_connect(handle, address, len(address))
    # -115 is EINPROGRESS, which a nonblocking unix connect may report
    # even though the socket is usable immediately.
    if result < 0 and result != -115:
        call close(handle)
        Error(FileError: "cannot connect " + path + " (" + String(result) + ")")
    end
    return handle
end

function open(path, flags):
    handle = __lsl_fd_open(path, flags)
    if handle < 0:
        Error(FileError: "cannot open " + path + " (" + String(handle) + ")")
    end
    return handle
end

# Returns the byte count, 0 on end of file, or fd.again for an empty
# nonblocking read. The runtime clamps count to the buffer length.
function read(handle, buffer, count):
    result = __lsl_fd_read(handle, buffer, count)
    if result == again or result == -4:
        return again
    end
    if result < 0:
        Error(FileError: "read failed (" + String(result) + ")")
    end
    return result
end

function write(handle, buffer, count):
    result = __lsl_fd_write(handle, buffer, count)
    if result < 0:
        Error(FileError: "write failed (" + String(result) + ")")
    end
    return None
end

function seek(handle, position):
    result = __lsl_fd_seek(handle, position)
    if result < 0:
        Error(FileError: "seek failed (" + String(result) + ")")
    end
    return result
end

function close(handle):
    call __lsl_fd_close(handle)
    return None
end

# ioctl(2). The buffer's bytes are the request argument (kernel reads and
# writes them in place); an empty buffer passes NULL. Returns the raw
# result, negative errno included — device control flows branch on it.
function ioctl(handle, request, buffer):
    return __lsl_fd_ioctl(handle, buffer, request)
end

# mmap(2) with PROT_READ|PROT_WRITE and MAP_SHARED: maps `length` bytes of
# the descriptor at `offset` and returns the raw address (negative errno
# on failure). Pair with __lsl_mem_pack to write pixels into the mapping.
function mmap(handle, length, offset):
    return __lsl_fd_mmap(handle, length, offset)
end

# Read a whole file through the descriptor path. Unlike readfile this
# also works for procfs/sysfs and device nodes whose stat size is zero.
function read_all(path):
    handle = open(path, read_only)
    chunk = __lsl_byte_zeros(4096)
    collected = __lsl_byte_zeros(0)
    total = 0
    loop:
        count = read(handle, chunk, 4096)
        if count == again:
            continue
        end
        if count == 0:
            break
        end
        # Grow-by-copy through the native kernel: appending byte by byte
        # cost ~700 ns per byte, which dominated every /proc sample.
        grown = __lsl_byte_zeros(total + count)
        call __lsl_byte_copy(grown, collected, 0, 0, total)
        call __lsl_byte_copy(grown, chunk, total, 0, count)
        collected = grown
        total = total + count
    end
    call close(handle)
    return collected
end

function read_text(path):
    # One native copy instead of a string per byte: with chr()+join this
    # cost hundreds of milliseconds per second of Monitor sampling.
    data = read_all(path)
    return __lsl_text_from_bytes(data, 0, len(data))
end
