# Kompatibilní vstup; strojová implementace je explicitně Linux x86_64.

load native_runtime_linux_x86_64 as implementation

function emit_print_int(output):
    return implementation.emit_print_int(output)
end

function emit_print_string(output):
    return implementation.emit_print_string(output)
end

function emit_int_to_string(output):
    return implementation.emit_int_to_string(output)
end

function emit_string_to_int(output):
    return implementation.emit_string_to_int(output)
end

function emit_chr_ord(output):
    return implementation.emit_chr_ord(output)
end

function emit_print_float(output):
    return implementation.emit_print_float(output)
end

function emit_float_to_string(output):
    return implementation.emit_float_to_string(output)
end

function emit_clock_source(output, label, clock_id):
    return implementation.emit_clock_source(output, label, clock_id)
end

function emit_clock(output):
    return implementation.emit_clock(output)
end

function emit_sleep(output):
    return implementation.emit_sleep(output)
end

function emit_print_scalar_names(output):
    return implementation.emit_print_scalar_names(output)
end

function emit_all(output):
    return implementation.emit_all(output)
end

function emit_lazy(output, text_used, input_used):
    return implementation.emit_lazy(output, text_used, input_used)
end

function print_int():
    return implementation.print_int()
end
