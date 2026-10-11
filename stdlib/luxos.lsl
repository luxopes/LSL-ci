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

# Veřejné API; operace hostitele poskytuje modul vybraný cílem.

load _luxos_platform as implementation

generations_dir = implementation.generations_dir
current_link = implementation.current_link

function validate_storage_path(path, label):
    return implementation.validate_storage_path(path, label)
end

function defaults():
    return implementation.defaults()
end

function is_dry():
    return implementation.is_dry()
end

function field(config, name, fallback):
    return implementation.field(config, name, fallback)
end

function validate_hostname(value):
    return implementation.validate_hostname(value)
end

function validate_identifier(value, label, maximum, allow_slash):
    return implementation.validate_identifier(value, label, maximum, allow_slash)
end

function validate_config(config):
    return implementation.validate_config(config)
end

function apt_installed_names():
    return implementation.apt_installed_names()
end

function lux_installed_names():
    return implementation.lux_installed_names()
end

function previous_manifest():
    return implementation.previous_manifest()
end

function latest_generation():
    return implementation.latest_generation()
end

function is_number(text):
    return implementation.is_number(text)
end

function record_generation(config):
    return implementation.record_generation(config)
end

function apply_identity(config, dry, changes):
    return implementation.apply_identity(config, dry, changes)
end

function apply_motd(config, dry, changes):
    return implementation.apply_motd(config, dry, changes)
end

function apply_packages(config, previous, dry, changes):
    return implementation.apply_packages(config, previous, dry, changes)
end

function list_contains(items, value):
    return implementation.list_contains(items, value)
end

function apply_users(config, dry, changes):
    return implementation.apply_users(config, dry, changes)
end

function apply(config):
    return implementation.apply(config)
end

function apply_manifest():
    return implementation.apply_manifest()
end
