# WebAssembly (WASI): nativní knihovny runtime ve wasm nenačte (NativeError).

load _native_linux_x86_64 as shared

function u8(library, offset):
    return shared.u8(library, offset)
end

function u16(library, offset):
    return shared.u16(library, offset)
end

function u32(library, offset):
    return shared.u32(library, offset)
end

function open(path):
    return shared.open(path)
end

function valid_symbol_name(name):
    return shared.valid_symbol_name(name)
end

function symbol(library, name):
    return shared.symbol(library, name)
end

function call(target, arguments):
    return shared.call(target, arguments)
end

function close(library):
    return shared.close(library)
end
