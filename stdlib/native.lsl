# Restricted fork-isolated CPU ET_DYN ABI. Libraries must be self-contained
# PIC, have no relocations/external dependencies, and map st_value to file
# offsets. Calls execute in a short-lived strict-seccomp child process.

# Veřejné API; operace hostitele poskytuje modul vybraný cílem.

load _native_platform as implementation


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
