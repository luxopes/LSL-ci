# macOS: terminál přes stty jako na Linuxu, čekání na vstup přes poll()
# (ppoll je syscall Linuxu).

load _tui_linux_x86_64 as shared

function stty_tool():
    return shared.stty_tool()
end

function enter_state():
    return shared.enter_state()
end

function restore_state(saved):
    return shared.restore_state(saved)
end

function dimensions():
    return shared.dimensions()
end

# 1, když stdin lze číst, 0 po timeout ms (poll z libSystem).
function wait_readable(timeout):
    descriptor = __lsl_byte_zeros(8)
    descriptor[4] = 1
    ready = __lsl_qbe_call3(__lsl_symbol("poll"), Int(__lsl_data_address(descriptor)), 1, Int(timeout)) & 4294967295
    if ready >= 2147483648:
        return -1
    end
    return ready
end
