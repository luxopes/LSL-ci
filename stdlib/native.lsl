# Restricted in-process CPU ET_DYN ABI. Libraries must be self-contained PIC,
# have no relocations/external dependencies, and map st_value to file offsets.

function u8(library, offset):
    return native_u64(library, offset) % 256
end

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
    if u8(library, 4) != 2 or u8(library, 5) != 1 or u8(library, 6) != 1 or u32(library, 20) != 1 or u16(library, 52) < 64:
        call native_close(library)
        Error(NativeError: "invalid ELF class, byte order or version")
    end
    return library
end

function symbol(library, name):
    if __lsl_type_code(library) != 11:
        Error(NativeError: "native symbol lookup requires an open library")
    end
    size = native_size(library)
    section_offset = native_u64(library, 40)
    section_entry_size = u16(library, 58)
    section_count = u16(library, 60)
    if section_entry_size < 64 or section_offset < 64 or section_offset > size:
        Error(NativeError: "invalid ELF section table")
    end
    if section_count > (size - section_offset) // section_entry_size:
        Error(NativeError: "invalid ELF section table")
    end

    # ABI v1 does not apply relocations, resolve external symbols or execute a
    # dynamic loader. Reject such images instead of calling partially fixed-up
    # code in-process.
    section_index = 0
    while section_index < section_count:
        section = section_offset + section_index * section_entry_size
        section_type = u32(library, section + 4)
        file_offset = native_u64(library, section + 24)
        file_size = native_u64(library, section + 32)
        if section_type != 8 and (file_offset > size or file_size > size - file_offset):
            Error(NativeError: "ELF section is out of bounds")
        end
        if section_type == 4 or section_type == 9 or section_type == 6:
            Error(NativeError: "native ABI does not accept relocations or dynamic sections")
        end
        section_index += 1
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
            if u32(library, strings_section + 4) != 3:
                Error(NativeError: "ELF symbol strings do not reference a string table")
            end
            strings_offset = native_u64(library, strings_section + 24)
            strings_size = native_u64(library, strings_section + 32)
            if symbols_offset > size or symbols_size > size - symbols_offset or strings_offset > size or strings_size > size - strings_offset:
                Error(NativeError: "ELF symbol data is out of bounds")
            end
            if symbols_size % symbol_size != 0:
                Error(NativeError: "ELF symbol table has a truncated entry")
            end
            symbol_offset = symbols_offset
            while symbol_offset + 24 <= symbols_offset + symbols_size:
                name_offset = u32(library, symbol_offset)
                value = native_u64(library, symbol_offset + 8)
                value_size = native_u64(library, symbol_offset + 16)
                target_index = u16(library, symbol_offset + 6)
                if name_offset < strings_size and len(name) < strings_size - name_offset:
                    if native_name_equal(library, strings_offset + name_offset, name):
                        if target_index == 0 or target_index >= section_count:
                            Error(NativeError: "native symbol is undefined")
                        end
                        target = section_offset + target_index * section_entry_size
                        target_type = u32(library, target + 4)
                        target_flags = native_u64(library, target + 8)
                        target_offset = native_u64(library, target + 24)
                        target_size = native_u64(library, target + 32)
                        if target_type != 1 or (target_flags & 4) == 0:
                            Error(NativeError: "native symbol is not in executable code")
                        end
                        if value < target_offset or value >= target_offset + target_size or value_size > target_offset + target_size - value:
                            Error(NativeError: "native symbol code is out of bounds")
                        end
                        resolved = native_function(library, value)
                        if resolved == None:
                            Error(NativeError: "native symbol address is out of bounds")
                        end
                        return resolved
                    end
                end
                symbol_offset += symbol_size
            end
        end
        section_index += 1
    end
    Error(NativeError: "native symbol not found: " + name)
end

function call(target, arguments):
    if __lsl_type_code(target) != 12:
        Error(NativeError: "native call requires a resolved native function")
    end
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
    return native_call(target, padded)
end

function close(library):
    if __lsl_type_code(library) != 11:
        Error(NativeError: "native close requires an open library")
    end
    return native_close(library)
end
