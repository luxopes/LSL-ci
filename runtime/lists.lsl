# lsl: runtime
# Kolekce: List (tag 2), Tuple 7, RealArray 8, IntArray 13, FloatArray 14,
# Set 16 mají +8 počet, +16 kapacitu a +24 surový buffer slov; ByteArray 15
# totéž s bajty. IntArray a FloatArray drží surové bity čísel (GC je nečte),
# ostatní hodnoty Any. Rutiny rt_runtime_* bez kontrol volá vnitřní ABI
# kompilátoru, rt_runtime_dynamic_* kontrolují typy a meze pro veřejné Any.
load core
load heap
load dict
load strops

TAG_LIST = 2
TAG_DICT = 3
TAG_TUPLE = 7
TAG_REAL_ARRAY = 8
TAG_INT_ARRAY = 13
TAG_FLOAT_ARRAY = 14
TAG_BYTE_ARRAY = 15
TAG_SET = 16
COUNT = 8
CAPACITY = 16
DATA = 24

# Kopie count slov (buffery jsou zarovnané).
function copy_words(destination, source, count):
    index = 0
    while index < count:
        __lsl_qbe_store64(destination + __lsl_qbe_shl(index, 3), __lsl_qbe_load64(source + __lsl_qbe_shl(index, 3)))
        index += 1
    end
    return 0
end

function box_int(value):
    return __lsl_qbe_call1(__lsl_symbol("rt_runtime_box_int"), value)
end

# --- ByteArray ---

function rt_runtime_byte_array_new():
    array = heap.rt_runtime_alloc(32)
    __lsl_qbe_store64(array, TAG_BYTE_ARRAY)
    __lsl_qbe_store64(array + COUNT, 0)
    __lsl_qbe_store64(array + CAPACITY, 64)
    __lsl_qbe_store64(array + DATA, heap.rt_runtime_alloc_raw(64))
    return array
end

# Nulový ByteArray délky count jedinou alokací dat (kapacita aspoň 64).
function rt_runtime_byte_array_zeros(count):
    if count < 0 or count > 1073741824:
        call heap.fatal_allocation()
    end
    array = heap.rt_runtime_alloc(32)
    __lsl_qbe_store64(array, TAG_BYTE_ARRAY)
    __lsl_qbe_store64(array + COUNT, count)
    capacity = count
    if capacity < 64:
        capacity = 64
    end
    __lsl_qbe_store64(array + CAPACITY, capacity)
    data = heap.rt_runtime_alloc_raw(capacity)
    __lsl_qbe_store64(array + DATA, data)
    # Alokace se zaokrouhluje na 8 B, nuluje se po slovech.
    offset = 0
    while offset < count:
        __lsl_qbe_store64(data + offset, 0)
        offset += 8
    end
    return array
end

function cold_byte_array_grow(array):
    capacity = __lsl_qbe_load64(array + CAPACITY)
    if capacity > 536870912:
        call heap.fatal_allocation()
    end
    capacity = capacity * 2
    data = heap.rt_runtime_alloc_raw(capacity)
    call strops.copy_memory(data, __lsl_qbe_load64(array + DATA), __lsl_qbe_load64(array + COUNT))
    __lsl_qbe_store64(array + CAPACITY, capacity)
    __lsl_qbe_store64(array + DATA, data)
    return 0
end

function rt_runtime_byte_array_append(array, value):
    count = __lsl_qbe_load64(array + COUNT)
    if count >= __lsl_qbe_load64(array + CAPACITY):
        call cold_byte_array_grow(array)
    end
    __lsl_qbe_store8(__lsl_qbe_load64(array + DATA) + count, value)
    __lsl_qbe_store64(array + COUNT, count + 1)
    return 0
end

function rt_runtime_byte_array_get(array, index):
    return __lsl_qbe_load8(__lsl_qbe_load64(array + DATA) + index)
end

function rt_runtime_byte_array_set(array, index, value):
    __lsl_qbe_store8(__lsl_qbe_load64(array + DATA) + index, value)
    return 0
end

# --- List a pole slov ---

