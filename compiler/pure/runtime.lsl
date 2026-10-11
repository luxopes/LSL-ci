# Rozhraní backendu do cílového runtime. Výběr je explicitní, bez odhadu hosta.

load abi_x86_64
load runtime_linux_x86_64

function select(target):
    if not abi_x86_64.matches(target) or not runtime_linux_x86_64.matches(target):
        Error(CompileError: "incompatible target runtime descriptor")
    end
    return target["runtime"]
end

function require_selected(selected):
    if selected != "lsl-runtime-linux-x86_64-v1":
        Error(CompileError: "unsupported target runtime: " + String(selected))
    end
end

function emit_all(selected, output):
    call require_selected(selected)
    call runtime_linux_x86_64.emit_all(output)
end

function emit_entry(selected, output, globals_bytes, registry_bytes, registry_mask):
    call require_selected(selected)
    call runtime_linux_x86_64.emit_entry(output, globals_bytes, registry_bytes, registry_mask)
end

function emit_lazy(selected, output, text_used, input_used):
    call require_selected(selected)
    call runtime_linux_x86_64.emit_lazy(output, text_used, input_used)
end

function emit_exit(selected, output):
    call require_selected(selected)
    call runtime_linux_x86_64.emit_exit(output)
end

function emit_finish(selected, output):
    call require_selected(selected)
    call runtime_linux_x86_64.emit_finish(output)
end

function emit_write_number(selected, output):
    call require_selected(selected)
    call runtime_linux_x86_64.emit_write_number(output)
end

function emit_syscall(selected, output):
    call require_selected(selected)
    call runtime_linux_x86_64.emit_syscall(output)
end

# Sloty popisují význam thread state, jejich umístění vlastní cílový runtime.
ERROR = "error"
ERROR_FLAG = "error_flag"
STACK_TOP = "stack_top"

function state_bytes(selected):
    call require_selected(selected)
    return runtime_linux_x86_64.state_bytes()
end

function thread_load(selected, output, register, slot):
    call require_selected(selected)
    call runtime_linux_x86_64.thread_load(output, register, slot)
end

function thread_store(selected, output, slot, register):
    call require_selected(selected)
    call runtime_linux_x86_64.thread_store(output, slot, register)
end

function thread_store_immediate(selected, output, slot, value):
    call require_selected(selected)
    call runtime_linux_x86_64.thread_store_immediate(output, slot, value)
end

function thread_compare(selected, output, slot, value):
    call require_selected(selected)
    call runtime_linux_x86_64.thread_compare(output, slot, value)
end

function emit_gc_poll(selected, output, done):
    call require_selected(selected)
    call runtime_linux_x86_64.emit_gc_poll(output, done)
end

function prepare_static_write(selected, output):
    call require_selected(selected)
    call runtime_linux_x86_64.prepare_static_write(output)
end

function emit_static_write(selected, output):
    call require_selected(selected)
    call runtime_linux_x86_64.emit_static_write(output)
end

function release_input(selected, output):
    call require_selected(selected)
    call runtime_linux_x86_64.release_input(output)
end
