# Instalátor LSL pro Windows a macOS: zkopíruje nástroje z bin/ a soubory
# lib/lsl balíku do prefixu (bez spravovaných generací a rollbacku, ty jsou
# zatím jen na Linuxu). Výchozí prefix: macOS /usr/local, Windows
# %LOCALAPPDATA%/Programs/LSL. Cesty používají "/".
load _platform as platform
load install_files

function windows():
    return platform.NAME.startswith("windows-")
end

function normalized(path):
    return String(path).replace(chr(92), "/")
end

function dirname(path):
    slash = -1
    index = 0
    while index < len(path):
        if path[index] == "/":
            slash = index
        end
        index += 1
    end
    if slash < 0:
        return "."
    elif slash == 0:
        return "/"
    elif slash == 2 and path[1] == ":":
        return path[0:3]
    end
    return path[0:slash]
end

function program_path():
    return normalized(executable_path())
end

# Kořen balíku: lib/lsl vedle bin/ (rozbalený archiv nebo instalace),
# ve vývojovém checkoutu repozitář.
function source_root():
    executable = program_path()
    repository = dirname(dirname(dirname(executable)))
    if exists(repository + "/compiler/pure/install.lsl"):
        return repository
    end
    return dirname(dirname(executable)) + "/lib/lsl"
end

SOURCE_ROOT = source_root()

function source_path(relative):
    return SOURCE_ROOT + "/" + relative
end

function executable_name(name):
    if windows():
        return name + ".exe"
    end
    return name
end

function absolute(path):
    if windows():
        return len(path) >= 3 and path[1] == ":" and path[2] == "/"
    end
    return path.startswith("/")
end

function default_prefix():
    if windows():
        local = __lsl_getenv("LOCALAPPDATA")
        if local == None or local == "":
            Error(InstallError: "LOCALAPPDATA is not set; pass the installation prefix")
        end
        return normalized(local) + "/Programs/LSL"
    end
    return "/usr/local"
end

# Vytvoří adresář včetně rodičů (mkdir existující adresář ponechá).
function make_directories(path):
    if exists(path):
        return 0
    end
    parent = dirname(path)
    if parent != path and parent != "." and not exists(parent):
        call make_directories(parent)
    end
    call mkdir(path)
    if not exists(path):
        Error(InstallError: "cannot create directory: " + path)
    end
    return 0
end

function copy_file(source, destination):
    if not exists(source):
        Error(InstallError: "package file is missing: " + source)
    end
    call writebytes(destination, readbytes(source))
end

prefix = arg(1)
if prefix == None:
    prefix = default_prefix()
end
if type(prefix) != "String" or len(prefix) == 0 or chr(0) in prefix:
    Error(InstallError: "installation prefix must be an absolute path without NUL")
end
prefix = normalized(prefix)
while len(prefix) > 3 and prefix.endswith("/"):
    prefix = prefix[0:len(prefix) - 1]
end
if not absolute(prefix):
    Error(InstallError: "installation prefix must be an absolute path")
end
for component in prefix.split("/"):
    if component == "..":
        Error(InstallError: "installation prefix must not contain parent traversal")
    end
end

library = prefix + "/lib/lsl"
for directory in [prefix + "/bin", library + "/compiler/pure", library + "/compiler/qbe/windows-x86_64", library + "/compiler/qbe/windows-arm64", library + "/stdlib", library + "/runtime/arch", library + "/tools", library + "/docs/developer_guides"]:
    call make_directories(directory)
end

binary_directory = dirname(program_path())
tools = ["lsl", "lslc", "luxir", "lsl-configure", "lsl-install"]
for name in tools:
    call copy_file(binary_directory + "/" + executable_name(name), prefix + "/bin/" + executable_name(name))
end
call copy_file(source_path("compiler/qbe/runtime.o"), library + "/compiler/qbe/runtime.o")
for name in install_files.TARGET_FILES:
    if exists(source_path(name)):
        call copy_file(source_path(name), library + "/" + name)
    end
end
for name in install_files.SOURCES:
    call copy_file(source_path("compiler/pure/" + name), library + "/compiler/pure/" + name)
end
for name in install_files.STANDARD_MODULES:
    call copy_file(source_path("stdlib/" + name), library + "/stdlib/" + name)
end
for name in install_files.MANUAL_PAGES:
    call copy_file(source_path("docs/developer_guides/" + name + ".md"), library + "/docs/developer_guides/" + name + ".md")
end
call copy_file(source_path("docs/developer_guides/SOURCE.json"), library + "/docs/developer_guides/SOURCE.json")
# Značka pro lsl update: aktualizuje se jen instalace z lsl-install, ne
# rozbalený archiv ani zdrojový checkout.
call writefile(library + "/INSTALLATION", "lsl-install" + chr(10))
print "installed LSL 0.10.2 into", prefix
if windows():
    print "Add " + prefix.replace("/", chr(92)) + chr(92) + "bin to PATH to use lsl in new terminals."
else:
    print "Make sure " + prefix + "/bin is in PATH."
end