# Nový List s count prvky ze source (source 0: nulové prvky pro typová pole).
function rt_runtime_list_new(count, source):
    if count < 0 or count > 134217728:
        call heap.fatal_allocation()
    end
    list = heap.rt_runtime_alloc(32)
    __lsl_qbe_store64(list, TAG_LIST)
    __lsl_qbe_store64(list + COUNT, count)
    capacity = count
    if capacity < 8:
        capacity = 8
    end
    __lsl_qbe_store64(list + CAPACITY, capacity)
    data = heap.rt_runtime_alloc_raw(__lsl_qbe_shl(capacity, 3))
    __lsl_qbe_store64(list + DATA, data)
    if source == 0:
        index = 0
        while index < count:
            __lsl_qbe_store64(data + __lsl_qbe_shl(index, 3), 0)
            index += 1
        end
    else:
        call copy_words(data, source, count)
    end
    return list
end

# Dvojnásobná kapacita bufferu slov.
function cold_list_grow(list):
    capacity = __lsl_qbe_load64(list + CAPACITY)
    if capacity > 67108864:
        call heap.fatal_allocation()
    end
    capacity = capacity * 2
    data = heap.rt_runtime_alloc_raw(__lsl_qbe_shl(capacity, 3))
    call copy_words(data, __lsl_qbe_load64(list + DATA), __lsl_qbe_load64(list + COUNT))
    __lsl_qbe_store64(list + CAPACITY, capacity)
    __lsl_qbe_store64(list + DATA, data)
    return 0
end

# Připojení bez kontrol typu prvku.
function list_push(list, value):
    count = __lsl_qbe_load64(list + COUNT)
    if count >= __lsl_qbe_load64(list + CAPACITY):
        call cold_list_grow(list)
    end
    __lsl_qbe_store64(__lsl_qbe_load64(list + DATA) + __lsl_qbe_shl(count, 3), value)
    __lsl_qbe_store64(list + COUNT, count + 1)
    return 0
end

# Typová pole ukládají surové bity (zabalený skalár by GC v poli nenašel),
# ByteArray bajt.
function cold_append_typed(list, value):
    tag = __lsl_qbe_load64(list)
    if tag == TAG_BYTE_ARRAY:
        return rt_runtime_byte_array_append(list, core.rt_runtime_unbox_dynamic_int(value))
    elif tag == TAG_INT_ARRAY:
        value = core.rt_runtime_unbox_dynamic_int(value)
    else:
        value = core.rt_runtime_unbox_dynamic_float(value)
    end
    return list_push(list, value)
end

function rt_runtime_list_append(list, value):
    tag = __lsl_qbe_load64(list)
    if tag == TAG_INT_ARRAY or tag == TAG_FLOAT_ARRAY or tag == TAG_BYTE_ARRAY:
        return cold_append_typed(list, value)
    end
    return list_push(list, value)
end

# Poslední prvek (volající ověřil neprázdnost).
function rt_runtime_list_pop_last(list):
    count = __lsl_qbe_load64(list + COUNT) - 1
    __lsl_qbe_store64(list + COUNT, count)
    return __lsl_qbe_load64(__lsl_qbe_load64(list + DATA) + __lsl_qbe_shl(count, 3))
end

function rt_runtime_list_clear(list):
    __lsl_qbe_store64(list + COUNT, 0)
    return 0
end

function rt_runtime_list_set(list, index, value):
    __lsl_qbe_store64(__lsl_qbe_load64(list + DATA) + __lsl_qbe_shl(index, 3), value)
    return 0
end

function rt_runtime_list_get(list, index):
    return __lsl_qbe_load64(__lsl_qbe_load64(list + DATA) + __lsl_qbe_shl(index, 3))
end

# --- Indexování bez kontrol (vnitřní ABI) ---

function rt_runtime_set_int_array(list, index, value):
    return rt_runtime_list_set(list, index, core.rt_runtime_unbox_dynamic_int(value))
end

function rt_runtime_set_float_array(list, index, value):
    return rt_runtime_list_set(list, index, core.rt_runtime_unbox_dynamic_float(value))
end

function rt_runtime_set_byte_array(list, index, value):
    return rt_runtime_byte_array_set(list, index, core.rt_runtime_unbox_dynamic_int(value))
