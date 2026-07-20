# Explicit runtime environment/secrets boundary.

function get(name, default_value):
    value = getenv(name)
    if value == None:
        return default_value
    end
    return value
end

function has(name):
    return getenv(name) != None
end

function require(name):
    value = getenv(name)
    if value == None:
        Error(EnvironmentError: "missing environment variable " + name)
    end
    return value
end
