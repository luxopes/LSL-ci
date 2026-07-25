# Explicit runtime environment/secrets boundary.

function get(name, default_value):
    value = __lsl_getenv(name)
    if value == None:
        return default_value
    end
    return value
end

function has(name):
    return __lsl_getenv(name) != None
end

function require(name):
    value = __lsl_getenv(name)
    if value == None:
        Error(EnvironmentError: "missing environment variable " + name)
    end
    return value
end
