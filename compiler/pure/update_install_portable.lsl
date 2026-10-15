# Spravované instalace s generacemi na Windows a macOS zatím nejsou
# (lsl-install kopíruje do prefixu). Rozhraní update_install_linux_x86_64.lsl.
RELAY = {"carry": ""}
TOOLS = ["lsl", "lslc", "lsl-configure", "lsl-test", "lsl-install"]

function fail(message):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function cstring(value):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function little(buffer, offset, width):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function dirname(path):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function metadata(path):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function owned_directory(path):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function directory(path):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function public_directory(path):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function private_work(parent):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function sync_path(path):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function rename(source, destination):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function link(target, destination):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function read_link(path):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function switch_link(target, destination, scratch):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function tool(name):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function bounded(executable, arguments, maximum, seconds):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function bounded_stream(executable, arguments, maximum, seconds, on_chunk):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function show_progress(label, percent):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function relay_installer_progress(chunk):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function lock(store):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function canonical(path):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function installation(executable, home, system):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function target(store, name):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function health(generation, expected, scratch):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function install_stage(installer, generation, version, scratch):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function prepare(prefix, executable, version, scratch):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function recover(store, scratch):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function activate(store, generation, version, scratch):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function rollback(store, scratch):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end

function cleanup_scratch(path):
    Error(UpdateError: "managed installations are not available on Windows and macOS yet; use lsl-install PREFIX")
end
