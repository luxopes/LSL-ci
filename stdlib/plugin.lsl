# Pure-LSL process plugin ABI v1. Requests and responses are one JSON argv/stdout value.

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

function request(executable, operation, payload):
    envelope = {"abi": 1, "operation": operation, "payload": payload}
    return response(capture(executable, [json.encode(envelope)]))
end

# Streaming variant for payloads larger than Linux MAX_ARG_STRLEN. The worker
# reads one JSON document from stdin and still returns one JSON stdout value.
function request_input(executable, operation, payload):
    envelope = {"abi": 1, "operation": operation, "payload": payload}
    return response(capture_input(executable, [], json.encode(envelope)))
end
