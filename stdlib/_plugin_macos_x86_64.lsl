# macOS: izolace pluginů s časovým limitem bez coreutils timeout: runtime
# potomka po limitu ukončí sám (__lsl_capture_input_timeout, stav 124 jako
# u timeout).

# Časový limit zajišťuje runtime, žádný vnější nástroj.
function timeout_tool():
    return "lsl-runtime"
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
    timeout = checked_timeout(seconds)
    values = []
    for argument in arguments:
        values.append(String(argument))
    end
    return __lsl_capture_input_timeout(String(executable), values, String(input_text), timeout)
end

function capture_argv(executable, encoded):
    if __lsl_text_byte_length(String(encoded)) > 32766:
        Error(PluginError: "legacy argv plugin request exceeds the command line limit")
    end
    return __lsl_capture_input_timeout(String(executable), [String(encoded)], "", 30)
end
