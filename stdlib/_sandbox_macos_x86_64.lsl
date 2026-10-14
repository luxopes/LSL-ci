# macOS: izolace procesu potřebuje bubblewrap a systemd (Linux); available()
# vrátí False.
# Logika je stejná jako na Linuxu (POSIX cesty a nástroje, builtiny runtime),
# konstanty dodá modul platformy cíle; platí pro x86_64 i arm64.

load _sandbox_linux_x86_64 as shared

function system_tool(primary, fallback, label):
    return shared.system_tool(primary, fallback, label)
end

function available():
    return shared.available()
end

function is_active():
    return shared.is_active()
end

function profile():
    return shared.profile()
end

function input_path(index):
    return shared.input_path(index)
end

function output_path(index):
    return shared.output_path(index)
end

function canonical_path(path, label):
    return shared.canonical_path(path, label)
end

function checked_capabilities(policy, name):
    return shared.checked_capabilities(policy, name)
end

function checked_arguments(arguments):
    return shared.checked_arguments(arguments)
end

function checked_policy(value):
    return shared.checked_policy(value)
end

function command(executable, arguments, policy):
    return shared.command(executable, arguments, policy)
end

function run(executable, arguments, policy):
    return shared.run(executable, arguments, policy)
end
