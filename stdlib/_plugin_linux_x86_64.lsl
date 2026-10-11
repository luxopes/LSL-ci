
function timeout_tool():
    if exists("/usr/bin/timeout"):
        return "/usr/bin/timeout"
    elif exists("/bin/timeout"):
        return "/bin/timeout"
    end
    Error(PluginError: "a trusted timeout executable is required for plugin isolation")
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
    timeout = checked_timeout(seconds)
    wrapped = ["--signal=TERM", "--kill-after=1s", "--", String(timeout) + "s", String(executable)]
    for argument in arguments:
        wrapped.append(String(argument))
    end
    return capture_input_clean(timeout_tool(), wrapped, String(input_text))
end

function capture_argv(executable, encoded):
    if __lsl_text_byte_length(String(encoded)) > 131071:
        Error(PluginError: "legacy argv plugin request exceeds Linux MAX_ARG_STRLEN")
    end
    wrapped = ["--signal=TERM", "--kill-after=1s", "--", "30s", String(executable), encoded]
    output = capture_clean(timeout_tool(), wrapped)
    return output
end
