# General ELF64 image builder over List[Int]. Unlike the bootstrap ASCII writer,
# this module supports every byte value and is materialized by the direct writer.

load bytes

function header(code_size, data_size, entry_offset):
    header_size = 64
    program_header_size = 56
    image_size = header_size + program_header_size + code_size + data_size
    base = 4194304
    result = [127, 69, 76, 70, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    result.extend(bytes.little(2, 2))
    result.extend(bytes.little(62, 2))
    result.extend(bytes.little(1, 4))
    result.extend(bytes.little(base + header_size + program_header_size + entry_offset, 8))
    result.extend(bytes.little(header_size, 8))
    result.extend(bytes.little(0, 8))
    result.extend(bytes.little(0, 4))
    result.extend(bytes.little(header_size, 2))
    result.extend(bytes.little(program_header_size, 2))
    result.extend(bytes.little(1, 2))
    result.extend(bytes.little(0, 2))
    result.extend(bytes.little(0, 2))
    result.extend(bytes.little(0, 2))

    # One read/execute PT_LOAD segment containing headers, code and immutable data.
    result.extend(bytes.little(1, 4))
    result.extend(bytes.little(5, 4))
    result.extend(bytes.little(0, 8))
    result.extend(bytes.little(base, 8))
    result.extend(bytes.little(base, 8))
    result.extend(bytes.little(image_size, 8))
    result.extend(bytes.little(image_size, 8))
    result.extend(bytes.little(4096, 8))
    return result
end

function image_entry(code, data, entry_offset):
    result = header(len(code), len(data), entry_offset)
    result.extend(code)
    result.extend(data)
    return result
end

function image(code, data):
    return image_entry(code, data, 0)
end
