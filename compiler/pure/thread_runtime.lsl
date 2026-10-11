# Kompatibilní vstup; strojová implementace je explicitně Linux x86_64.

load thread_runtime_linux_x86_64 as implementation

function emit_mutex_pair(output, lock_label, wait_label, unlock_label, offset, guarded):
    return implementation.emit_mutex_pair(output, lock_label, wait_label, unlock_label, offset, guarded)
end

function emit_mutex(output):
    return implementation.emit_mutex(output)
end

function emit_entry_lookup(output, found_label, missing_label):
    return implementation.emit_entry_lookup(output, found_label, missing_label)
end

function emit_slot_address(output):
    return implementation.emit_slot_address(output)
end

function emit_spawn(output):
    return implementation.emit_spawn(output)
end

function emit_entry(output):
    return implementation.emit_entry(output)
end

function emit_signal_handler(output):
    return implementation.emit_signal_handler(output)
end

function emit_join(output):
    return implementation.emit_join(output)
end

function emit_cpu_count(output):
    return implementation.emit_cpu_count(output)
end

function emit_all(output):
    return implementation.emit_all(output)
end