end

function rt_runtime_set_dict(target, key, value):
    return dict.rt_runtime_dict_set(target, key, value)
end

function rt_runtime_set(target, index, value):
    tag = __lsl_qbe_load64(target)
    if tag == TAG_DICT:
        return dict.rt_runtime_dict_set(target, index, value)
    elif tag == TAG_BYTE_ARRAY:
        return rt_runtime_set_byte_array(target, index, value)
    elif tag == TAG_INT_ARRAY:
        return rt_runtime_set_int_array(target, index, value)
    elif tag == TAG_FLOAT_ARRAY:
        return rt_runtime_set_float_array(target, index, value)
    end
    return rt_runtime_list_set(target, index, value)
end

function rt_runtime_get_dict(target, key):
    return dict.rt_runtime_dict_get(target, key)
end

function rt_runtime_get_byte_array(array, index):
    if index < 0:
        index += __lsl_qbe_load64(array + COUNT)
    end
    return rt_runtime_byte_array_get(array, index)
end

function rt_runtime_get_list(list, index):
    if index < 0:
        index += __lsl_qbe_load64(list + COUNT)
    end
    return rt_runtime_list_get(list, index)
end

# Prvek; záporný index od konce, String vrací znak, Dictionary hodnotu klíče.
function rt_runtime_get(target, index):
    tag = __lsl_qbe_load64(target)
    if tag == core.TAG_STRING:
        return strops.rt_runtime_get_string(target, index)
    elif tag == TAG_DICT:
        return dict.rt_runtime_dict_get(target, index)
    elif tag == TAG_BYTE_ARRAY:
        return rt_runtime_get_byte_array(target, index)
    end
    return rt_runtime_get_list(target, index)
end

# Výřez [start, stop): String po znacích, ostatní jako nový List.
function rt_runtime_slice(target, start, stop):
    if __lsl_qbe_load64(target) == core.TAG_STRING:
        return strops.string_slice(target, start, stop)
    end
    length = __lsl_qbe_load64(target + COUNT)
    if start < 0:
        start += length
    end
    if stop < 0:
        stop += length
    end
    start = strops.rt_runtime_slice_clamp(start, length)
    count = strops.rt_runtime_slice_clamp(stop, length) - start
    if count < 0:
        count = 0
    end
    return rt_runtime_list_new(count, __lsl_qbe_load64(target + DATA) + __lsl_qbe_shl(start, 3))
end

# String -> List jednoznakových String v jednom průchodu. Znaky ASCII se
# v rámci volání sdílejí (mezipaměť 128 ukazatelů na zásobníku; všechny jsou
# zároveň v seznamu).
function rt_runtime_string_chars(text):
    length = __lsl_qbe_load64(text + 8)
    pieces = rt_runtime_list_new(0, 0)
    cache = __lsl_qbe_alloc(1024)
    slot = 0
    while slot < 128:
        __lsl_qbe_store64(cache + __lsl_qbe_shl(slot, 3), 0)
        slot += 1
    end
    position = 0
    while position < length:
        source = text + 16 + position
        byte = __lsl_qbe_load8(source)
        width = strops.utf8_width(byte)
        piece = 0
        if width == 1:
            piece = __lsl_qbe_load64(cache + __lsl_qbe_shl(byte, 3))
        end
        if piece == 0:
            piece = strops.string_alloc(width)
            offset = 0
            while offset < width:
                __lsl_qbe_store8(piece + 16 + offset, __lsl_qbe_load8(source + offset))
                offset += 1
            end
            if width == 1:
                __lsl_qbe_store64(cache + __lsl_qbe_shl(byte, 3), piece)
            end
        end
        call list_push(pieces, piece)
        position += width
    end
    return pieces
end

# --- Kontrolované operace pro veřejné Any ---

# Sekvenční index: zabalený Int nebo Bool (jinak chyba s typem indexu).
function index_valid(index):
    code = core.rt_runtime_type_code(index)
    if code == core.TAG_INT or code == core.TAG_BOOL:
        return 1
    end
    return 0
end

