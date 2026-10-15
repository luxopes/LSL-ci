# Katalog knihoven na Windows a macOS: stejné rozhraní jako
# catalog_linux_x86_64.lsl. Adresář vypíše runtime (__lsl_list_directory:
# FindFirstFileW, readdir); přijímají se jen ověřená jména knihoven.
load console
load package

function fail(message):
    Error(PackageError: message)
end

# Běžný soubor (ne adresář): výpis adresáře na souboru selže. Trik
# "cesta/." Windows nepoužije (cestu normalizuje).
function library_file(path):
    if not exists(path):
        return False
    end
    directory = False
    safe:
        call __lsl_list_directory(String(path))
        directory = True
    end
    return not directory
end

function listing(directory):
    names = []
    try:
        names = __lsl_list_directory(String(directory))
    else:
        call fail("cannot list library directory")
    end
    return names
end

function directory_names(directory):
    if not exists(directory):
        return []
    end
    result = []
    entries = 0
    for name in listing(directory):
        entries += 1
        if entries > 16384:
            call fail("library directory contains too many entries")
        end
        if name.endswith(".lsl"):
            name = name[0:len(name) - 4]
            if package.valid_name(name) and library_file(directory + "/" + name + ".lsl"):
                result.append(name)
            end
        end
    end
    call result.sort()
    return result
end
