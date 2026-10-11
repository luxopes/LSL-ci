# Kompatibilní vstup; strojová implementace je explicitně Linux x86_64.

load native_plugin_runtime_linux_x86_64 as implementation

function emit_validation(output):
    return implementation.emit_validation(output)
end

function emit_open(output):
    return implementation.emit_open(output)
end

function emit_access(output):
    return implementation.emit_access(output)
end

function emit_call_close(output):
    return implementation.emit_call_close(output)
end

function emit_all(output):
    return implementation.emit_all(output)
end
