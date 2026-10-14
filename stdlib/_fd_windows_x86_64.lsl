# Windows: I/O přes deskriptory runtime (HANDLE, vrstva OS Windows). Logika
# je stejná jako na Linuxu (_fd_linux_x86_64 nad __lsl_fd_*), konstanty dodá
# modul platformy cíle. Sockety Unixu runtime na Windows nemá (FileError).

load _fd_linux_x86_64 as shared

read_only = shared.read_only
write_only = shared.write_only
read_write = shared.read_write
create = shared.create
truncate = shared.truncate
nonblock = shared.nonblock
again = shared.again
af_unix = shared.af_unix
sock_stream = shared.sock_stream

function checked_path(path):
    return shared.checked_path(path)
end

function checked_unix_path(path):
    return shared.checked_unix_path(path)
end

function socket(domain, kind):
    return shared.socket(domain, kind)
end

function connect_unix(path):
    return shared.connect_unix(path)
end

function open(path, flags):
    return shared.open(path, flags)
end

function read(handle, buffer, count):
    return shared.read(handle, buffer, count)
end

function write(handle, buffer, count):
    return shared.write(handle, buffer, count)
end

function seek(handle, position):
    return shared.seek(handle, position)
end

function close(handle):
    return shared.close(handle)
end

function ioctl(handle, request, buffer):
    return shared.ioctl(handle, request, buffer)
end

function mmap(handle, length, offset):
    return shared.mmap(handle, length, offset)
end

function read_all_limit(path, limit):
    return shared.read_all_limit(path, limit)
end

function read_all(path):
    return shared.read_all(path)
end

function read_text(path):
    return shared.read_text(path)
end

function read_text_limit(path, limit):
    return shared.read_text_limit(path, limit)
end
