# Služby hostitele používané veřejnými knihovnami.

function tool(name):
    return "/usr/bin/" + String(name)
end

function null_device():
    return "/dev/null"
end
