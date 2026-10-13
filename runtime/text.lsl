# lsl: runtime
# Nativní pomocníci nad bajty řetězců a polí (__lsl_text_*, __lsl_byte_copy,
# rastrové smyčky gfx/display). Rozsahy se ořezávají na skutečné délky a typy
# se ověřují, takže chybné volání nic nepoškodí. Kromě nových řetězců
# a seznamů nic nealokují.
load core

TAG_LIST = 2
TAG_INT_ARRAY = 13
TAG_BYTE_ARRAY = 15
# Objekt pole: +8 délka, +24 ukazatel na data.
ARRAY_LENGTH = 8
ARRAY_DATA = 24

# Živý objekt na haldě s daným tagem.
# (Ne `return a and b`: výsledek `and` by se rozbaloval jako Any.)
function rt_runtime_heap_type_valid(value, tag):
    if core.rt_runtime_is_heap_object(value) and __lsl_qbe_load64(value) == tag:
        return 1
    end
    return 0
end

# Kopie dopředu po bajtech. Po 8 bajtech jen při stejném zarovnání obou
# konců a když cíl neleží 1-7 bajtů za zdrojem (tam se bajtová kopie
# dopředu „rozmazává“ jinak než slovní).
function copy_bytes(destination, source, count):
    if (destination ~ source) & 7 == 0 and not __lsl_qbe_ult(destination - source - 1, 7):
        while count > 0 and destination & 7 != 0:
            __lsl_qbe_store8(destination, __lsl_qbe_load8(source))
            destination += 1
            source += 1
            count -= 1
        end
        while count >= 8:
            __lsl_qbe_store64(destination, __lsl_qbe_load64(source))
            destination += 8
            source += 8
            count -= 8
        end
    end
    while count > 0:
        __lsl_qbe_store8(destination, __lsl_qbe_load8(source))
        destination += 1
        source += 1
        count -= 1
    end
    return 0
end

# Nový String z count bajtů od adresy source (zakončený nulou).
function string_from(source, count):
    text = __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc"), count + 17)
    __lsl_qbe_store64(text, core.TAG_STRING)
    __lsl_qbe_store64(text + 8, count)
    call copy_bytes(text + 16, source, count)
    __lsl_qbe_store8(text + 16 + count, 0)
    return text
end

# Počet prvků z rozsahu [start, start + count) v poli délky length; 0 když
# je rozsah prázdný nebo mimo pole.
function clamp_count(length, start, count):
    if count <= 0 or start < 0:
        return 0
    end
    available = length - start
    if available <= 0:
        return 0
    end
    if count > available:
        return available
    end
    return count
end

function rt_runtime_from_cstring(pointer):
    length = 0
    while __lsl_qbe_load8(pointer + length) != 0:
        length += 1
    end
    return string_from(pointer, length)
end

# __lsl_text_byte: bajt na indexu, -1 mimo rozsah nebo pro jiný typ než String.
function rt_runtime_text_byte(text, index):
    if not rt_runtime_heap_type_valid(text, core.TAG_STRING):
        return -1
    end
    if index < 0 or index >= __lsl_qbe_load64(text + 8):
        return -1
    end
    return __lsl_qbe_load8(text + 16 + index)
end

# __lsl_text_piece: nový String z bajtů [start, start + count), ořezaný;
# prázdný mimo rozsah nebo pro jiný typ než String.
function rt_runtime_text_piece(text, start, count):
    if not rt_runtime_heap_type_valid(text, core.TAG_STRING):
        return string_from(0, 0)
    end
    count = clamp_count(__lsl_qbe_load64(text + 8), start, count)
    if count == 0:
        return string_from(0, 0)
    end
    return string_from(text + 16 + start, count)
end

# __lsl_text_scan_digits: první index >= start, kde není číslice ASCII
# (délka, když jsou číslice až do konce); -1 pro jiný typ nebo start mimo.
function rt_runtime_text_scan_digits(text, start):
    if not rt_runtime_heap_type_valid(text, core.TAG_STRING):
        return -1
    end
    length = __lsl_qbe_load64(text + 8)
    if start < 0 or start > length:
        return -1
    end
    bytes = text + 16
    while start < length:
        byte = __lsl_qbe_load8(bytes + start)
        if byte < 48 or byte > 57:
            return start
        end
        start += 1
    end
    return start
