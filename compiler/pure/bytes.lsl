# Byte-buffer helpers represented entirely as LSL List[Int].

function append(buffer, value):
    if value < 0 or value > 255:
        Error(ByteRangeError: "byte is outside 0..255")
    end
    buffer.append(value)
end

function extend(buffer, values):
    for value in values:
        call append(buffer, value)
    end
end

function little(value, width):
    result = []
    # Compiler-internal direct calls carry scalar arguments as boxed Ints.
    # Normalize once into typed raw locals; keeping `remaining` as Any made the
    # byte encoder depend on generic heap classification under peak self-host
    # memory pressure and very rarely emitted another boxed payload.
    remaining = __lsl_typed_int(value)
    byte_width = __lsl_typed_int(width)
    if remaining < 0:
        limit = 1
        for index in rang(byte_width):
            limit *= 256
        end
        remaining += limit
    end
    for index in rang(byte_width):
        result.append(remaining % 256)
        remaining = remaining // 256
    end
    return result
end

function patch_little(buffer, offset, value, width):
    encoded = little(value, width)
    index = 0
    while index < width:
        buffer[offset + index] = encoded[index]
        index += 1
    end
end

function utf8(text):
    result = []
    for character in text:
        code = ord(character)
        if code <= 127:
            result.append(code)
        elif code <= 2047:
            result.append(192 + code // 64)
            result.append(128 + code % 64)
        elif code <= 65535:
            result.append(224 + code // 4096)
            result.append(128 + (code // 64) % 64)
            result.append(128 + code % 64)
        else:
            result.append(240 + code // 262144)
            result.append(128 + (code // 4096) % 64)
            result.append(128 + (code // 64) % 64)
            result.append(128 + code % 64)
        end
    end
    return result
end

function decimal_spec(buffer):
    parts = []
    for value in buffer:
        parts.append(String(value))
    end
    return ",".join(parts)
end
