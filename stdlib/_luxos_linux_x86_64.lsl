# luxos — the declarative system configuration engine for LuxOS.
#
# A LuxOS system is described by one declarative config (a dict) that names the
# desired hostname, locale, timezone, keymap, message of the day, the set of
# extra packages to keep installed, and the user accounts to ensure. Calling
# apply(config) converges the running system to that description and records a
# new generation so a later rollback() can restore it.
#
# It is deliberately file-based (no systemd: LuxOS runs no daemons), mirroring
# how the installer and machine.lsl write /etc directly. Package convergence is
# additive-safe: it installs declared packages that are missing and removes only
# packages that a PREVIOUS generation declared and this one drops — it never
# touches the base system.
#
# LUXOS_DRY_RUN=1 in the environment reports the plan without changing anything.

load os
load system
load env
load json

function validate_storage_path(path, label):
    call system.validate_absolute_path(path, label, False)
    if path.endswith("/"):
        Error(ValueError: label + " cannot end with /")
    end
end

generations_dir = env.get("LUXOS_GEN_DIR", "/var/lib/luxos/generations")
current_link = env.get("LUXOS_GEN_LINK", "/var/lib/luxos/current-generation")
call validate_storage_path(generations_dir, "generation directory")
call validate_storage_path(current_link, "generation link")

# A config with every field defaulted; callers override what they care about.
function defaults():
    return {
        "hostname": "luxos",
        "locale": "C",
        "timezone": "UTC",
        "keymap": "us",
        "motd": None,
        "packages": [],
        "users": []
    }
end

function is_dry():
    return env.get("LUXOS_DRY_RUN", "") != ""
end

function field(config, name, fallback):
    if name in config:
        return config[name]
    end
    return fallback
end

function validate_hostname(value):
    if type(value) != "String" or len(value) == 0 or len(value) > 253:
        Error(ValueError: "hostname must contain 1..253 ASCII characters")
    end
    for label in value.split("."):
        if len(label) == 0 or len(label) > 63 or label.startswith("-") or label.endswith("-"):
            Error(ValueError: "hostname contains an invalid label")
        end
        for character in label:
            code = ord(character)
            if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or character == "-"):
                Error(ValueError: "hostname contains an invalid character")
            end
        end
    end
end

