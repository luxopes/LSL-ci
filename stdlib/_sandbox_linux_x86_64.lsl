# Capability-oriented process sandbox for Linux x86-64.
#
# The sandbox is deliberately out-of-process. A program sees an empty tmpfs
# root, a minimal /proc and /dev, its own read-only executable, and only the
# host paths explicitly bound into /input or /output. Network namespaces are
# private unless the caller selects the server profile. Resource ceilings are
# applied outside bubblewrap so they also cover sandbox setup.

function system_tool(primary, fallback, label):
    if exists(primary):
        return primary
    elif exists(fallback):
        return fallback
    end
    Error(SandboxError: "trusted " + String(label) + " executable is required")
end

function available():
    bubblewrap = exists("/usr/bin/bwrap") or exists("/bin/bwrap")
    timeout = exists("/usr/bin/timeout") or exists("/bin/timeout")
    prlimit = exists("/usr/bin/prlimit") or exists("/bin/prlimit")
    realpath = exists("/usr/bin/realpath") or exists("/bin/realpath")
    systemd = exists("/usr/bin/systemd-run") or exists("/bin/systemd-run")
    environment = exists("/usr/bin/env") or exists("/bin/env")
    return bubblewrap and timeout and prlimit and realpath and systemd and environment
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

function input_path(index):
    number = index
    if number < 0:
        Error(SandboxError: "input capability index cannot be negative")
    end
    return "/input/" + String(number)
end

function output_path(index):
    number = index
    if number < 0:
        Error(SandboxError: "output capability index cannot be negative")
    end
    return "/output/" + String(number)
end

function canonical_path(path, label):
    realpath = system_tool("/usr/bin/realpath", "/bin/realpath", "realpath")
    result = capture_clean(realpath, ["-e", "--", String(path)])
    if capture_status() != 0 or not result.endswith(chr(10)):
        Error(SandboxError: "cannot resolve " + String(label) + ": " + String(path))
    end
    result = result[0:len(result) - 1]
    if len(result) == 0 or chr(10) in result or chr(13) in result:
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

function command(executable, arguments, policy):
    checked = checked_policy(policy)
    program = canonical_path(executable, "sandbox executable")
    argv = checked_arguments(arguments)
    bubblewrap = system_tool("/usr/bin/bwrap", "/bin/bwrap", "bubblewrap")
    result = [
        bubblewrap,
        "--die-with-parent", "--new-session", "--unshare-all", "--unshare-user"
    ]
    if checked["profile"] == "server":
        result.append("--share-net")
    end
    result.extend([
        "--disable-userns", "--cap-drop", "ALL", "--clearenv",
        "--tmpfs", "/", "--proc", "/proc", "--dev", "/dev",
        "--dir", "/tmp", "--dir", "/app",
        "--ro-bind", program, "/app/program",
        "--setenv", "LSL_SANDBOX", "1",
        "--setenv", "LSL_SANDBOX_PROFILE", checked["profile"]
    ])
    reads = checked["read"]
    if len(reads) > 0:
        result.extend(["--dir", "/input"])
        index = 0
        while index < len(reads):
            result.extend(["--ro-bind", reads[index], input_path(index)])
            index += 1
        end
    end
    writes = checked["write"]
    if len(writes) > 0:
        result.extend(["--dir", "/output"])
        index = 0
        while index < len(writes):
            result.extend(["--bind", writes[index], output_path(index)])
            index += 1
        end
    end
    result.extend(["--chdir", "/app", "--", "/app/program"])
    result.extend(argv)
    return {"argv": result, "policy": checked}
end

function run(executable, arguments, policy):
    prepared = command(executable, arguments, policy)
    checked = prepared["policy"]
    timeout = system_tool("/usr/bin/timeout", "/bin/timeout", "timeout")
    prlimit = system_tool("/usr/bin/prlimit", "/bin/prlimit", "prlimit")
    systemd = system_tool("/usr/bin/systemd-run", "/bin/systemd-run", "systemd-run")
    environment = system_tool("/usr/bin/env", "/bin/env", "env")
    wall_seconds = checked["timeout"]
    limits = [
        "--signal=TERM", "--kill-after=1s", "--", String(wall_seconds) + "s",
        prlimit,
        "--as=" + String(checked["memory"]),
        "--cpu=" + String(wall_seconds),
        "--core=0", "--fsize=16777216", "--nofile=64",
        "--stack=67108864", "--"
    ]
    limits.extend(prepared["argv"])
    scope = [
        "--user", "--scope", "--quiet", "--collect",
        "-p", "TasksMax=64",
        "-p", "MemoryMax=" + String(checked["memory"]),
        "-p", "MemorySwapMax=0",
        "--", timeout
    ]
    scope.extend(limits)
    runtime_directory = __lsl_getenv("XDG_RUNTIME_DIR")
    bus = __lsl_getenv("DBUS_SESSION_BUS_ADDRESS")
    if runtime_directory == None or runtime_directory == "" or bus == None or bus == "":
        Error(SandboxError: "a systemd user session is required for cgroup limits")
    end
    # Only the two values required to reach the user's systemd manager cross
    # this boundary. bubblewrap clears them before executing untrusted code.
    clean_environment = [
        "-i",
        "XDG_RUNTIME_DIR=" + String(runtime_directory),
        "DBUS_SESSION_BUS_ADDRESS=" + String(bus),
        systemd
    ]
    clean_environment.extend(scope)
    return run_clean(environment, clean_environment)
end
