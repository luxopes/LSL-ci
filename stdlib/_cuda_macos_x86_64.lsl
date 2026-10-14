# macOS: pracovní proces CUDA (lsl-cuda-worker) pro macOS není (NVIDIA CUDA
# macOS nepodporuje). worker_path vrátí None, takže cuda hlásí nedostupné GPU
# stejně jako Linux bez nainstalovaného workeru; spojení nikdy nevznikne.

MAX_CUDA_BINARY_ELEMENTS = 2000000

function session_send(handle, text, deadline):
    Error(CudaProtocolError: "CUDA sessions are not available on macOS")
end

function session_read(handle, size, deadline):
    Error(CudaProtocolError: "CUDA sessions are not available on macOS")
end

function thread_id():
    return __lsl_qbe_call0(__lsl_symbol("pthread_self"))
end

function close_on_exec(handle):
    return 0
end

function worker_path():
    return None
end

function dirname(path):
    separator = -1
    index = 0
    while index < len(path):
        if path[index] == "/" or path[index] == "\\":
            separator = index
        end
        index += 1
    end
    if separator < 0:
        return "."
    elif separator == 0:
        return path[0:1]
    end
    return path[0:separator]
end
