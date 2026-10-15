# Hostitel překladače na Windows a macOS (cíle windows-*, macos-*): stejné
# rozhraní jako host_linux_x86_64.lsl bez systémových volání Linuxu.
# Cesty mají oddělovač "/" (Windows ho přijímá; cesta k programu se
# normalizuje), dočasné soubory jsou v %TEMP% nebo $TMPDIR, konfigurace se
# vyhodnocuje v čistém procesu s časovým limitem runtime (omezení paměti
# a souborů jako prlimit na Linuxu tu není).
load _platform as platform
load os

function windows():
    return platform.NAME.startswith("windows-")
end

function program_path():
    return executable_path().replace(chr(92), "/")
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

function resource_path(path):
    executable = program_path()
    binary_directory = dirname(executable)
    root_candidate = binary_directory + "/" + path
    if exists(root_candidate):
        return root_candidate
    end
    root_candidate = dirname(dirname(dirname(executable))) + "/" + path
    if exists(root_candidate):
        return root_candidate
    end
    prefix = dirname(binary_directory)
    prefix_bin = prefix + "/bin"
    if prefix == "/":
        prefix_bin = "/bin"
    end
    if binary_directory == prefix_bin:
        return prefix + "/lib/lsl/" + path
    end
    # Repository fallback is last so an attacker-controlled working directory
    # cannot shadow resources beside an installed executable.
    return path
end

function tool_path(repository_path, installed_name):
    if windows() and not installed_name.endswith(".exe"):
        installed_name = installed_name + ".exe"
    end
    binary_directory = dirname(program_path())
    adjacent = binary_directory + "/" + installed_name
    if exists(adjacent):
        return adjacent
    end
    prefix = dirname(binary_directory)
    prefix_bin = prefix + "/bin"
    if prefix == "/":
        prefix_bin = "/bin"
    end
    if binary_directory == prefix_bin:
        # An incomplete installation must not execute a same-named tool from
        # the caller's working directory.
        return adjacent
    end
    return repository_path
end

function required_system_tool(primary, fallback, label):
    if exists(primary):
        return primary
    elif exists(fallback):
        return fallback
    end
    Error(ProcessError: "trusted " + label + " executable is required")
end

function user_home():
    directory = home()
    if directory == None or directory == "":
        Error(PackageError: "HOME (USERPROFILE on Windows) is required for per-user library installation")
    end
    return directory
end

function temporary_root():
    names = ["TMPDIR"]
    if windows():
        names = ["TEMP", "TMP"]
    end
    for name in names:
        value = __lsl_getenv(name)
        if value != None and value != "":
            return String(value).replace(chr(92), "/")
        end
    end
    if windows():
        Error(FileError: "TEMP is not set")
    end
    return "/tmp"
end

# Soukromý dočasný adresář pro přeložený program (jméno z monotónního času,
# kolize řeší opakování).
function scratch_program_path():
    root = temporary_root()
    stamp = String(Int(__lsl_monotonic() * 1000000000.0))
    attempt = 0
    directory = root + "/lsl-program-" + stamp
    while __lsl_mkdir_private(directory) != 0:
        attempt += 1
        if attempt > 100:
            Error(FileError: "cannot create a private CLI scratch directory")
        end
        directory = root + "/lsl-program-" + stamp + "-" + String(attempt)
    end
    if windows():
        return directory + "/program.exe"
    end
    return directory + "/program"
end

function cleanup_program(path):
    call unlink(path)
    call rmdir(dirname(path))
end

# Verze z hlavičky knihovny AI ("# AI 1.2.0: ..."), jinak None.
function ai_header_version(path):
    first_line = ""
    safe:
        first_line = readfile(path).split(chr(10))[0]
    end
    if not first_line.startswith("# AI "):
        return None
    end
    text = first_line[5:len(first_line)]
    colon = text.find(":")
    if colon > 0:
        text = text[0:colon]
    end
    parts = text.strip().split(".")
    if len(parts) != 3:
        return None
    end
    numbers = []
    for part in parts:
        if part == "" or len(part) > 6:
            return None
        end
        for character in part:
            if "0123456789".find(character) < 0:
                return None
            end
        end
        numbers.append(Int(part))
    end
    return numbers
end

function version_newer(candidate, current):
    for position in rang(3):
        if candidate[position] != current[position]:
            return candidate[position] > current[position]
        end
    end
    return False
end

