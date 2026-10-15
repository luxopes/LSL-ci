# Katalog knihoven na Windows a macOS: stejné rozhraní jako
# catalog_linux_x86_64.lsl. Adresář se vypíše systémovým nástrojem
# (/bin/ls, na Windows cmd /c dir /b); přijímají se jen ověřená jména
# knihoven (ASCII), ostatní položky se zahodí.
load _platform as platform
load console
load package

function fail(message):
    Error(PackageError: message)
end

function windows():
    return platform.NAME.startswith("windows-")
end

# Běžný soubor (ne adresář).
function library_file(path):
    if not exists(path):
        return False
    end
    return not exists(String(path) + "/.")
end

function listing(directory):
    if windows():
        root = __lsl_getenv("SystemRoot")
        if root == None or root == "":
            root = "C:/Windows"
        end
        shell = String(root).replace(chr(92), "/") + "/System32/cmd.exe"
        output = capture_clean(shell, ["/d", "/c", "dir", "/b", "/a-d", String(directory).replace("/", chr(92))])
    else:
        output = capture_clean("/bin/ls", ["-1a", String(directory)])
    end
    if capture_status() != 0:
        call fail("cannot list library directory")
    end
    return output.replace(chr(13), "").split(chr(10))
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
