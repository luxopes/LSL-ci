# Explicit runtime environment/secrets boundary.

function checked_name(name):
    if type(name) != "String" or len(name) == 0 or len(name) > 255 or chr(0) in name or "=" in name:
        Error(EnvironmentError: "environment name must contain 1..255 characters without NUL or =")
    end
    return name
end

function get(name, default_value):
    value = __lsl_getenv(checked_name(name))
    if value == None:
        return default_value
    end
    return value
end

function has(name):
    return __lsl_getenv(checked_name(name)) != None
end

function require(name):
    name = checked_name(name)
    value = __lsl_getenv(name)
    if value == None:
        Error(EnvironmentError: "missing environment variable " + name)
    end
    return value
end
