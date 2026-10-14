# lsl: runtime
# Nativní knihovny bez operačního systému: nejsou procesy pro izolaci
# ani ochrana paměti. native.open vrátí None, volání NativeError.
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

function native_sandbox_start(image, size, code, items, channel_out):
    return -1
end

function native_sandbox_finish(pid, reader, result_out):
    return 0
end

function native_child_main():
    return 0
end