end

# __lsl_text_digits: hodnota číslic [start, stop) (value * 10 + číslice
# s přetečením jako parser); 0 pro jiný typ nebo rozsah mimo.
function rt_runtime_text_digits(text, start, stop):
    if not rt_runtime_heap_type_valid(text, core.TAG_STRING):
        return 0
    end
    if start < 0 or stop > __lsl_qbe_load64(text + 8):
        return 0
    end
    bytes = text + 16
    value = 0
    while start < stop:
        value = value * 10 + (__lsl_qbe_load8(bytes + start) - 48)
        start += 1
    end
    return value
end

# __lsl_text_split_byte: List kusů mezi oddělovači (celý text bez
# oddělovače, prázdný List pro jiný typ než String).
function rt_runtime_text_split_byte(text, separator):
    pieces = __lsl_qbe_call2(__lsl_symbol("rt_runtime_list_new"), 0, 0)
    if not rt_runtime_heap_type_valid(text, core.TAG_STRING):
        return pieces
    end
    start = 0
    position = 0
    while position < __lsl_qbe_load64(text + 8):
        if __lsl_qbe_load8(text + 16 + position) == separator:
            call __lsl_qbe_call2(__lsl_symbol("rt_runtime_list_append"), pieces, rt_runtime_text_piece(text, start, position - start))
            start = position + 1
        end
        position += 1
    end
    call __lsl_qbe_call2(__lsl_symbol("rt_runtime_list_append"), pieces, rt_runtime_text_piece(text, start, __lsl_qbe_load64(text + 8) - start))
    return pieces
end

# __lsl_text_from_bytes: String z bajtů ByteArray [start, start + count),
# ořezaný; prázdný mimo rozsah nebo pro jiný typ.
function rt_runtime_text_from_bytes(array, start, count):
    if not rt_runtime_heap_type_valid(array, TAG_BYTE_ARRAY):
        return string_from(0, 0)
    end
    count = clamp_count(__lsl_qbe_load64(array + ARRAY_LENGTH), start, count)
    if count == 0:
        return string_from(0, 0)
    end
    return string_from(__lsl_qbe_load64(array + ARRAY_DATA) + start, count)
end

# __lsl_byte_copy: dopředná kopie bajtů mezi ByteArray s ořezáním obou konců.
function rt_runtime_byte_copy(target, source, target_offset, source_offset, count):
    if not rt_runtime_heap_type_valid(target, TAG_BYTE_ARRAY) or not rt_runtime_heap_type_valid(source, TAG_BYTE_ARRAY):
        return 0
    end
    if source_offset < 0:
        return 0
    end
    count = clamp_count(__lsl_qbe_load64(target + ARRAY_LENGTH), target_offset, count)
    count = clamp_count(__lsl_qbe_load64(source + ARRAY_LENGTH), source_offset, count)
    if count == 0:
        return 0
    end
    call copy_bytes(__lsl_qbe_load64(target + ARRAY_DATA) + target_offset, __lsl_qbe_load64(source + ARRAY_DATA) + source_offset, count)
    return 0
end

# __lsl_data_address: adresa dat ByteArray (ioctl s ukazateli), jinak 0.
function rt_runtime_data_address(array):
    if not rt_runtime_heap_type_valid(array, TAG_BYTE_ARRAY):
        return 0
    end
    return __lsl_qbe_load64(array + ARRAY_DATA)
end

# Pixely 0xRRGGBB z IntArray do slov BGRX (jeden 32bitový zápis na pixel).
function pack_pixels(target, pixels, count):
    index = 0
    while index < count:
        __lsl_qbe_store32(target + __lsl_qbe_shl(index, 2), __lsl_qbe_load64(pixels + __lsl_qbe_shl(index, 3)))
        index += 1
    end
    return 0
end

