# Kompatibilní fasáda původního assembleru pro x86_64.

load assembler_x86_64 as implementation

function builder():
    return implementation.builder()
end

function position(value):
    return implementation.position(value)
end

function emit(value, data):
    return implementation.emit(value, data)
end

function label(value, name):
    return implementation.label(value, name)
end

function relative(value, opcode, name):
    return implementation.relative(value, opcode, name)
end

function finish(value):
    return implementation.finish(value)
end

function import_symbol(value, library, name):
    return implementation.import_symbol(value, library, name)
end

function external_relative(value, opcode, symbol):
    call implementation.external_relative(value, opcode, symbol)
end

function export_symbol(value, name):
    call implementation.export_symbol(value, name)
end