function validate_identifier(value, label, maximum, allow_slash):
    if type(value) != "String" or len(value) == 0 or len(value) > maximum:
        Error(ValueError: label + " has an invalid length")
    end
    if value.startswith("/") or value.endswith("/"):
        Error(ValueError: label + " cannot start or end with /")
    end
    for component in value.split("/"):
        if component == "" or component == "." or component == "..":
            Error(ValueError: label + " contains an unsafe path component")
        end
    end
    for character in value:
        code = ord(character)
        valid = (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or character in "+-_.@"
        if allow_slash and character == "/":
            valid = True
        end
        if not valid:
            Error(ValueError: label + " contains an invalid character")
        end
    end
end

function validate_config(config):
    if type(config) != "Dictionary":
        Error(TypeError: "LuxOS configuration must be a Dictionary")
    end
    for name in config:
        if type(name) != "String" or name not in ["hostname", "locale", "timezone", "keymap", "motd", "packages", "users"]:
            Error(ValueError: "unknown LuxOS configuration field: " + String(name))
        end
    end
    call validate_hostname(field(config, "hostname", "luxos"))
    call validate_identifier(field(config, "locale", "C"), "locale", 128, False)
    call validate_identifier(field(config, "timezone", "UTC"), "timezone", 255, True)
    call validate_identifier(field(config, "keymap", "us"), "keymap", 128, False)

    motd = field(config, "motd", None)
    if motd != None and type(motd) != "String":
        Error(TypeError: "motd must be a String or None")
    elif motd != None and (__lsl_text_byte_length(String(motd)) > 1048576 or chr(0) in motd):
        Error(ValueError: "motd must not exceed 1 MiB or contain NUL")
    end

    packages = field(config, "packages", [])
    if type(packages) != "List" or len(packages) > 4096:
        Error(ValueError: "packages must be a List with at most 4096 entries")
    end
    seen_packages = {}
    for package in packages:
        call system.validate_package(package)
        if package in seen_packages:
            Error(ValueError: "duplicate package: " + package)
        end
        seen_packages[package] = True
    end

    users = field(config, "users", [])
    if type(users) != "List" or len(users) > 1024:
        Error(ValueError: "users must be a List with at most 1024 entries")
    end
    seen_users = {}
    for user in users:
        if type(user) != "Dictionary" or "name" not in user:
            Error(TypeError: "each user must be a Dictionary with a name")
        end
        for name in user:
            if type(name) != "String" or name not in ["name", "shell", "groups"]:
                Error(ValueError: "unknown user configuration field: " + String(name))
            end
        end
        name = user["name"]
        call system.validate_account_name(name, "user name")
        if name in seen_users:
            Error(ValueError: "duplicate user: " + name)
        end
        seen_users[name] = True
        shell = "/bin/lsh"
        if "shell" in user:
            shell = user["shell"]
        end
        call system.validate_absolute_path(shell, "user shell", False)
        groups = []
        if "groups" in user:
            groups = user["groups"]
        end
        if type(groups) != "List" or len(groups) > 256:
            Error(ValueError: "user groups must be a List with at most 256 entries")
        end
        call system.validate_account_list(groups, "user groups")
        seen_groups = {}
        for group in groups:
            if group in seen_groups:
                Error(ValueError: "duplicate user group: " + group)
            end
            seen_groups[group] = True
        end
    end
    return config
end

# ----- installed-package probes ----------------------------------------------

function apt_installed_names():
    names = {}
    command = system.required_tool("dpkg-query")
    output = system.capture_checked(command, ["-W", "-f=${Package}\n"], "query installed Debian packages")
    for line in output.split(chr(10)):
        trimmed = line.strip()
        if trimmed != "":
            names[trimmed] = True
        end
    end
    return names
end

function lux_installed_names():
    names = {}
    command = os.which_trusted("lux")
    if command == None:
        return names
    end
    output = system.capture_checked(command, ["list"], "query installed Lux packages")
    for line in output.split(chr(10)):
        trimmed = line.strip()
        if trimmed != "":
            names[trimmed] = True
        end
    end
    return names
end

# ----- generation bookkeeping -------------------------------------------------

# The manifest (config) declared by the current generation, or an empty default.
function previous_manifest():
    path = current_link + "/manifest.json"
    if not exists(path):
        return defaults()
    end
    safe:
        manifest = json.decode(readfile(path))
        call validate_config(manifest)
        return manifest
    end
    return defaults()
end

# Highest existing generation number (0 when none).
function latest_generation():
    highest = 0
    if not exists(generations_dir):
        return 0
    end
    output = system.capture_checked(system.required_tool("ls"), ["-1", "--", generations_dir], "list LuxOS generations")
    for entry in output.split(chr(10)):
        name = entry.strip()
        if name != "" and len(name) <= 18 and is_number(name):
            value = Int(name)
            if value > highest:
                highest = value
            end
        end
    end
    return highest
end

function is_number(text):
    if len(text) == 0:
        return False
    end
    for character in text:
        code = ord(character)
        if code < 48 or code > 57:
            return False
        end
    end
    return True
end

# Persist config as a new generation and point current-generation at it.
function record_generation(config):
    number = latest_generation() + 1
    directory = generations_dir + "/" + String(number)
    call system.ensure_directory(directory, "0755")
    call system.write_file(directory + "/manifest.json", json.encode(config) + chr(10), "0644")
    call system.run_checked(system.required_tool("ln"), ["-sfnT", "--", directory, current_link], "activate LuxOS generation")
    return number
end

# ----- the individual convergence steps --------------------------------------

function apply_identity(config, dry, changes):
    hostname = field(config, "hostname", "luxos")
    locale = field(config, "locale", "C")
    timezone = field(config, "timezone", "UTC")
    keymap = field(config, "keymap", "us")

    if not dry:
        hostname_command = os.which_trusted("hostname")
        if hostname_command != None:
            call system.run_checked(hostname_command, [hostname], "set hostname")
        end
        call system.write_file("/etc/hostname", hostname + chr(10), "0644")
        call system.write_file("/etc/hosts", "127.0.0.1 localhost" + chr(10) + "127.0.1.1 " + hostname + chr(10) + "::1 localhost ip6-localhost ip6-loopback" + chr(10), "0644")
        call system.write_file("/etc/locale.conf", "LANG=" + locale + chr(10), "0644")
        call system.write_file("/etc/default/locale", "LANG=" + locale + chr(10), "0644")
        call system.write_file("/etc/timezone", timezone + chr(10), "0644")
        zoneinfo = "/usr/share/zoneinfo/" + timezone
        if not exists(zoneinfo):
            Error(ValueError: "timezone does not exist: " + timezone)
        end
        call system.run_checked(system.required_tool("ln"), ["-sfnT", "--", zoneinfo, "/etc/localtime"], "set local timezone")
        call system.write_file("/etc/luxos/keymap", keymap + chr(10), "0644")
    end
    changes.append("identity: hostname=" + hostname + " locale=" + locale + " timezone=" + timezone + " keymap=" + keymap)
    return None
end

function apply_motd(config, dry, changes):
    motd = field(config, "motd", None)
    if motd == None:
        return None
    end
    if not dry:
        call system.write_file("/etc/motd", motd, "0644")
    end
    changes.append("motd: updated")
    return None
end

# Install declared-but-missing packages and remove packages a previous
# generation declared that this one drops. Never removes anything outside the
# tracked declared set.
function apply_packages(config, previous, dry, changes):
    declared = field(config, "packages", [])
    prior = field(previous, "packages", [])
    apt = apt_installed_names()
    lux = lux_installed_names()

    for name in declared:
        if not (name in apt) and not (name in lux):
            changes.append("install: " + name)
            if not dry:
                call system.install(name)
            end
        end
    end

    for name in prior:
        if not list_contains(declared, name) and ((name in apt) or (name in lux)):
            changes.append("remove: " + name)
            if not dry:
                call system.remove(name)
            end
        end
    end
    return None
end

function list_contains(items, value):
    for item in items:
        if item == value:
            return True
        end
    end
    return False
end

# Ensure each declared user exists with its shell and group memberships.
function apply_users(config, dry, changes):
    users = field(config, "users", [])
    for user in users:
        name = user["name"]
        shell = "/bin/lsh"
        if "shell" in user:
            shell = user["shell"]
        end
        groups = []
        if "groups" in user:
            groups = user["groups"]
        end
        changes.append("user: " + name + " groups=" + ", ".join(groups))
        if not dry:
            for group in groups:
                call system.ensure_group(group)
            end
            call system.ensure_user(name, shell, groups)
        end
    end
    return None
end

# ----- the public entry point -------------------------------------------------

# Converge the system to `config`. Returns the list of changes (also printed).
# Records a new generation unless this is a dry run.
function apply(config):
    call validate_config(config)
    dry = is_dry()
    previous = previous_manifest()
    changes = []

    call apply_identity(config, dry, changes)
    call apply_motd(config, dry, changes)
    call apply_packages(config, previous, dry, changes)
    call apply_users(config, dry, changes)

    if dry:
        print("luxos: dry run — no changes applied")
    else:
        number = record_generation(config)
        print("luxos: applied generation " + String(number))
    end
    for change in changes:
        print("  " + change)
    end
    return changes
end

# Apply the manifest whose path is in LUXOS_MANIFEST (used by `lux rollback`,
# which points it at a stored generation's manifest.json).
function apply_manifest():
    path = env.require("LUXOS_MANIFEST")
    call system.validate_absolute_path(path, "LuxOS manifest", False)
    return apply(json.decode(readfile(path)))
end
