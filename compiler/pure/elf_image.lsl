# General ELF64 image builder over List[Int]. Unlike the bootstrap ASCII writer,
# this module supports every byte value and is materialized by the direct writer.

load bytes

function header(code_size, data_size, entry_offset):
    header_size = 64
    program_header_size = 56
    program_header_count = 2
    payload_offset = header_size + program_header_size * program_header_count
    image_size = payload_offset + code_size + data_size
    result = [127, 69, 76, 70, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    # ET_DYN with fully RIP-relative code is a static PIE. Linux chooses a
    # randomized load bias even though the image has no interpreter, dynamic
    # section or relocations.
    result.extend(bytes.little(3, 2))
    result.extend(bytes.little(62, 2))
    result.extend(bytes.little(1, 4))
    result.extend(bytes.little(payload_offset + entry_offset, 8))
    result.extend(bytes.little(header_size, 8))
    result.extend(bytes.little(0, 8))
    result.extend(bytes.little(0, 4))
    result.extend(bytes.little(header_size, 2))
    result.extend(bytes.little(program_header_size, 2))
    result.extend(bytes.little(program_header_count, 2))
    result.extend(bytes.little(0, 2))
    result.extend(bytes.little(0, 2))
    result.extend(bytes.little(0, 2))

    # One read/execute PT_LOAD segment containing headers, code and immutable
    # data. A zero virtual address makes every e_entry and RIP-relative
    # displacement relative to the kernel-selected PIE load bias.
    result.extend(bytes.little(1, 4))
    result.extend(bytes.little(5, 4))
    result.extend(bytes.little(0, 8))
    result.extend(bytes.little(0, 8))
    result.extend(bytes.little(0, 8))
    result.extend(bytes.little(image_size, 8))
    result.extend(bytes.little(image_size, 8))
    result.extend(bytes.little(4096, 8))

    # Explicit non-executable stack. Relying on the kernel default when
    # PT_GNU_STACK is absent is architecture- and tooling-dependent.
    result.extend(bytes.little(1685382481, 4))
    result.extend(bytes.little(6, 4))
    result.extend(bytes.little(0, 8))
    result.extend(bytes.little(0, 8))
    result.extend(bytes.little(0, 8))
    result.extend(bytes.little(0, 8))
    result.extend(bytes.little(0, 8))
    result.extend(bytes.little(16, 8))
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
