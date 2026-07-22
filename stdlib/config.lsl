# Pure helpers for declarative configuration modules.

function option(expected_type, default_value, description):
    return {"type": expected_type, "default": default_value, "description": description, "required": False}
end

function required(expected_type, description):
    return {"type": expected_type, "default": None, "description": description, "required": True}
end

function mkOverride(priority, value):
    return {"__priority": priority, "value": value}
end

function mkDefault(value):
    return mkOverride(100, value)
end

function mkForce(value):
    return mkOverride(1000, value)
end

function lazy(thunk):
    return {"__lazy": thunk}
end

function mkIf(condition, value):
    if condition:
        return value
    end
    return {"__omit": True}
end
