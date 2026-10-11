# Raw file-descriptor I/O over the __lsl_fd_* runtime builtins. Device
# nodes (framebuffer, evdev) need a persistent descriptor, byte-level
# reads and nonblocking mode, which the path-based readbytes/writebytes
# builtins cannot express.

# Veřejné API; operace hostitele poskytuje modul vybraný cílem.

load _fd_platform as implementation

read_only = implementation.read_only
write_only = implementation.write_only
read_write = implementation.read_write
create = implementation.create
truncate = implementation.truncate
nonblock = implementation.nonblock
again = implementation.again
af_unix = implementation.af_unix
sock_stream = implementation.sock_stream

function checked_path(path):
    return implementation.checked_path(path)
end

function checked_unix_path(path):
    return implementation.checked_unix_path(path)
end

function socket(domain, kind):
    return implementation.socket(domain, kind)
end

function connect_unix(path):
    return implementation.connect_unix(path)
end

function open(path, flags):
    return implementation.open(path, flags)
end

function read(handle, buffer, count):
    return implementation.read(handle, buffer, count)
end

function write(handle, buffer, count):
    return implementation.write(handle, buffer, count)
end

function seek(handle, position):
    return implementation.seek(handle, position)
end

function close(handle):
    return implementation.close(handle)
end

function ioctl(handle, request, buffer):
    return implementation.ioctl(handle, request, buffer)
end

function mmap(handle, length, offset):
    return implementation.mmap(handle, length, offset)
end

function read_all_limit(path, limit):
    return implementation.read_all_limit(path, limit)
end

function read_all(path):
    return implementation.read_all(path)
end

function read_text(path):
    return implementation.read_text(path)
end

function read_text_limit(path, limit):
    return implementation.read_text_limit(path, limit)
end
