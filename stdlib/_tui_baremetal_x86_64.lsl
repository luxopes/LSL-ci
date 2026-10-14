# Bare metal: terminál v surovém režimu bez OS není.

function stty_tool():
    Error(TUIError: "terminal raw mode is not available on bare metal")
end

function enter_state():
    Error(TUIError: "terminal raw mode is not available on bare metal")
end

function restore_state(saved):
    Error(TUIError: "terminal raw mode is not available on bare metal")
end

function dimensions():
    return []
end

function wait_readable(timeout):
    return 1
end
