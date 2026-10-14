# Služby hostitele používané veřejnými knihovnami (Windows): systémové
# nástroje jsou v %SystemRoot%\System32 (curl.exe je součástí Windows 10+).

function system_root():
    root = __lsl_getenv("SystemRoot")
    if root == None or String(root) == "":
        return "C:\\Windows"
    end
    return String(root)
end

function tool(name):
    return system_root() + "\\System32\\" + String(name) + ".exe"
end

function null_device():
    return "NUL"
end
