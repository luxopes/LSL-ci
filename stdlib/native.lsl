# Restricted in-process CPU ET_DYN ABI. Libraries must be self-contained PIC,
# have no relocations/external dependencies, and map st_value to file offsets.

function u16(library, offset):
    return native_u64(library, offset) % 65536
end

function u32(library, offset):
    return native_u64(library, offset) % 4294967296
end

function open(path):
    library = native_open(path)
    if library == None:
        Error(NativeError: "cannot map valid Linux x86_64 ET_DYN image")
    end
    return library
end

function symbol(library, name):
    size = native_size(library)
    section_offset = native_u64(library, 40)
    section_entry_size = u16(library, 58)
    section_count = u16(library, 60)
    if section_entry_size < 64 or section_offset < 64 or section_offset + section_entry_size * section_count > size:
        Error(NativeError: "invalid ELF section table")
    end
    section_index = 0
    while section_index < section_count:
        section = section_offset + section_index * section_entry_size
        if u32(library, section + 4) == 11:
            symbols_offset = native_u64(library, section + 24)
            symbols_size = native_u64(library, section + 32)
            strings_index = u32(library, section + 40)
            symbol_size = native_u64(library, section + 56)
            if symbol_size < 24 or strings_index >= section_count:
                Error(NativeError: "invalid ELF dynamic symbol table")
            end
            strings_section = section_offset + strings_index * section_entry_size
            strings_offset = native_u64(library, strings_section + 24)
            if symbols_offset + symbols_size > size or strings_offset >= size:
                Error(NativeError: "ELF symbol data is out of bounds")
            end
            symbol_offset = symbols_offset
            while symbol_offset + 24 <= symbols_offset + symbols_size:
                name_offset = u32(library, symbol_offset)
                value = native_u64(library, symbol_offset + 8)
                if value < size and strings_offset + name_offset < size:
                    if native_name_equal(library, strings_offset + name_offset, name):
                        return native_function(library, value)
                    end
                end
                symbol_offset += symbol_size
            end
        end
        section_index += 1
    end
    Error(NativeError: "native symbol not found: " + name)
end

function call(function, arguments):
    if len(arguments) > 6:
        Error(NativeError: "native ABI supports at most six Int arguments")
    end
    padded = []
    for value in arguments:
        code = __lsl_type_code(value)
        if code != 0 and code != 9:
            Error(NativeError: "native ABI accepts only Int arguments")
        end
        padded.append(Int(value))
    end
    while len(padded) < 6:
        padded.append(0)
    end
    return native_call(function, padded)
end

function close(library):
    return native_close(library)
end
