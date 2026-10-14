# lsl: runtime
# Operace nad řetězci: spojení, internované literály, délka a indexy v kódových
# bodech UTF-8, výřez, hledání podřetězce. String: +0 tag 1,
# +8 délka v bajtech, od +16 bajty zakončené nulou. Indexy se počítají podle
# šířky úvodního bajtu (< 128: 1, < 224: 2, < 240: 3, jinak 4), délka jako počet
# bajtů, které nejsou pokračovací (10xxxxxx), stejně jako dřívější x86 rutiny.
load core
load heap
load _runtime_os as os

INTERN_TABLE = 48
INTERN_MASK = 56
# Horní bity všech bajtů slova.
HIGH_BITS = -9187201950435737472
LOW_BYTES = 72340172838076673

# Kopie count bajtů dopředu, oblasti se nepřekrývají. Cíl se zarovná na 8 B;
# při jiném zarovnání zdroje se slovo skládá ze dvou zarovnaných čtení
# (little-endian), takže se nečte nic mimo bloky haldy obou oblastí.
function copy_memory(destination, source, count):
    if count >= 16:
        while destination & 7 != 0:
            __lsl_qbe_store8(destination, __lsl_qbe_load8(source))
            destination += 1
            source += 1
            count -= 1
        end
        shift = source & 7
        if shift == 0:
            while count >= 8:
                __lsl_qbe_store64(destination, __lsl_qbe_load64(source))
                destination += 8
                source += 8
                count -= 8
            end
        else:
            aligned = source - shift
            low = __lsl_qbe_shl(shift, 3)
            high = 64 - low
            word = __lsl_qbe_load64(aligned)
            while count >= 8:
                aligned += 8
                following = __lsl_qbe_load64(aligned)
                __lsl_qbe_store64(destination, __lsl_qbe_lshr(word, low) | __lsl_qbe_shl(following, high))
                word = following
                destination += 8
                count -= 8
            end
            source = aligned + shift
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

# Nový String délky count (bajty nevyplněné, nula na konci).
function string_alloc(count):
    text = heap.rt_runtime_alloc(count + 17)
    __lsl_qbe_store64(text, core.TAG_STRING)
    __lsl_qbe_store64(text + 8, count)
    __lsl_qbe_store8(text + 16 + count, 0)
    return text
end

function rt_runtime_string_concat(left, right):
    left_length = __lsl_qbe_load64(left + 8)
    right_length = __lsl_qbe_load64(right + 8)
    text = string_alloc(left_length + right_length)
    call copy_memory(text + 16, left + 16, left_length)
    call copy_memory(text + 16 + left_length, right + 16, right_length)
    return text
end

# Tabulka internovaných literálů (stav +48, maska +56): dvojice (statický
# záznam, String na haldě) po 16 B; slot = (adresa >> 3) & maska. Nová
# dvojnásobná tabulka je nové mapování (paměť je nulová), stará se nevrací.
function rt_runtime_grow_intern_table():
    base = core.state()
    old = __lsl_qbe_load64(base + INTERN_TABLE)
    mask = __lsl_qbe_load64(base + INTERN_MASK)
    if mask > 16777215:
        call heap.fatal_allocation()
    end
    capacity = (mask + 1) * 2
    new_mask = capacity - 1
    size = __lsl_qbe_shl(capacity, 4)
    table = os.map_anonymous(size, 0)
    if table < 0:
        call heap.fatal_allocation()
    end
    index = 0
    while index <= mask:
        entry = old + __lsl_qbe_shl(index, 4)
        key = __lsl_qbe_load64(entry)
        if key != 0:
            slot = __lsl_qbe_ashr(key, 3) & new_mask
            while __lsl_qbe_load64(table + __lsl_qbe_shl(slot, 4)) != 0:
                slot = (slot + 1) & new_mask
            end
            __lsl_qbe_store64(table + __lsl_qbe_shl(slot, 4), key)
            __lsl_qbe_store64(table + __lsl_qbe_shl(slot, 4) + 8, __lsl_qbe_load64(entry + 8))
        end
        index += 1
    end
    __lsl_qbe_store64(base + INTERN_TABLE, table)
    __lsl_qbe_store64(base + INTERN_MASK, new_mask)
    return 0
end

# Kopie statického záznamu String na haldu, jednou pro každou adresu záznamu.
function rt_runtime_string_clone(source):
    base = core.state()
    table = __lsl_qbe_load64(base + INTERN_TABLE)
    mask = __lsl_qbe_load64(base + INTERN_MASK)
    start = __lsl_qbe_ashr(source, 3) & mask
    slot = start
    while True:
        key = __lsl_qbe_load64(table + __lsl_qbe_shl(slot, 4))
        if key == 0:
            break
        elif key == source:
            return __lsl_qbe_load64(table + __lsl_qbe_shl(slot, 4) + 8)
        end
        slot = (slot + 1) & mask
        if slot == start:
            call rt_runtime_grow_intern_table()
            table = __lsl_qbe_load64(base + INTERN_TABLE)
            mask = __lsl_qbe_load64(base + INTERN_MASK)
            start = __lsl_qbe_ashr(source, 3) & mask
            slot = start
        end
    end
    length = __lsl_qbe_load64(source + 8)
    text = string_alloc(length)
    call copy_memory(text + 16, source + 16, length)
    entry = __lsl_qbe_load64(base + INTERN_TABLE) + __lsl_qbe_shl(slot, 4)
    __lsl_qbe_store64(entry, source)
    __lsl_qbe_store64(entry + 8, text)
    return text
