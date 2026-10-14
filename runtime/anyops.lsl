# lsl: runtime
# Obecné operace nad Any: zabalení skalárů, rovnost, porovnání, aritmetika
# Int/Float s povýšením na Float, kontroly číselných operandů a `in`.
# Chování a texty chyb odpovídají dřívějším x86 rutinám přesně, včetně
# toho, že surový Int i Bool jsou jen čísla a raw 0 je zároveň None.
load core
load heap
load strings
load dict
load floats

TAG_DICTIONARY = 3

# --- Zabalení a rozbalení skalárů ---

function rt_runtime_box_int(value):
    box = heap.rt_runtime_alloc(24)
    __lsl_qbe_store64(box, core.TAG_INT)
    __lsl_qbe_store64(box + 8, value)
    return box
end

function rt_runtime_box_bool(value):
    box = heap.rt_runtime_alloc(24)
    __lsl_qbe_store64(box, core.TAG_BOOL)
    __lsl_qbe_store64(box + 8, value)
    return box
end

function rt_runtime_box_none():
    box = heap.rt_runtime_alloc(16)
    __lsl_qbe_store64(box, core.TAG_NONE)
    __lsl_qbe_store64(box + 8, 0)
    return box
end

# Function: +8 kód, +16 značka návratového typu (-1 neznámý).
function rt_runtime_box_function(code, return_tag):
    box = heap.rt_runtime_alloc(24)
    __lsl_qbe_store64(box, core.TAG_FUNCTION)
    __lsl_qbe_store64(box + 8, code)
    __lsl_qbe_store64(box + 16, return_tag)
    return box
end

function rt_runtime_box_dynamic_function(value, return_tag):
    if core.rt_runtime_is_heap_object(value) and __lsl_qbe_load64(value) == core.TAG_FUNCTION:
        return value
    end
    return rt_runtime_box_function(value, return_tag)
end

function rt_runtime_function_return_tag(value):
    if core.rt_runtime_is_heap_object(value) and __lsl_qbe_load64(value) == core.TAG_FUNCTION:
        return __lsl_qbe_load64(value + 16)
    end
    return -1
end

# Přechodová hranice Any: objekt na haldě zůstane, surový Int se zabalí.
function rt_runtime_box_dynamic_int(value):
    if core.rt_runtime_is_heap_object(value):
        return value
    end
    return rt_runtime_box_int(value)
end

function rt_runtime_unbox_bool(value):
    return __lsl_qbe_load64(value + 8)
end

function rt_runtime_unbox_int(value):
    return __lsl_qbe_load64(value + 8)
end

# Tag objektu na haldě, nebo 0 pro surové slovo (tagy objektů jsou >= 1).
function heap_tag(value):
    if core.rt_runtime_is_heap_object(value):
        return __lsl_qbe_load64(value)
    end
    return 0
end

# unbox_dynamic_int(value) při známém tagu.
function tagged_int(value, tag):
    if tag == core.TAG_INT or tag == core.TAG_BOOL:
        return __lsl_qbe_load64(value + 8)
    end
    return value
end

# Bity, které by měl coerce_float(value), při známém tagu a bez alokace.
function tagged_bits(value, tag):
    if tag == 0:
        return __lsl_raw_fitof(value)
    elif tag == core.TAG_INT or tag == core.TAG_BOOL:
        return __lsl_raw_fitof(__lsl_qbe_load64(value + 8))
    end
    return __lsl_qbe_load64(value + 8)
end

function rt_runtime_is_float(value):
    return heap_tag(value) == core.TAG_FLOAT
end

# Surový Int a zabalený Int/Bool se povýší na Float; cokoli jiného (i Float)
# se vrátí beze změny. Typ ověřují volající předem.
function rt_runtime_coerce_float(value):
    tag = heap_tag(value)
    if tag == 0 or tag == core.TAG_INT or tag == core.TAG_BOOL:
        return floats.rt_runtime_float_new(tagged_bits(value, tag))
    end
    return value
end

# --- Rovnost a porovnání ---

