# Veřejné API; operace hostitele poskytuje modul vybraný cílem.

load _plugin_linux_x86_64 as implementation


function timeout_tool():
    return implementation.timeout_tool()
end

function checked_timeout(seconds):
    return implementation.checked_timeout(seconds)
end

function capture_with_timeout(executable, arguments, input_text, seconds):
    return implementation.capture_with_timeout(executable, arguments, input_text, seconds)
end

function capture_argv(executable, encoded):
    return implementation.capture_argv(executable, encoded)
end