# __lsl_raster_pack: IntArray src, ByteArray dst, src_off a count v pixelech,
# dst_off v bajtech.
function rt_runtime_raster_pack(source, target, source_offset, target_offset, count):
    if not rt_runtime_heap_type_valid(source, TAG_INT_ARRAY) or not rt_runtime_heap_type_valid(target, TAG_BYTE_ARRAY):
        return 0
    end
    if count <= 0 or source_offset < 0 or target_offset < 0:
        return 0
    end
    count = clamp_count(__lsl_qbe_load64(source + ARRAY_LENGTH), source_offset, count)
    if count == 0:
        return 0
    end
    room = __lsl_qbe_ashr(__lsl_qbe_load64(target + ARRAY_LENGTH) - target_offset, 2)
    if room <= 0:
        return 0
    end
    if count > room:
        count = room
    end
    return pack_pixels(__lsl_qbe_load64(target + ARRAY_DATA) + target_offset, __lsl_qbe_load64(source + ARRAY_DATA) + __lsl_qbe_shl(source_offset, 3), count)
end

# __lsl_raster_copy: dopředná kopie prvků IntArray (překryv jen s dst <= src).
function rt_runtime_raster_copy(target, source, target_offset, source_offset, count):
    if not rt_runtime_heap_type_valid(target, TAG_INT_ARRAY) or not rt_runtime_heap_type_valid(source, TAG_INT_ARRAY):
        return 0
    end
    if source_offset < 0:
        return 0
    end
    count = clamp_count(__lsl_qbe_load64(target + ARRAY_LENGTH), target_offset, count)
    count = clamp_count(__lsl_qbe_load64(source + ARRAY_LENGTH), source_offset, count)
    destination = __lsl_qbe_load64(target + ARRAY_DATA) + __lsl_qbe_shl(target_offset, 3)
    origin = __lsl_qbe_load64(source + ARRAY_DATA) + __lsl_qbe_shl(source_offset, 3)
    index = 0
    while index < count:
        __lsl_qbe_store64(destination + __lsl_qbe_shl(index, 3), __lsl_qbe_load64(origin + __lsl_qbe_shl(index, 3)))
        index += 1
    end
    return 0
end

# __lsl_raster_fill: IntArray, offset, count, hodnota.
function rt_runtime_raster_fill(array, offset, count, value):
    if not rt_runtime_heap_type_valid(array, TAG_INT_ARRAY):
        return 0
    end
    count = clamp_count(__lsl_qbe_load64(array + ARRAY_LENGTH), offset, count)
    destination = __lsl_qbe_load64(array + ARRAY_DATA) + __lsl_qbe_shl(offset, 3)
    index = 0
    while index < count:
        __lsl_qbe_store64(destination + __lsl_qbe_shl(index, 3), value)
        index += 1
    end
    return 0
end

# __lsl_mem_pack: jako raster_pack, cíl je mapovaná paměť (adresa); meze
# mapování hlídá volající.
function rt_runtime_mem_pack(target, source, source_offset, target_offset, count):
    if not rt_runtime_heap_type_valid(source, TAG_INT_ARRAY):
        return 0
    end
    if target <= 0 or target_offset < 0:
        return 0
    end
    count = clamp_count(__lsl_qbe_load64(source + ARRAY_LENGTH), source_offset, count)
    if count == 0:
        return 0
    end
    return pack_pixels(target + target_offset, __lsl_qbe_load64(source + ARRAY_DATA) + __lsl_qbe_shl(source_offset, 3), count)
end

# __lsl_mem_unpack: slova BGRX z mapované paměti do pixelů IntArray.
function rt_runtime_mem_unpack(target, target_offset, source, count):
    if not rt_runtime_heap_type_valid(target, TAG_INT_ARRAY):
        return 0
    end
    if source == 0:
        return 0
    end
    count = clamp_count(__lsl_qbe_load64(target + ARRAY_LENGTH), target_offset, count)
    destination = __lsl_qbe_load64(target + ARRAY_DATA) + __lsl_qbe_shl(target_offset, 3)
    index = 0
    while index < count:
        __lsl_qbe_store64(destination + __lsl_qbe_shl(index, 3), __lsl_qbe_load32(source + __lsl_qbe_shl(index, 2)))
        index += 1
    end
    return 0
end