# load ai: knihovna aikit z registru (lsl update ai) má přednost před
# vestavěným modulem jen tehdy, když je prokazatelně novější. Jiné vestavěné
# moduly uživatelské knihovny nikdy nezastíní.
function module_path(name, owner_path, home, builtin):
    resolved = module_path_base(name, owner_path, home, builtin)
    if name != "ai" or not resolved.endswith("stdlib/ai.lsl") or home == None or home == "":
        return resolved
    end
    updated = home + "/.local/lib/lsl/stdlib/aikit.lsl"
    if not exists(updated):
        return resolved
    end
    updated_version = ai_header_version(updated)
    builtin_version = ai_header_version(resolved)
    if updated_version == None or builtin_version == None:
        return resolved
    end
    if version_newer(updated_version, builtin_version):
        return updated
    end
    return resolved
end

function module_path_base(name, owner_path, home, builtin):
    relative_name = name.replace(".", "/") + ".lsl"
    standard_path = "stdlib/" + relative_name
    executable = program_path()
    binary_directory = dirname(executable)
    # Installed/repository resources adjacent to the compiler are trusted ahead
    # of the source directory, so local json.lsl/config.lsl files cannot shadow
    # security-critical built-in modules.
    root_candidate = binary_directory + "/" + standard_path
    if exists(root_candidate):
        return root_candidate
    end
    root_candidate = dirname(dirname(dirname(executable))) + "/" + standard_path
    if exists(root_candidate):
        return root_candidate
    end
    prefix = dirname(binary_directory)
    prefix_bin = prefix + "/bin"
    if prefix == "/":
        prefix_bin = "/bin"
    end
    installed_layout = binary_directory == prefix_bin
    installed_path = prefix + "/lib/lsl/" + standard_path
    if installed_layout:
        if exists(installed_path) or builtin:
            # A missing built-in fails at its trusted prefix path. Local/user
            # modules remain available for names outside the built-in set.
            return installed_path
        end
    end
    local_path = dirname(owner_path) + "/" + relative_name
    if exists(local_path):
        return local_path
    end
    # Compiler-focused tests live under tests/, while implementation modules stay
    # exclusively in compiler/pure/. Prefer a path rooted beside the compiler.
    test_owner = owner_path.startswith("tests/") or owner_path.find("/tests/") >= 0
    compiler_path = dirname(dirname(dirname(executable))) + "/compiler/pure/" + relative_name
    if test_owner and exists(compiler_path):
        return compiler_path
    end
    compiler_path = "compiler/pure/" + relative_name
    if test_owner and exists(compiler_path):
        return compiler_path
    end
    # Development compiler copied outside the tree: cwd is an explicit fallback,
    # never a precedence path for installed binaries.
    if not installed_layout:
        for extension_root in [binary_directory + "/extensions/", dirname(dirname(dirname(executable))) + "/extensions/", "extensions/"]:
            if exists(extension_root + relative_name):
                return extension_root + relative_name
            end
        end
    end
    if exists(standard_path):
        return standard_path
    end
    # Registry libraries are user-owned and never shadow built-in modules.
    if home != None and home != "":
        user_path = home + "/.local/lib/lsl/stdlib/" + relative_name
        if exists(user_path):
            return user_path
        end
    end
    # Preserve the deterministic missing-file diagnostic path.
    if installed_layout:
        return installed_path
    end
    return standard_path
end

# Cíl, pro který byl tento program přeložen (modul platformy se volí podle
# cíle): compiler přeložený pro arm64 překládá implicitně pro arm64.
function target_name():
    return platform.NAME
end

function home():
    if windows():
        profile = __lsl_getenv("USERPROFILE")
        if profile == None:
            return None
        end
        return String(profile).replace(chr(92), "/")
    end
    return __lsl_getenv("HOME")
end

# Systémové nástroje správce balíčků: macOS /usr/bin, Windows System32.
function tool(name):
    if windows():
        root = __lsl_getenv("SystemRoot")
        if root == None or root == "":
            root = "C:/Windows"
        end
        return String(root).replace(chr(92), "/") + "/System32/" + String(name) + ".exe"
    end
    return "/usr/bin/" + String(name)
end

function null_device():
    if windows():
        return "NUL"
    end
    return "/dev/null"
end

# Vyhodnocení konfigurace v čistém procesu s limitem 30 s (runtime ukončí
# proces po termínu, stav 124).
function run_config(evaluator):
    return __lsl_run_timeout(evaluator, [], 30)
end

# Surový režim terminálu přes stty (jen macOS; na Windows řádkový vstup).
function interactive_tool():
    if windows():
        return None
    end
    return os.which_trusted("stty")
end

function prompt_enter(command):
    saved = os.capture_argv_clean(command, ["-g"]).strip()
    if capture_status() != 0 or len(saved) == 0 or len(saved) > 4096:
        Error(CliError: "cannot read terminal state")
    end
    if os.run_argv_clean(command, ["-echo", "-icanon", "min", "1", "time", "0"]) != 0:
        Error(CliError: "cannot enter terminal raw mode")
    end
    return saved
end

function prompt_leave(command, saved):
    return os.run_argv_clean(command, [saved])
end
