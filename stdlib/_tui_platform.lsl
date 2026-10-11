# Veřejné API; operace hostitele poskytuje modul vybraný cílem.

load _tui_linux_x86_64 as implementation


function stty_tool():
    return implementation.stty_tool()
end

function enter_state():
    return implementation.enter_state()
end

function restore_state(saved):
    return implementation.restore_state(saved)
end

function dimensions():
    return implementation.dimensions()
end

function wait_readable(timeout):
    return implementation.wait_readable(timeout)
end