# Dva objekty: stejný tag a String po bajtech, Bool/Float/Int/Function podle
# hodnoty (Float bitově), None vždy; ostatní jen totožné. Objekt a surové
# slovo: Bool/Int/Function podle hodnoty, None jen s 0.
function rt_runtime_equal_any(left, right):
    if left == right:
        return 1
    end
    left_tag = heap_tag(left)
    right_tag = heap_tag(right)
    if left_tag != 0 and right_tag != 0:
        if left_tag != right_tag:
            return 0
        elif left_tag == core.TAG_STRING:
            return strings.rt_runtime_string_equal(left, right)
        elif left_tag == core.TAG_BOOL or left_tag == core.TAG_FLOAT or left_tag == core.TAG_INT or left_tag == core.TAG_FUNCTION:
            return __lsl_qbe_load64(left + 8) == __lsl_qbe_load64(right + 8)
        end
        return left_tag == core.TAG_NONE
    end
    object = left
    other = right
    tag = left_tag
    if left_tag == 0:
        if right_tag == 0:
            return 0
        end
        object = right
        other = left
        tag = right_tag
    end
    if tag == core.TAG_BOOL or tag == core.TAG_INT or tag == core.TAG_FUNCTION:
        return __lsl_qbe_load64(object + 8) == other
    end
    return tag == core.TAG_NONE and other == 0
end

# -1/0/1 podle left <=> right. S Float na jedné straně se obě strany
# porovnají jako Float (NaN dává -1 jako ucomisd + jb), jinak jako Int.
function rt_runtime_compare_any(left, right):
    left_tag = heap_tag(left)
    right_tag = heap_tag(right)
    if left_tag == core.TAG_FLOAT or right_tag == core.TAG_FLOAT:
        a = tagged_bits(left, left_tag)
        b = tagged_bits(right, right_tag)
        if not __lsl_raw_fge(a, b):
            return -1
        elif __lsl_raw_feq(a, b):
            return 0
        end
        return 1
    end
    a = tagged_int(left, left_tag)
    b = tagged_int(right, right_tag)
    if a < b:
        return -1
    elif a == b:
        return 0
    end
    return 1
end

# --- Aritmetika ---
# Varianty _raw (vnitřní kód překladače) vrací Int a Bool rozbalené, jako
# unbox_dynamic_int výsledku, ale celočíselný výsledek vůbec nebalí.

# Mocnina Int umocňováním na druhou (nejvýš 64 kroků), přetéká jako Int.
function rt_runtime_int_power(base, exponent):
    result = 1
    while exponent != 0:
        if exponent & 1:
            result = result * base
        end
        exponent = __lsl_qbe_lshr(exponent, 1)
        if exponent == 0:
            break
        end
        base = base * base
    end
    return result
end

function rt_runtime_abs_any_raw(value):
    tag = heap_tag(value)
    if tag == core.TAG_FLOAT:
        return floats.rt_runtime_float_new(__lsl_qbe_load64(value + 8) & floats.FLOAT_MAGNITUDE)
    end
    number = tagged_int(value, tag)
    if number < 0:
        return 0 - number
    end
    return number
end

function rt_runtime_abs_any(value):
    tag = heap_tag(value)
    if tag == core.TAG_FLOAT:
        return floats.rt_runtime_float_new(__lsl_qbe_load64(value + 8) & floats.FLOAT_MAGNITUDE)
    end
    number = tagged_int(value, tag)
    if number < 0:
        number = 0 - number
    end
    return rt_runtime_box_int(number)
end

function rt_runtime_neg_any_raw(value):
    tag = heap_tag(value)
    if tag == core.TAG_FLOAT:
        return floats.rt_runtime_float_new(__lsl_qbe_load64(value + 8) + floats.FLOAT_SIGN)
    end
    return 0 - tagged_int(value, tag)
end

function rt_runtime_neg_any(value):
    tag = heap_tag(value)
    if tag == core.TAG_FLOAT:
        return floats.rt_runtime_float_new(__lsl_qbe_load64(value + 8) + floats.FLOAT_SIGN)
    end
    return rt_runtime_box_int(0 - tagged_int(value, tag))
end

function cold_negative_exponent():
    call __lsl_qbe_call1(__lsl_symbol("qbe_error_set"), "ValueError: negative Int exponent")
    return 0
end

# Float základ: float_power; Int základ: int_power, záporný exponent je
# chyba (výsledek zabalená 0 jako dřív).
function rt_runtime_pow_any(base, exponent):
    if rt_runtime_is_float(base):
        return floats.rt_runtime_float_power(base, core.rt_runtime_unbox_dynamic_int(exponent))
    end
    power = core.rt_runtime_unbox_dynamic_int(exponent)
    if power < 0:
        return rt_runtime_box_int(cold_negative_exponent())
    end
    return rt_runtime_box_int(rt_runtime_int_power(core.rt_runtime_unbox_dynamic_int(base), power))