end

# Počet kódových bodů: bajty bez pokračovacích, po slovech.
function utf8_length(text):
    remaining = __lsl_qbe_load64(text + 8)
    count = remaining
    position = text + 16
    while remaining >= 8:
        word = __lsl_qbe_load64(position)
        continuation = word & (~__lsl_qbe_shl(word, 1)) & HIGH_BITS
        if continuation != 0:
            count -= __lsl_qbe_lshr(__lsl_qbe_lshr(continuation, 7) * LOW_BYTES, 56)
        end
        position += 8
        remaining -= 8
    end
    while remaining > 0:
        if __lsl_qbe_load8(position) & 192 == 128:
            count -= 1
        end
        position += 1
        remaining -= 1
    end
    return count
end

# Délka: kódové body u String, jinak pole +8.
function rt_runtime_length(value):
    if __lsl_qbe_load64(value) == core.TAG_STRING:
        return utf8_length(value)
    end
    return __lsl_qbe_load64(value + 8)
end

# Šířka znaku UTF-8 podle úvodního bajtu.
function utf8_width(byte):
    if byte < 128:
        return 1
    elif byte < 224:
        return 2
    elif byte < 240:
        return 3
    end
    return 4
end

# Bajtový posun za count znaky od adresy bytes (bez kontroly mezí). Zarovnaná
# slova jen z ASCII se přeskočí najednou.
function utf8_skip(bytes, count):
    offset = 0
    while count > 0:
        if count >= 8 and (bytes + offset) & 7 == 0 and __lsl_qbe_load64(bytes + offset) & HIGH_BITS == 0:
            offset += 8
            count -= 8
        else:
            offset += utf8_width(__lsl_qbe_load8(bytes + offset))
            count -= 1
        end
    end
    return offset
end

function rt_runtime_string_byte_offset(text, index):
    return utf8_skip(text + 16, index)
end

# Znak na nezáporném indexu jako nový String.
function string_char_at(text, index):
    source = text + 16 + utf8_skip(text + 16, index)
    width = utf8_width(__lsl_qbe_load8(source))
    piece = string_alloc(width)
    offset = 0
    while offset < width:
        __lsl_qbe_store8(piece + 16 + offset, __lsl_qbe_load8(source + offset))
        offset += 1
    end
    return piece
end

function rt_runtime_get_string(text, index):
    if index < 0:
        index += utf8_length(text)
    end
    return string_char_at(text, index)
end

# min(max(value, 0), length)
function rt_runtime_slice_clamp(value, length):
    if value < 0:
        value = 0
    end
    if value > length:
        return length
    end
    return value
end

# Výřez [start, stop) ve znacích; záporné meze od konce, ořez na [0, délka].
function string_slice(text, start, stop):
    length = utf8_length(text)
    if start < 0:
        start += length
    end
    if stop < 0:
        stop += length
    end
    start = rt_runtime_slice_clamp(start, length)
    stop = rt_runtime_slice_clamp(stop, length)
    first = text + 16 + utf8_skip(text + 16, start)
    size = 0
    if stop > start:
        size = utf8_skip(first, stop - start)
    end
    piece = string_alloc(size)
    call copy_memory(piece + 16, first, size)
    return piece
end

function rt_runtime_string_contains(text, part):
    part_length = __lsl_qbe_load64(part + 8)
    if part_length == 0:
        return 1
    end
    last = __lsl_qbe_load64(text + 8) - part_length
    haystack = text + 16
    needle = part + 16
    first = __lsl_qbe_load8(needle)
    position = 0
    while position <= last:
        if __lsl_qbe_load8(haystack + position) == first:
            index = 1
            while index < part_length and __lsl_qbe_load8(haystack + position + index) == __lsl_qbe_load8(needle + index):
                index += 1
            end
            if index == part_length:
                return 1
            end
        end
        position += 1
    end
    return 0
end

# Přípona chybové zprávy s typem hodnoty, 0 pro neznámý typ.
function type_error_suffix(code):
    if code == 0 or code == 9:
        return ", got Int"
    elif code == 1:
        return ", got String"
    elif code == 2:
        return ", got List"
    elif code == 3:
        return ", got Dictionary"
    elif code == 4:
        return ", got Bool"
    elif code == 5:
        return ", got None"
    elif code == 6:
        return ", got Float"
    elif code == 7:
        return ", got Tuple"
    elif code == 8:
        return ", got RealArray"
    elif code == 10:
        return ", got Function"
    elif code == 13:
        return ", got IntArray"
    elif code == 14:
        return ", got FloatArray"
    elif code == 15:
        return ", got ByteArray"
    elif code == 16:
        return ", got Set"
    end
    return 0
end

# "zpráva, got Typ" (statický prefix + název typu hodnoty).
function rt_runtime_typed_error_message(prefix, value):
    suffix = type_error_suffix(core.rt_runtime_type_code(value))
    if suffix == 0:
        return prefix
    end
    return rt_runtime_string_concat(prefix, suffix)
end

# Chyba se statickým textem; vrací 0.
function cold_error(message):
    call __lsl_qbe_call1(__lsl_symbol("qbe_error_set"), message)
    return 0
end

# Chyba "zpráva, got Typ"; vrací 0.
function cold_type_error(message, value):
    call __lsl_qbe_call1(__lsl_symbol("qbe_error_set"), rt_runtime_typed_error_message(message, value))
    return 0
end