function rt_runtime_dynamic_length(value):
    code = core.rt_runtime_type_code(value)
    if code == core.TAG_STRING:
        return strops.utf8_length(value)
    elif code == TAG_LIST or code == TAG_DICT or code == TAG_TUPLE or code == TAG_REAL_ARRAY or code == TAG_INT_ARRAY or code == TAG_FLOAT_ARRAY or code == TAG_SET or code == TAG_BYTE_ARRAY:
        return __lsl_qbe_load64(value + COUNT)
    end
    return strops.cold_error("TypeError: object has no length")
end

# Iterace smí číst i prvky Set (meze zajišťuje smyčka).
function rt_runtime_iter_get(target, index):
    if core.rt_runtime_type_code(target) == TAG_SET:
        return rt_runtime_list_get(target, core.rt_runtime_unbox_dynamic_int(index))
    end
    return rt_runtime_dynamic_get(target, index)
end

function cold_dynamic_get(target, code, index):
    if code == TAG_BYTE_ARRAY:
        return box_int(rt_runtime_byte_array_get(target, index))
    elif code == TAG_INT_ARRAY:
        return box_int(rt_runtime_list_get(target, index))
    end
    return __lsl_qbe_call1(__lsl_symbol("rt_runtime_float_new"), rt_runtime_list_get(target, index))
end

function rt_runtime_dynamic_get(target, index):
    code = core.rt_runtime_type_code(target)
    if code == TAG_DICT:
        return dict.rt_runtime_dict_get(target, index)
    end
    if not (code == core.TAG_STRING or code == TAG_LIST or code == TAG_TUPLE or code == TAG_REAL_ARRAY or code == TAG_INT_ARRAY or code == TAG_FLOAT_ARRAY or code == TAG_BYTE_ARRAY):
        return strops.cold_type_error("TypeError: object is not indexable", target)
    end
    if not index_valid(index):
        return strops.cold_type_error("TypeError: sequence index must be Int", index)
    end
    position = __lsl_qbe_load64(index + 8)
    if code == core.TAG_STRING:
        length = strops.utf8_length(target)
    else:
        length = __lsl_qbe_load64(target + COUNT)
    end
    if position < 0:
        position += length
    end
    if position < 0 or position >= length:
        return strops.cold_error("IndexError: index out of range")
    end
    if code == core.TAG_STRING:
        return strops.string_char_at(target, position)
    elif code == TAG_LIST or code == TAG_TUPLE or code == TAG_REAL_ARRAY:
        return rt_runtime_list_get(target, position)
    end
    return cold_dynamic_get(target, code, position)
end

# Zápis do typového pole po kontrole typu hodnoty.
function cold_dynamic_set_typed(target, code, position, value):
    value_code = core.rt_runtime_type_code(value)
    if code == TAG_REAL_ARRAY:
        if value_code != core.TAG_INT and value_code != core.TAG_FLOAT:
            return strops.cold_error("TypeError: RealArray accepts only Int or Float values")
        end
        return rt_runtime_list_set(target, position, value)
    elif code == TAG_INT_ARRAY:
        if value_code != core.TAG_INT:
            return strops.cold_error("TypeError: IntArray accepts only Int values")
        end
        return rt_runtime_list_set(target, position, __lsl_qbe_load64(value + 8))
    elif code == TAG_FLOAT_ARRAY:
        if value_code != core.TAG_FLOAT:
            return strops.cold_error("TypeError: FloatArray accepts only Float values")
        end
        return rt_runtime_list_set(target, position, __lsl_qbe_load64(value + 8))
    end
    if value_code != core.TAG_INT:
        return strops.cold_error("TypeError: ByteArray accepts only Int values")
    end
    byte = __lsl_qbe_load64(value + 8)
    if byte < 0 or byte > 255:
        return strops.cold_error("ValueError: ByteArray value is outside 0..255")
    end
    return rt_runtime_byte_array_set(target, position, byte)
end