end

function rt_runtime_pow_any_raw(base, exponent):
    if rt_runtime_is_float(base):
        return floats.rt_runtime_float_power(base, core.rt_runtime_unbox_dynamic_int(exponent))
    end
    power = core.rt_runtime_unbox_dynamic_int(exponent)
    if power < 0:
        return cold_negative_exponent()
    end
    return rt_runtime_int_power(core.rt_runtime_unbox_dynamic_int(base), power)
end

# +: s Float na jedné straně Float součet; dva objekty, které nejsou Int,
# spojí string_concat; jinak součet Int.
function rt_runtime_add_any_raw(left, right):
    left_tag = heap_tag(left)
    right_tag = heap_tag(right)
    if left_tag == core.TAG_FLOAT or right_tag == core.TAG_FLOAT:
        return floats.rt_runtime_float_new(__lsl_raw_fadd(tagged_bits(left, left_tag), tagged_bits(right, right_tag)))
    elif left_tag != 0 and left_tag != core.TAG_INT and right_tag != 0 and right_tag != core.TAG_INT:
        return __lsl_qbe_call2(__lsl_symbol("rt_runtime_string_concat"), left, right)
    end
    return tagged_int(left, left_tag) + tagged_int(right, right_tag)
end

function rt_runtime_add_any(left, right):
    left_tag = heap_tag(left)
    right_tag = heap_tag(right)
    if left_tag == core.TAG_FLOAT or right_tag == core.TAG_FLOAT:
        return floats.rt_runtime_float_new(__lsl_raw_fadd(tagged_bits(left, left_tag), tagged_bits(right, right_tag)))
    elif left_tag != 0 and left_tag != core.TAG_INT and right_tag != 0 and right_tag != core.TAG_INT:
        return __lsl_qbe_call2(__lsl_symbol("rt_runtime_string_concat"), left, right)
    end
    return rt_runtime_box_int(tagged_int(left, left_tag) + tagged_int(right, right_tag))
end

function rt_runtime_sub_any_raw(left, right):
    left_tag = heap_tag(left)
    right_tag = heap_tag(right)
    if left_tag == core.TAG_FLOAT or right_tag == core.TAG_FLOAT:
        return floats.rt_runtime_float_new(__lsl_raw_fsub(tagged_bits(left, left_tag), tagged_bits(right, right_tag)))
    end
    return tagged_int(left, left_tag) - tagged_int(right, right_tag)
end

function rt_runtime_sub_any(left, right):
    left_tag = heap_tag(left)
    right_tag = heap_tag(right)
    if left_tag == core.TAG_FLOAT or right_tag == core.TAG_FLOAT:
        return floats.rt_runtime_float_new(__lsl_raw_fsub(tagged_bits(left, left_tag), tagged_bits(right, right_tag)))
    end
    return rt_runtime_box_int(tagged_int(left, left_tag) - tagged_int(right, right_tag))
end

function rt_runtime_mul_any_raw(left, right):
    left_tag = heap_tag(left)
    right_tag = heap_tag(right)
    if left_tag == core.TAG_FLOAT or right_tag == core.TAG_FLOAT:
        return floats.rt_runtime_float_new(__lsl_raw_fmul(tagged_bits(left, left_tag), tagged_bits(right, right_tag)))
    end
    return tagged_int(left, left_tag) * tagged_int(right, right_tag)
end

function rt_runtime_mul_any(left, right):
    left_tag = heap_tag(left)
    right_tag = heap_tag(right)
    if left_tag == core.TAG_FLOAT or right_tag == core.TAG_FLOAT:
        return floats.rt_runtime_float_new(__lsl_raw_fmul(tagged_bits(left, left_tag), tagged_bits(right, right_tag)))
    end
    return rt_runtime_box_int(tagged_int(left, left_tag) * tagged_int(right, right_tag))
end

# --- Kontroly operandů ---

function numeric_value_error():
    call __lsl_qbe_call1(__lsl_symbol("qbe_error_set"), "TypeError: numeric operand required")
    return 0
end

function numeric_pair_error():
    call __lsl_qbe_call1(__lsl_symbol("qbe_error_set"), "TypeError: numeric operands required")
    return 0
end

