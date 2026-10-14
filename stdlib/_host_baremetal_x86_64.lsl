# Bare metal: cesty systémových nástrojů. Logika je stejná jako na Linuxu (builtiny runtime, vrstva OS os_baremetal).

load _host_linux_x86_64 as shared

function tool(name):
    return shared.tool(name)
end

function null_device():
    return shared.null_device()
end
