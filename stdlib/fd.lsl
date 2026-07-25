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

# Read a whole file through the descriptor path. Unlike readfile this
# also works for procfs/sysfs and device nodes whose stat size is zero.
function read_all(path):
    handle = open(path, read_only)
    chunk = ByteArray()
    index = 0
    while index < 4096:
        chunk.append(0)
        index += 1
    end
    collected = ByteArray()
    loop:
        count = read(handle, chunk, 4096)
        if count == again:
            continue
        end
        if count == 0:
            break
        end
        index = 0
        while index < count:
            collected.append(chunk[index])
            index += 1
        end
    end
    call close(handle)
    return collected
end

function read_text(path):
    data = read_all(path)
    parts = []
    index = 0
    total = len(data)
    while index < total:
        parts.append(chr(data[index]))
        index += 1
    end
    return "".join(parts)
end
