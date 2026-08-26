# Pure-LSL process plugin ABI v1. Requests use JSON stdin and responses use
# JSON stdout, so payloads and secrets do not appear in process argv.

load json

function response(output):
    if len(output) == 0:
        Error(PluginError: "plugin returned no JSON response")
    end
    value = json.decode(output)
    if value.get("abi", 0) != 1:
        Error(PluginError: "plugin ABI version mismatch")
    end
    if not value.get("ok", False):
        Error(PluginError: value.get("error", "plugin failed"))
    end
    return value.get("value", None)
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

function request(executable, operation, payload):
    envelope = {"abi": 1, "operation": operation, "payload": payload}
    output = capture_input(executable, [], json.encode(envelope))
    return checked_response(output)
end

# Compatibility alias retained for callers that already selected stdin.
function request_input(executable, operation, payload):
    return request(executable, operation, payload)
end

# Explicit legacy transport for old workers. It is unsafe for secrets and
# bounded by Linux MAX_ARG_STRLEN; new integrations must use request().
function request_argv(executable, operation, payload):
    envelope = {"abi": 1, "operation": operation, "payload": payload}
    output = capture(executable, [json.encode(envelope)])
    return checked_response(output)
end
