# Windows: izolace pluginů spouští program pod nástrojem timeout (coreutils),
# který Windows nemá. Pluginy s časovým limitem na Windows hlásí chybu.

function timeout_tool():
    Error(PluginError: "plugin isolation with a timeout is not available on Windows")
    return ""
end

function checked_timeout(seconds):
    value = Int(seconds)
    if value < 1 or value > 3600:
        Error(PluginError: "plugin timeout must be between 1 and 3600 seconds")
    end
    return value
end

function capture_with_timeout(executable, arguments, input_text, seconds):
    if type(arguments) != "List" or len(arguments) > 4096:
        Error(PluginError: "plugin arguments must be a bounded List")
    end
    call checked_timeout(seconds)
    return timeout_tool()
end

function capture_argv(executable, encoded):
    return timeout_tool()
end
