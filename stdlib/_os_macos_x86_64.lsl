# macOS: hledání programů v PATH.
# Logika je stejná jako na Linuxu (POSIX cesty a nástroje, builtiny runtime),
# konstanty dodá modul platformy cíle; platí pro x86_64 i arm64.

load _os_linux_x86_64 as shared

function checked_argument(value, label):
    return shared.checked_argument(value, label)
end

function which(name):
    return shared.which(name)
end

function which_trusted(name):
    return shared.which_trusted(name)
end
