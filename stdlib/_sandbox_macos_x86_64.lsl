# Izolace procesu na macOS (sandbox-exec, Seatbelt). Program vidí jen
# systémové knihovny, svůj soubor a cesty z policy (read jen pro čtení,
# write pro čtení a zápis); síť jen s profilem server. macOS nemá jmenné
# prostory: cesty schopností program nedostane jako /input/N, ale v proměnných
# LSL_SANDBOX_INPUT_N a LSL_SANDBOX_OUTPUT_N (input_path, output_path).
# Prostředí je jinak prázdné. Časový limit hlídá runtime (SIGTERM, po
# sekundě SIGKILL); limit paměti macOS neumí (bez cgroups, RLIMIT_AS
# ignoruje), policy memory se jen ověří.

function system_tool(primary, fallback, label):
    if exists(primary):
        return primary
    elif exists(fallback):
        return fallback
    end
    Error(SandboxError: "trusted " + String(label) + " executable is required")
end

function available():
    return exists("/usr/bin/sandbox-exec") and exists("/usr/bin/env") and (exists("/bin/realpath") or exists("/usr/bin/realpath"))
end

function is_active():
    return __lsl_getenv("LSL_SANDBOX") == "1"
end

function profile():
    if not is_active():
        return None
    end
    return __lsl_getenv("LSL_SANDBOX_PROFILE")
end

function capability_path(kind, index):
    number = index
    if number < 0:
        Error(SandboxError: kind.lower() + " capability index cannot be negative")
    end
    value = __lsl_getenv("LSL_SANDBOX_" + kind + "_" + String(number))
    if value == None:
        Error(SandboxError: kind.lower() + " capability " + String(number) + " is not granted")
    end
    return String(value)
end

function input_path(index):
    return capability_path("INPUT", index)
end

function output_path(index):
    return capability_path("OUTPUT", index)
end

# BSD realpath nezná -e; neexistující cestu odmítne i bez něj.
function canonical_path(path, label):
    realpath = system_tool("/bin/realpath", "/usr/bin/realpath", "realpath")
    result = capture_clean(realpath, ["--", String(path)])
    if capture_status() != 0 or not result.endswith(chr(10)):
        Error(SandboxError: "cannot resolve " + String(label) + ": " + String(path))
    end
    result = result[0:len(result) - 1]
    if len(result) == 0 or chr(10) in result or chr(13) in result or "\"" in result or "\\" in result:
        Error(SandboxError: String(label) + " has an unsupported path")
    end
    return result
end

function checked_capabilities(policy, name):
    values = policy.get(name, [])
    if type(values) != "List":
        Error(SandboxError: String(name) + " capabilities must be a List")
    elif len(values) > 64:
        Error(SandboxError: String(name) + " capability count exceeds 64")
    end
    result = []
    for value in values:
        if type(value) != "String":
            Error(SandboxError: String(name) + " capability paths must be Strings")
        end
        result.append(canonical_path(value, String(name) + " capability"))
    end
    return result
end

function checked_arguments(arguments):
    if type(arguments) != "List" or len(arguments) > 4096:
        Error(SandboxError: "sandbox arguments must be a List of at most 4096 Strings")
    end
    result = []
    for argument in arguments:
        if type(argument) != "String":
            Error(SandboxError: "sandbox arguments must be Strings")
        end
        result.append(argument)
    end
    return result
end

function checked_policy(value):
    if value == None:
        value = {}
    elif type(value) != "Dictionary":
        Error(SandboxError: "sandbox policy must be a Dictionary")
    end
    allowed = ["profile", "timeout", "memory", "read", "write"]
    for key in value.keys():
        if key not in allowed:
            Error(SandboxError: "unknown sandbox policy key: " + String(key))
        end
    end
    selected = value.get("profile", "strict")
    if selected != "strict" and selected != "server":
        Error(SandboxError: "sandbox profile must be strict or server")
    end
    wall_seconds = Int(value.get("timeout", 30))
    if wall_seconds < 1 or wall_seconds > 3600:
        Error(SandboxError: "sandbox timeout must be between 1 and 3600 seconds")
    end
    memory_bytes = Int(value.get("memory", 1073741824))
    if memory_bytes < 67108864 or memory_bytes > 8589934592:
        Error(SandboxError: "sandbox memory must be between 64 MiB and 8 GiB")
    end
    return {
        "profile": selected,
        "timeout": wall_seconds,
        "memory": memory_bytes,
        "read": checked_capabilities(value, "read"),
        "write": checked_capabilities(value, "write")
    }
end

function quoted(path):
    return "\"" + String(path) + "\""
end

# Profil Seatbelt: vše zakázané kromě spuštění programu, čtení systémových
# knihoven a dyld cache, cest schopností a (server) sítě.
function seatbelt_profile(program, checked):
    rules = "(version 1)(deny default)"
    rules += "(allow process-exec (literal " + quoted(program) + ") (literal \"/usr/bin/env\"))"
    rules += "(allow process-fork)"
    rules += "(allow signal (target self))"
    rules += "(allow sysctl-read)"
    rules += "(allow file-read-metadata)"
    # Jen výpis kořene (env ho při startu čte), nic pod ním.
    rules += "(allow file-read-data (literal \"/\"))"
    rules += "(allow file-read* (literal " + quoted(program) + ") (literal \"/usr/bin/env\") (subpath \"/usr/lib\") (subpath \"/System\") (subpath \"/private/var/db/dyld\") (subpath \"/private/preboot/Cryptexes\") (literal \"/dev/null\") (literal \"/dev/random\") (literal \"/dev/urandom\") (literal \"/dev/zero\"))"
    rules += "(allow file-write-data (literal \"/dev/null\"))"
    for path in checked["read"]:
        rules += "(allow file-read* (subpath " + quoted(path) + "))"
    end
    for path in checked["write"]:
        rules += "(allow file-read* file-write* (subpath " + quoted(path) + "))"
    end
    if checked["profile"] == "server":
        rules += "(allow network*)"
    end
    return rules
end

function command(executable, arguments, policy):
    checked = checked_policy(policy)
    program = canonical_path(executable, "sandbox executable")
    argv = checked_arguments(arguments)
    result = [system_tool("/usr/bin/sandbox-exec", "/usr/bin/sandbox-exec", "sandbox-exec"), "-p", seatbelt_profile(program, checked), "/usr/bin/env", "-i", "LSL_SANDBOX=1", "LSL_SANDBOX_PROFILE=" + checked["profile"]]
    index = 0
    while index < len(checked["read"]):
        result.append("LSL_SANDBOX_INPUT_" + String(index) + "=" + checked["read"][index])
        index += 1
    end
    index = 0
    while index < len(checked["write"]):
        result.append("LSL_SANDBOX_OUTPUT_" + String(index) + "=" + checked["write"][index])
        index += 1
    end
    result.append(program)
    result.extend(argv)
    return {"argv": result, "policy": checked}
end

function run(executable, arguments, policy):
    prepared = command(executable, arguments, policy)
    argv = prepared["argv"]
    return __lsl_run_timeout(argv[0], argv[1:len(argv)], prepared["policy"]["timeout"])
end
