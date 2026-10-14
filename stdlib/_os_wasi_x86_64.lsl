# WebAssembly (WASI): hledání programů v PATH. Logika je stejná jako na Linuxu (builtiny runtime, vrstva OS os_wasi).

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
