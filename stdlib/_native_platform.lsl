# Veřejné API; operace hostitele poskytuje modul vybraný cílem.

load _native_linux_x86_64 as implementation


function u8(library, offset):
    return implementation.u8(library, offset)
end

function u16(library, offset):
    return implementation.u16(library, offset)
end

function u32(library, offset):
    return implementation.u32(library, offset)
end

function open(path):
    return implementation.open(path)
end

function valid_symbol_name(name):
    return implementation.valid_symbol_name(name)
end

function symbol(library, name):
    return implementation.symbol(library, name)
end

function call(target, arguments):
    return implementation.call(target, arguments)
end

function close(library):
    return implementation.close(library)
end
