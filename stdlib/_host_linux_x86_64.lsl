# Služby hostitele používané veřejnými knihovnami.

# Systémový nástroj z /usr/bin, jinak z /bin (Android nemá /usr; /bin je
# tam /system/bin).
function tool(name):
    primary = "/usr/bin/" + String(name)
    if not exists(primary) and exists("/bin/" + String(name)):
        return "/bin/" + String(name)
    end
    return primary
end

function null_device():
    return "/dev/null"
end
