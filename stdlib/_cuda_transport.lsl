# Veřejné API; operace hostitele poskytuje modul vybraný cílem.

load _cuda_linux_x86_64 as implementation

MAX_CUDA_BINARY_ELEMENTS = implementation.MAX_CUDA_BINARY_ELEMENTS

function session_send(handle, text, deadline):
    return implementation.session_send(handle, text, deadline)
end

function session_read(handle, size, deadline):
    return implementation.session_read(handle, size, deadline)
end

function thread_id():
    return implementation.thread_id()
end

function close_on_exec(handle):
    return implementation.close_on_exec(handle)
end

function worker_path():
    return implementation.worker_path()
end

function dirname(path):
    return implementation.dirname(path)
end
