load _platform as platform
load time

MAX_CUDA_BINARY_ELEMENTS = 2000000

function session_send(handle, text, deadline):
    data = String(text)
    count = __lsl_text_byte_length(data)
    offset = 0
    # String payload is inline at +16. Keep data rooted for the entire syscall.
    while offset < count:
        sent = __lsl_syscall6(platform.SYS_SENDTO, Int(handle), __lsl_address(data) + 16 + offset, count - offset, platform.MSG_NOSIGNAL + platform.MSG_DONTWAIT, 0, 0)
        if sent > 0:
            offset += sent
        elif sent == -11 or sent == -4:
            if monotonic() >= Float(deadline):
                Error(CudaTimeoutError: "CUDA session write timed out")
            end
            call time.sleep(0.001)
        else:
            Error(CudaProtocolError: "CUDA session connection closed while writing")
        end
    end
end

function session_read(handle, size, deadline):
    count = Int(size)
    if count < 0 or count > MAX_CUDA_BINARY_ELEMENTS * 8:
        Error(CudaProtocolError: "CUDA session response exceeds its byte limit")
    end
    bytes = __lsl_byte_zeros(count)
    offset = 0
    while offset < count:
        received = __lsl_syscall6(platform.SYS_RECVFROM, Int(handle), __lsl_data_address(bytes) + offset, count - offset, platform.MSG_DONTWAIT, 0, 0)
        if received > 0:
            offset += received
        elif received == -11 or received == -4:
            if monotonic() >= Float(deadline):
                Error(CudaTimeoutError: "CUDA session read timed out")
            end
            call time.sleep(0.001)
        else:
            Error(CudaProtocolError: "CUDA session connection closed while reading")
        end
    end
    return __lsl_text_from_bytes(bytes, 0, count)
end

function thread_id():
    return __lsl_syscall(platform.SYS_GETTID, 0, 0, 0, 0)
end

function close_on_exec(handle):
    return __lsl_syscall(platform.SYS_FCNTL, Int(handle), platform.F_SETFD, platform.FD_CLOEXEC, 0)
end

function worker_path():
    executable_directory = dirname(executable_path())
    for candidate in [executable_directory + "/lsl-cuda-worker", executable_directory + "/cuda/lsl-cuda-worker", "/usr/local/bin/lsl-cuda-worker", "/usr/bin/lsl-cuda-worker"]:
        if exists(candidate):
            return candidate
        end
    end
    return None
end

function dirname(path):
    slash = -1
    index = 0
    while index < len(path):
        if path[index] == "/":
            slash = index
        end
        index += 1
    end
    if slash < 0:
        return "."
    elif slash == 0:
        return "/"
    end
    return path[0:slash]
end
