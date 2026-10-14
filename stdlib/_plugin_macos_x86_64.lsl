# macOS: izolace pluginů přes timeout (coreutils, na macOS jen po instalaci).
# Logika je stejná jako na Linuxu (POSIX cesty a nástroje, builtiny runtime),
# konstanty dodá modul platformy cíle; platí pro x86_64 i arm64.

load _plugin_linux_x86_64 as shared

function timeout_tool():
    return shared.timeout_tool()
end

function checked_timeout(seconds):
    return shared.checked_timeout(seconds)
end

function capture_with_timeout(executable, arguments, input_text, seconds):
    return shared.capture_with_timeout(executable, arguments, input_text, seconds)
end

function capture_argv(executable, encoded):
    return shared.capture_argv(executable, encoded)
end
