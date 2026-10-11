# Veřejné API; operace hostitele poskytuje modul vybraný cílem.

load update_install_linux_x86_64 as implementation

TOOLS = implementation.TOOLS
RELAY = implementation.RELAY

function fail(message):
    return implementation.fail(message)
end

function cstring(value):
    return implementation.cstring(value)
end

function little(buffer, offset, width):
    return implementation.little(buffer, offset, width)
end

function dirname(path):
    return implementation.dirname(path)
end

function metadata(path):
    return implementation.metadata(path)
end

function owned_directory(path):
    return implementation.owned_directory(path)
end

function directory(path):
    return implementation.directory(path)
end

function public_directory(path):
    return implementation.public_directory(path)
end

function private_work(parent):
    return implementation.private_work(parent)
end

function sync_path(path):
    return implementation.sync_path(path)
end

function rename(source, destination):
    return implementation.rename(source, destination)
end

function link(target, destination):
    return implementation.link(target, destination)
end

function read_link(path):
    return implementation.read_link(path)
end

function switch_link(target, destination, scratch):
    return implementation.switch_link(target, destination, scratch)
end

function tool(name):
    return implementation.tool(name)
end

function bounded(executable, arguments, maximum, seconds):
    return implementation.bounded(executable, arguments, maximum, seconds)
end

function bounded_stream(executable, arguments, maximum, seconds, on_chunk):
    return implementation.bounded_stream(executable, arguments, maximum, seconds, on_chunk)
end

function show_progress(label, percent):
    return implementation.show_progress(label, percent)
end

function relay_installer_progress(chunk):
    return implementation.relay_installer_progress(chunk)
end

function lock(store):
    return implementation.lock(store)
end

function canonical(path):
    return implementation.canonical(path)
end

function installation(executable, home, system):
    return implementation.installation(executable, home, system)
end

function target(store, name):
    return implementation.target(store, name)
end

function health(generation, expected, scratch):
    return implementation.health(generation, expected, scratch)
end

function install_stage(installer, generation, version, scratch):
    return implementation.install_stage(installer, generation, version, scratch)
end

function prepare(prefix, executable, version, scratch):
    return implementation.prepare(prefix, executable, version, scratch)
end

function recover(store, scratch):
    return implementation.recover(store, scratch)
end

function activate(store, generation, version, scratch):
    return implementation.activate(store, generation, version, scratch)
end

function rollback(store, scratch):
    return implementation.rollback(store, scratch)
end

function cleanup_scratch(path):
    return implementation.cleanup_scratch(path)
end
