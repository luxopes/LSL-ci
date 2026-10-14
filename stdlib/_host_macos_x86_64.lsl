# macOS: systémové nástroje (curl je v /usr/bin).
# Logika je stejná jako na Linuxu (POSIX cesty a nástroje, builtiny runtime),
# konstanty dodá modul platformy cíle; platí pro x86_64 i arm64.

load _host_linux_x86_64 as shared

function tool(name):
    return shared.tool(name)
end

function null_device():
    return shared.null_device()
end
