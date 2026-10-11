load _plugin_platform as transport
# Pure-LSL process plugin ABI v1. Requests use JSON stdin and responses use
# JSON stdout, so payloads and secrets do not appear in process argv.

load json

function response(output):
    if len(output) == 0:
        Error(PluginError: "plugin returned no JSON response")
    elif __lsl_text_byte_length(String(output)) > 4194304:
        Error(PluginError: "plugin response exceeds 4 MiB")
    end
    value = json.decode(output)
    if type(value) != "Dictionary":
        Error(PluginError: "plugin response must be a JSON object")
    end
    if value.get("abi", 0) != 1:
        Error(PluginError: "plugin ABI version mismatch")
    end
    if not value.get("ok", False):
        detail = String(value.get("error", "plugin failed"))
        if len(detail) > 4096:
            detail = detail[0:4096]
        end
        Error(PluginError: detail)
    end
    return value.get("value", None)
end

function timeout_tool():
    return transport.timeout_tool()
end

function checked_timeout(seconds):
    return transport.checked_timeout(seconds)
end

function capture_with_timeout(executable, arguments, input_text, seconds):
    return transport.capture_with_timeout(executable, arguments, input_text, seconds)
end

function checked_response(output):
    status = capture_status()
    if status != 0:
        detail = capture_stderr().strip()
        if detail == "":
            detail = "plugin exited with status " + String(status)
        end
        Error(PluginError: detail)
    end
    return response(output)
end

function operation_name(operation):
    action = String(operation)
    if len(action) == 0 or len(action) > 256:
        Error(PluginError: "plugin operation must contain 1..256 characters")
    end
    for character in action:
        code = ord(character)
        if code < 32 or code == 127:
            Error(PluginError: "plugin operation contains a control character")
        end
    end
    return action
end

function request_with_timeout(executable, operation, payload, seconds):
    action = operation_name(operation)
    envelope = {"abi": 1, "operation": action, "payload": payload}
    encoded = json.encode(envelope)
    if __lsl_text_byte_length(String(encoded)) > 4194304:
        Error(PluginError: "plugin request exceeds 4 MiB")
    end
    output = capture_with_timeout(executable, [], encoded, seconds)
    return checked_response(output)
end

function request(executable, operation, payload):
    return request_with_timeout(executable, operation, payload, 30)
end

# Compatibility alias retained for callers that already selected stdin.
function request_input(executable, operation, payload):
    return request(executable, operation, payload)
end

# Explicit legacy transport for old workers. It is unsafe for secrets and
# omezený limitem argumentů hostitele; nové integrace používají request().
function request_argv(executable, operation, payload):
    envelope = {"abi": 1, "operation": operation_name(operation), "payload": payload}
    encoded = json.encode(envelope)
    output = transport.capture_argv(executable, encoded)
    return checked_response(output)
end
