# Kompatibilní vstup; strojová implementace je explicitně Linux x86_64.

load process_runtime_linux_x86_64 as implementation

function emit_process_validation(output):
    return implementation.emit_process_validation(output)
end

function emit_clear_capture_cloexec(output, descriptor):
    return implementation.emit_clear_capture_cloexec(output, descriptor)
end

function emit_process_error_data(output, label, message):
    return implementation.emit_process_error_data(output, label, message)
end

function emit_run(output):
    return implementation.emit_run(output)
end

function emit_executable_path(output):
    return implementation.emit_executable_path(output)
end

function emit_getenv(output):
    return implementation.emit_getenv(output)
end

function emit_stream_callback(output):
    return implementation.emit_stream_callback(output)
end

function emit_capture(output):
    return implementation.emit_capture(output)
end

function emit_test_fd_fault(output):
    return implementation.emit_test_fd_fault(output)
end

function emit_capture_status(output):
    return implementation.emit_capture_status(output)
end

function emit_capture_stderr(output):
    return implementation.emit_capture_stderr(output)
end

function emit_all(output):
    return implementation.emit_all(output)
end