function rt_runtime_dynamic_set(target, index, value):
    code = core.rt_runtime_type_code(target)
    if code == TAG_DICT:
        return dict.rt_runtime_dict_set(target, index, value)
    end
    if not (code == TAG_LIST or code == TAG_REAL_ARRAY or code == TAG_INT_ARRAY or code == TAG_FLOAT_ARRAY or code == TAG_BYTE_ARRAY):
        return strops.cold_type_error("TypeError: object does not support indexed assignment", target)
    end
    if not index_valid(index):
        return strops.cold_type_error("TypeError: sequence index must be Int", index)
    end
    position = __lsl_qbe_load64(index + 8)
    length = __lsl_qbe_load64(target + COUNT)
    if position < 0:
        position += length
    end
    if position < 0 or position >= length:
        return strops.cold_error("IndexError: index out of range")
    end
    if code == TAG_LIST:
        return rt_runtime_list_set(target, position, value)
    end
    return cold_dynamic_set_typed(target, code, position, value)
end

function rt_runtime_dynamic_delete(target, index):
    code = core.rt_runtime_type_code(target)
    if code == TAG_DICT:
        return dict.rt_runtime_dict_delete(target, index)
    end
    if not (code == TAG_LIST or code == TAG_INT_ARRAY or code == TAG_FLOAT_ARRAY):
        return strops.cold_type_error("TypeError: object does not support indexed deletion", target)
    end
    if not index_valid(index):
        return strops.cold_type_error("TypeError: sequence index must be Int", index)
    end
    position = __lsl_qbe_load64(index + 8)
    count = __lsl_qbe_load64(target + COUNT)
    if position < 0:
        position += count
    end
    if position < 0 or position >= count:
        return strops.cold_error("IndexError: del index out of range")
    end
    count -= 1
    __lsl_qbe_store64(target + COUNT, count)
    data = __lsl_qbe_load64(target + DATA)
    while position < count:
        __lsl_qbe_store64(data + __lsl_qbe_shl(position, 3), __lsl_qbe_load64(data + __lsl_qbe_shl(position + 1, 3)))
        position += 1
    end
    return 0
end

function cold_dynamic_append_typed(target, code, value):
    value_code = core.rt_runtime_type_code(value)
    if code == TAG_INT_ARRAY:
        if value_code != core.TAG_INT:
            return strops.cold_error("TypeError: IntArray accepts only Int values")
        end
        return rt_runtime_list_append(target, __lsl_qbe_load64(value + 8))
    elif code == TAG_FLOAT_ARRAY:
        if value_code != core.TAG_FLOAT:
            return strops.cold_error("TypeError: FloatArray accepts only Float values")
        end
        return rt_runtime_list_append(target, __lsl_qbe_load64(value + 8))
    end
    if value_code != core.TAG_INT:
        return strops.cold_error("TypeError: ByteArray accepts only Int values")
    end
    byte = __lsl_qbe_load64(value + 8)
    if byte < 0 or byte > 255:
        return strops.cold_error("ValueError: ByteArray value is outside 0..255")
    end
    return rt_runtime_byte_array_append(target, byte)
end

function rt_runtime_dynamic_append(target, value):
    code = core.rt_runtime_type_code(target)
    if code == TAG_LIST:
        return rt_runtime_list_append(target, value)
    elif code == TAG_INT_ARRAY or code == TAG_FLOAT_ARRAY or code == TAG_BYTE_ARRAY:
        return cold_dynamic_append_typed(target, code, value)
    end
    return strops.cold_error("TypeError: object does not support append")
end

function rt_runtime_dynamic_clear(target):
    code = core.rt_runtime_type_code(target)
    if code == TAG_DICT:
        __lsl_qbe_store64(target + COUNT, 0)
        return dict.dict_reindex(target)
    elif code == TAG_LIST or code == TAG_INT_ARRAY or code == TAG_FLOAT_ARRAY or code == TAG_SET or code == TAG_BYTE_ARRAY:
        __lsl_qbe_store64(target + COUNT, 0)
        return 0
    end
    return strops.cold_error("TypeError: object does not support clear")
end

function rt_runtime_dynamic_dict_keys(target):
    if core.rt_runtime_type_code(target) != TAG_DICT:
        return strops.cold_error("TypeError: keys requires a Dictionary")
    end
    return dict.rt_runtime_dict_keys(target)
end
