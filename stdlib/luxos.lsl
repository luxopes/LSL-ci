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

generations_dir = env.get("LUXOS_GEN_DIR", "/var/lib/luxos/generations")
current_link = env.get("LUXOS_GEN_LINK", "/var/lib/luxos/current-generation")

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

# ----- installed-package probes ----------------------------------------------

function apt_installed_names():
    names = {}
    for line in os.capture_argv("dpkg-query", ["-W", "-f=${Package}\n"]).split(chr(10)):
        trimmed = line.strip()
        if trimmed != "":
            names[trimmed] = True
        end
    end
    return names
end

function lux_installed_names():
    names = {}
    for line in os.capture_argv("lux", ["list"]).split(chr(10)):
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
        return json.decode(readfile(path))
    end
    return defaults()
end

# Highest existing generation number (0 when none).
function latest_generation():
    highest = 0
    if not exists(generations_dir):
        return 0
    end
    for entry in os.capture_argv("ls", ["-1", generations_dir]).split(chr(10)):
        name = entry.strip()
        if name != "" and is_number(name):
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
    safe:
        call os.run_argv("ln", ["-sfn", directory, current_link])
    end
    return number
end

# ----- the individual convergence steps --------------------------------------

function apply_identity(config, dry, changes):
    hostname = field(config, "hostname", "luxos")
    locale = field(config, "locale", "C")
    timezone = field(config, "timezone", "UTC")
    keymap = field(config, "keymap", "us")

    if not dry:
        safe:
            call os.run_argv("/bin/hostname", [hostname])
        end
        call system.write_file("/etc/hostname", hostname + chr(10), "0644")
        call system.write_file("/etc/hosts", "127.0.0.1 localhost" + chr(10) + "127.0.1.1 " + hostname + chr(10) + "::1 localhost ip6-localhost ip6-loopback" + chr(10), "0644")
        call system.write_file("/etc/locale.conf", "LANG=" + locale + chr(10), "0644")
        call system.write_file("/etc/default/locale", "LANG=" + locale + chr(10), "0644")
        call system.write_file("/etc/timezone", timezone + chr(10), "0644")
        zoneinfo = "/usr/share/zoneinfo/" + timezone
        if exists(zoneinfo):
            safe:
                call os.run_argv("ln", ["-sfn", zoneinfo, "/etc/localtime"])
            end
        end
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
                safe:
                    call system.install(name)
                end
            end
        end
    end

    for name in prior:
        if not list_contains(declared, name) and ((name in apt) or (name in lux)):
            changes.append("remove: " + name)
            if not dry:
                safe:
                    call system.remove(name)
                end
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
                safe:
                    call system.ensure_group(group)
                end
            end
            safe:
                call system.ensure_user(name, shell, groups)
            end
        end
    end
    return None
end

# ----- the public entry point -------------------------------------------------

# Converge the system to `config`. Returns the list of changes (also printed).
# Records a new generation unless this is a dry run.
function apply(config):
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
    return apply(json.decode(readfile(path)))
end
