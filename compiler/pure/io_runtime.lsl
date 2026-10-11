# Kompatibilní vstup; strojová implementace je explicitně Linux x86_64.

load io_runtime_linux_x86_64 as implementation

function emit_heap_type_validation(output):
    return implementation.emit_heap_type_validation(output)
end

function emit_path_validation(output):
    return implementation.emit_path_validation(output)
end

function emit_string_validation(output):
    return implementation.emit_string_validation(output)
end

function emit_cstring(output):
    return implementation.emit_cstring(output)
end

function emit_stdin_buffer(output):
    return implementation.emit_stdin_buffer(output)
end

function emit_stdout_buffer(output):
    return implementation.emit_stdout_buffer(output)
end

function emit_input(output):
    return implementation.emit_input(output)
end

function emit_readfile(output):
    return implementation.emit_readfile(output)
end

function emit_readbytes(output):
    return implementation.emit_readbytes(output)
end

function emit_write_all(output):
    return implementation.emit_write_all(output)
end

function emit_writefile(output):
    return implementation.emit_writefile(output)
end

function emit_appendfile(output):
    return implementation.emit_appendfile(output)
end

function emit_writebytes(output):
    return implementation.emit_writebytes(output)
end

function emit_fd_io(output):
    return implementation.emit_fd_io(output)
end

function emit_raster(output):
    return implementation.emit_raster(output)
end

function emit_gpu(output):
    return implementation.emit_gpu(output)
end

function emit_paths(output):
    return implementation.emit_paths(output)
end

function emit_exists(output):
    return implementation.emit_exists(output)
end

function emit_terminal_state(output):
    return implementation.emit_terminal_state(output)
end

function emit_error_output(output):
    return implementation.emit_error_output(output)
end

function emit_error_literal(output, label, message):
    return implementation.emit_error_literal(output, label, message)
end

function emit_text_helpers(output):
    return implementation.emit_text_helpers(output)
end

function emit_lazy(output, text_used, input_used):
    return implementation.emit_lazy(output, text_used, input_used)
end

function emit_all(output):
    return implementation.emit_all(output)
end
