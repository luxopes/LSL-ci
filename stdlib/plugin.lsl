# Pure-LSL process plugin ABI v1. Requests and responses are one JSON argv/stdout value.

load json

function request(executable, operation, payload):
    envelope = {"abi": 1, "operation": operation, "payload": payload}
    output = capture(executable, [json.encode(envelope)])
    if len(output) == 0:
        Error(PluginError: "plugin returned no JSON response")
    end
    response = json.decode(output)
    if response.get("abi", 0) != 1:
        Error(PluginError: "plugin ABI version mismatch")
    end
    if not response.get("ok", False):
        Error(PluginError: response.get("error", "plugin failed"))
    end
    return response.get("value", None)
end