# Hodnota musí být Int, Bool, raw 0 (None) nebo v režimu 0 i Float; vrací ji.
function rt_runtime_require_numeric_value(value, mode):
    code = core.rt_runtime_type_code(value)
    if code == core.TAG_INT or code == core.TAG_BOOL or code == 0:
        return value
    elif code == core.TAG_FLOAT:
        if mode == 0:
            return value
        end
        return numeric_value_error()
    elif code == core.TAG_NONE and value == 0:
        return value
    end
    return numeric_value_error()
end

# Režim 1 dovolí i String + String, režim 2 zakáže Float vpravo. Číselná
# strana je Int, Bool, raw 0, nebo Float. Vrací left.
function rt_runtime_require_numeric_pair(left, right, mode):
    left_code = core.rt_runtime_type_code(left)
    right_code = core.rt_runtime_type_code(right)
    if mode == 1 and left_code == core.TAG_STRING:
        if right_code == core.TAG_STRING:
            return left
        end
        return numeric_pair_error()
    end
    if not (left_code == core.TAG_INT or left_code == core.TAG_BOOL or left_code == 0 or left_code == core.TAG_FLOAT):
        if left_code != core.TAG_NONE or left != 0:
            return numeric_pair_error()
        end
    end
    if right_code == core.TAG_INT or right_code == core.TAG_BOOL or right_code == 0:
        return left
    elif right_code == core.TAG_FLOAT:
        if mode != 2:
            return left
        end
        return numeric_pair_error()
    elif right_code == core.TAG_NONE and right == 0:
        return left
    end
    return numeric_pair_error()
end

function cold_index_type_error(value):
    message = __lsl_qbe_call2(__lsl_symbol("rt_runtime_typed_error_message"), "TypeError: sequence index must be Int", value)
    call __lsl_qbe_call1(__lsl_symbol("qbe_error_set"), message)
    return 0
end

# Veřejný index Any -> surový Int; Bool je 0/1, raw 0 projde, jiné typy
# jsou chyba "..., got Typ".
function rt_runtime_checked_index(value):
    code = core.rt_runtime_type_code(value)
    if code == core.TAG_INT or code == core.TAG_BOOL:
        return __lsl_qbe_load64(value + 8)
    elif code == 0 or value == 0:
        return value
    end
    return cold_index_type_error(value)
end

# --- `in` ---

# String: podřetězec, Dictionary: klíč, ostatní kolekce (+8 počet, +24 data):
# některý prvek rovný hledané hodnotě podle equal_any(prvek, hodnota).
function rt_runtime_contains(container, needle):
    tag = __lsl_qbe_load64(container)
    if tag == core.TAG_STRING:
        return __lsl_qbe_call2(__lsl_symbol("rt_runtime_string_contains"), container, needle)
    elif tag == TAG_DICTIONARY:
        slot_out = __lsl_qbe_alloc(8)
        template = 0
        if __lsl_qbe_load64(container + dict.DICT_INDEX) != 0:
            template = dict.dict_key_template(needle)
        end
        return dict.dict_find(container, needle, template, slot_out) != 0
    end
    data = __lsl_qbe_load64(container + 24)
    index = 0
    while index < __lsl_qbe_load64(container + 8):
        if rt_runtime_equal_any(__lsl_qbe_load64(data + __lsl_qbe_shl(index, 3)), needle):
            return 1
        end
        index += 1
    end
    return 0
end

# --- Hashe klíčů slovníku (vstupní body; výpočet je v strings) ---

function rt_runtime_hash_mix(value):
    return strings.hash_mix(value)
end

function rt_runtime_string_hash(text):
    return strings.string_hash(text)
end

# Hash konzistentní s equal_any: String bajty, zabalený skalár hodnota,
# surové slovo samo, vždy se seedem procesu a SplitMix64.
function rt_runtime_key_hash(key):
    if core.rt_runtime_is_heap_object(key):
        if __lsl_qbe_load64(key) == core.TAG_STRING:
            return strings.string_hash(key)
        end
        key = __lsl_qbe_load64(key + 8)
    end
    return strings.hash_mix(key ~ __lsl_qbe_load64(core.state() + 120))
end

# Překladač: lexerem ověřený token bez znaménka -> surový Int (přetéká).
function rt_runtime_parse_literal_int(text):
    length = __lsl_qbe_load64(text + 8)
    data = text + 16
    value = 0
    index = 0
    while index < length:
        value = value * 10 + __lsl_qbe_load8(data + index) - 48
        index += 1
    end
    return value
end
