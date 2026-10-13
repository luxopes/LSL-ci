load _platform as platform
load console
load fd
load package

function fail(message):
    Error(PackageError: message)
end

function library_file(path):
    encoded = __lsl_byte_zeros(__lsl_text_byte_length(String(path)) + 1)
    for index in rang(len(encoded) - 1):
        encoded[index] = __lsl_text_byte(String(path), index)
    end
    metadata = __lsl_byte_zeros(platform.STAT_BYTES)
    status = __lsl_syscall(platform.SYS_NEWFSTATAT, platform.AT_FDCWD, __lsl_data_address(encoded), __lsl_data_address(metadata), 0)
    if status == -2 or status == -20:
        return False
    elif status < 0:
        call fail("cannot inspect library: " + console.clean(path))
    end
    return ((metadata[platform.STAT_MODE] + metadata[platform.STAT_MODE + 1] * 256) & platform.S_IFMT) == platform.S_IFREG
end

function directory_names(directory):
    # getdents64 is bounded, accepts only validated module basenames and closes
    # the descriptor on every error. Listing does not create HOME directories.
    if not exists(directory):
        return []
    end
    handle = fd.open(directory, platform.O_DIRECTORY + platform.O_CLOEXEC)
    result = []
    failure = None
    try:
        buffer = __lsl_byte_zeros(32768)
        entries = 0
        loop:
            count = __lsl_syscall(platform.SYS_GETDENTS64, handle, __lsl_data_address(buffer), len(buffer), 0)
            if count < 0:
                call fail("cannot list library directory")
            elif count == 0:
                break
            end
            offset = 0
            while offset < count:
                if count - offset < platform.DIRENT64_MIN_BYTES:
                    call fail("invalid directory entry")
                end
                size = buffer[offset + platform.DIRENT64_RECLEN] + buffer[offset + platform.DIRENT64_RECLEN + 1] * 256
                if size < platform.DIRENT64_MIN_BYTES or size > count - offset:
                    call fail("invalid directory record length")
                end
                limit = offset + platform.DIRENT64_NAME
                while limit < offset + size and buffer[limit] != 0:
                    limit += 1
                end
                name = __lsl_text_from_bytes(buffer, offset + platform.DIRENT64_NAME, limit - offset - platform.DIRENT64_NAME)
                if name.endswith(".lsl"):
                    name = name[0:len(name) - 4]
                    if package.valid_name(name) and library_file(directory + "/" + name + ".lsl"):
                        result.append(name)
                    end
                end
                entries += 1
                if entries > 16384:
                    call fail("library directory contains too many entries")
                end
                offset += size
            end
        end
    else:
        failure = last_error()
    end
    call fd.close(handle)
    if failure != None:
        call fail(String(failure))
    end
    call result.sort()
    return result
end
