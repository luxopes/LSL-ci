# WebAssembly (WASI): terminál v surovém režimu WASI preview1 neumí.

function stty_tool():
    Error(TUIError: "terminal raw mode is not available in WebAssembly (WASI)")
end

function enter_state():
    Error(TUIError: "terminal raw mode is not available in WebAssembly (WASI)")
end

function restore_state(saved):
    Error(TUIError: "terminal raw mode is not available in WebAssembly (WASI)")
end

function dimensions():
    return []
end

function wait_readable(timeout):
    return 1
end
