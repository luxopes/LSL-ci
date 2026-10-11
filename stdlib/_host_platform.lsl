load _host_linux_x86_64 as implementation

function tool(name):
    return implementation.tool(name)
end

function null_device():
    return implementation.null_device()
end
