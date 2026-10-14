# WebAssembly (WASI): konfigurace LuxOS potřebuje procesy, které WASI nemá.

load _luxos_linux_x86_64 as shared

generations_dir = shared.generations_dir
current_link = shared.current_link

function validate_storage_path(path, label):
    return shared.validate_storage_path(path, label)
end

function defaults():
    return shared.defaults()
end

function is_dry():
    return shared.is_dry()
end

function field(config, name, fallback):
    return shared.field(config, name, fallback)
end

function validate_hostname(value):
    return shared.validate_hostname(value)
end

function validate_identifier(value, label, maximum, allow_slash):
    return shared.validate_identifier(value, label, maximum, allow_slash)
end

function validate_config(config):
    return shared.validate_config(config)
end

function apt_installed_names():
    return shared.apt_installed_names()
end

function lux_installed_names():
    return shared.lux_installed_names()
end

function previous_manifest():
    return shared.previous_manifest()
end

function latest_generation():
    return shared.latest_generation()
end

function is_number(text):
    return shared.is_number(text)
end

function record_generation(config):
    return shared.record_generation(config)
end

function apply_identity(config, dry, changes):
    return shared.apply_identity(config, dry, changes)
end

function apply_motd(config, dry, changes):
    return shared.apply_motd(config, dry, changes)
end

function apply_packages(config, previous, dry, changes):
    return shared.apply_packages(config, previous, dry, changes)
end

function list_contains(items, value):
    return shared.list_contains(items, value)
end

function apply_users(config, dry, changes):
    return shared.apply_users(config, dry, changes)
end

function apply(config):
    return shared.apply(config)
end

function apply_manifest():
    return shared.apply_manifest()
end
