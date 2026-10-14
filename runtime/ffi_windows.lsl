# lsl: runtime
# Nativní knihovny na Windows: izolované volání (vlastní proces s kopií kódu,
# seccomp) zatím chybí, proto se obraz nikdy nenačte. native.open vrátí
# None a volání skončí chybou NativeError, stejně jako na Linuxu bez izolace.
EINVAL = 22

function native_image_load(path, size_out):
    return 0
end

function native_image_seal(image, size):
    return -EINVAL
end

function native_image_unmap(image, size):
    return -EINVAL
end

function native_sandbox_start(code, items, channel_out):
    return -1
end

function native_sandbox_finish(pid, reader, result_out):
    return 0
end
