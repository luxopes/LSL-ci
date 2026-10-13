# lsl: runtime
# Dictionary: +0 tag 3, +8 počet, +16 kapacita, +24 klíče, +32 hodnoty
# (pořadí vložení), +40 index (0 = malý slovník bez indexu), +48 počet slotů
# indexu (mocnina 2). Položka indexu: bity 0-31 pozice + 1 (0 = prázdný slot),
# bit 32 klíč je String, bity 33-63 horních 31 bitů hashe; slot se volí
# z týchž bitů. Formát čte i contains, clear a GC.
load core
load strings

DICT_COUNT = 8
DICT_CAPACITY = 16
DICT_KEYS = 24
DICT_VALUES = 32
DICT_INDEX = 40
DICT_SLOTS = 48

# Šablona položky indexu: (hash >> 33) << 33 | String << 32. Hash: seed
# procesu, FNV-1a pro String, hodnota zabaleného skaláru nebo surové slovo,
# pak SplitMix64 (stejné jako x86 runtime_key_hash).
function dict_key_template(key):
    if core.rt_runtime_is_heap_object(key):
        if __lsl_qbe_load64(key) == core.TAG_STRING:
            return __lsl_qbe_shl(__lsl_qbe_lshr(strings.string_hash(key), 33), 33) | 4294967296
        end
        key = __lsl_qbe_load64(key + 8)
    end
    hash = strings.hash_mix(key ~ __lsl_qbe_load64(core.state() + 120))
    return __lsl_qbe_shl(__lsl_qbe_lshr(hash, 33), 33)
end

# Rovnost klíčů se stejnou šablonou: String přímo, jinak obecně.
function dict_keys_equal(left, right, template):
    if left == right:
        return 1
    elif __lsl_qbe_lshr(template, 32) & 1:
        return strings.rt_runtime_string_equal(left, right)
    end
    return __lsl_qbe_call2(__lsl_symbol("rt_runtime_equal_any"), left, right)
end

# Pozice klíče + 1, nebo 0. S indexem uloží do slot_out slot nalezeného
# klíče, nebo první prázdný slot pro vložení.
function dict_find(dict, key, template, slot_out):
    keys = __lsl_qbe_load64(dict + DICT_KEYS)
    index = __lsl_qbe_load64(dict + DICT_INDEX)
    if index == 0:
        count = __lsl_qbe_load64(dict + DICT_COUNT)
        position = 0
        while __lsl_qbe_ult(position, count):
            stored = __lsl_qbe_load64(keys + __lsl_qbe_shl(position, 3))
            if stored == key or __lsl_qbe_call2(__lsl_symbol("rt_runtime_equal_any"), stored, key):
                return position + 1
            end
            position += 1
        end
        return 0
    end
    mask = __lsl_qbe_load64(dict + DICT_SLOTS) - 1
    want = __lsl_qbe_lshr(template, 32)
    slot = __lsl_qbe_lshr(template, 33) & mask
    while True:
        entry = __lsl_qbe_load64(index + __lsl_qbe_shl(slot, 3))
        if entry == 0:
            __lsl_qbe_store64(slot_out, slot)
            return 0
        end
        if __lsl_qbe_lshr(entry, 32) == want:
            position = (entry & 4294967295) - 1
            if dict_keys_equal(__lsl_qbe_load64(keys + __lsl_qbe_shl(position, 3)), key, template):
                __lsl_qbe_store64(slot_out, slot)
                return position + 1
            end
        end
        slot = (slot + 1) & mask
    end
    return 0
end

# Vloží položku do prvního prázdného slotu podle šablony (index existuje).
function dict_index_insert(dict, template, position):
    index = __lsl_qbe_load64(dict + DICT_INDEX)
    mask = __lsl_qbe_load64(dict + DICT_SLOTS) - 1
    slot = __lsl_qbe_lshr(template, 33) & mask
    while __lsl_qbe_load64(index + __lsl_qbe_shl(slot, 3)) != 0:
        slot = (slot + 1) & mask
    end
    __lsl_qbe_store64(index + __lsl_qbe_shl(slot, 3), template | (position + 1))
    return 0
end

# Vynuluje index a vloží všechny klíče znovu (po mazání a při vzniku indexu).
function dict_reindex(dict):
    index = __lsl_qbe_load64(dict + DICT_INDEX)
    slots = __lsl_qbe_load64(dict + DICT_SLOTS)
    slot = 0
    while __lsl_qbe_ult(slot, slots):
        __lsl_qbe_store64(index + __lsl_qbe_shl(slot, 3), 0)
        slot += 1
    end
    keys = __lsl_qbe_load64(dict + DICT_KEYS)
    count = __lsl_qbe_load64(dict + DICT_COUNT)
    position = 0
    while __lsl_qbe_ult(position, count):
        call dict_index_insert(dict, dict_key_template(__lsl_qbe_load64(keys + __lsl_qbe_shl(position, 3))), position)
        position += 1
    end
    return 0
end

# Zdvojnásobí kapacitu polí; index má dvojnásobek kapacity slotů. Položky
# indexu se přesunou podle uloženého hashe, první index se zahashuje.
function dict_grow(dict):
    count = __lsl_qbe_load64(dict + DICT_COUNT)
    capacity = __lsl_qbe_load64(dict + DICT_CAPACITY) * 2
    new_keys = __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc_raw"), __lsl_qbe_shl(capacity, 3))
    new_values = __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc_raw"), __lsl_qbe_shl(capacity, 3))
    keys = __lsl_qbe_load64(dict + DICT_KEYS)
    values = __lsl_qbe_load64(dict + DICT_VALUES)
    position = 0
    while __lsl_qbe_ult(position, count):
        offset = __lsl_qbe_shl(position, 3)
        __lsl_qbe_store64(new_keys + offset, __lsl_qbe_load64(keys + offset))
        __lsl_qbe_store64(new_values + offset, __lsl_qbe_load64(values + offset))
        position += 1
    end
    __lsl_qbe_store64(dict + DICT_CAPACITY, capacity)
    __lsl_qbe_store64(dict + DICT_KEYS, new_keys)
    __lsl_qbe_store64(dict + DICT_VALUES, new_values)
    old_index = __lsl_qbe_load64(dict + DICT_INDEX)
    old_slots = __lsl_qbe_load64(dict + DICT_SLOTS)
    slots = capacity * 2
    __lsl_qbe_store64(dict + DICT_SLOTS, slots)
    index = __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc_raw"), __lsl_qbe_shl(slots, 3))
    __lsl_qbe_store64(dict + DICT_INDEX, index)
    if old_index == 0:
        return dict_reindex(dict)
    end
    slot = 0
    while __lsl_qbe_ult(slot, slots):
        __lsl_qbe_store64(index + __lsl_qbe_shl(slot, 3), 0)
        slot += 1
    end
    mask = slots - 1
    old = 0
    while __lsl_qbe_ult(old, old_slots):
        entry = __lsl_qbe_load64(old_index + __lsl_qbe_shl(old, 3))
        if entry != 0:
            target = __lsl_qbe_lshr(entry, 33) & mask
            while __lsl_qbe_load64(index + __lsl_qbe_shl(target, 3)) != 0:
                target = (target + 1) & mask
            end
            __lsl_qbe_store64(index + __lsl_qbe_shl(target, 3), entry)
        end
        old += 1
    end
    return 0
end

function rt_runtime_dict_new():
    dict = __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc"), 56)
    __lsl_qbe_store64(dict, 3)
    __lsl_qbe_store64(dict + DICT_COUNT, 0)
    __lsl_qbe_store64(dict + DICT_CAPACITY, 16)
    __lsl_qbe_store64(dict + DICT_INDEX, 0)
    __lsl_qbe_store64(dict + DICT_SLOTS, 0)
    __lsl_qbe_store64(dict + DICT_KEYS, __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc_raw"), 128))
    __lsl_qbe_store64(dict + DICT_VALUES, __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc_raw"), 128))
    return dict
end

function rt_runtime_dict_get(dict, key):
    slot_out = __lsl_qbe_alloc(8)
    template = 0
    if __lsl_qbe_load64(dict + DICT_INDEX) != 0:
        template = dict_key_template(key)
    end
    found = dict_find(dict, key, template, slot_out)
    if found == 0:
        call __lsl_qbe_call1(__lsl_symbol("qbe_error_set"), "KeyError: key not found")
        return 0
    end
    return __lsl_qbe_load64(__lsl_qbe_load64(dict + DICT_VALUES) + __lsl_qbe_shl(found - 1, 3))
end

function rt_runtime_dict_set(dict, key, value):
    slot_out = __lsl_qbe_alloc(8)
    template = 0
    if __lsl_qbe_load64(dict + DICT_INDEX) != 0:
        template = dict_key_template(key)
    end
    found = dict_find(dict, key, template, slot_out)
    if found != 0:
        position = found - 1
    else:
        position = __lsl_qbe_load64(dict + DICT_COUNT)
        grew = 0
        if not __lsl_qbe_ult(position, __lsl_qbe_load64(dict + DICT_CAPACITY)):
            call dict_grow(dict)
            grew = 1
        end
        __lsl_qbe_store64(__lsl_qbe_load64(dict + DICT_KEYS) + __lsl_qbe_shl(position, 3), key)
        index = __lsl_qbe_load64(dict + DICT_INDEX)
        if index != 0:
            if grew:
                call dict_index_insert(dict, dict_key_template(key), position)
            else:
                __lsl_qbe_store64(index + __lsl_qbe_shl(__lsl_qbe_load64(slot_out), 3), template | (position + 1))
            end
        end
        __lsl_qbe_store64(dict + DICT_COUNT, position + 1)
    end
    __lsl_qbe_store64(__lsl_qbe_load64(dict + DICT_VALUES) + __lsl_qbe_shl(position, 3), value)
    return 0
end

function rt_runtime_dict_delete(dict, key):
    slot_out = __lsl_qbe_alloc(8)
    template = 0
    index = __lsl_qbe_load64(dict + DICT_INDEX)
    if index != 0:
        template = dict_key_template(key)
    end
    found = dict_find(dict, key, template, slot_out)
    if found == 0:
        call __lsl_qbe_call1(__lsl_symbol("qbe_error_set"), "KeyError: key not found")
        return 0
    end
    position = found - 1
    count = __lsl_qbe_load64(dict + DICT_COUNT) - 1
    __lsl_qbe_store64(dict + DICT_COUNT, count)
    keys = __lsl_qbe_load64(dict + DICT_KEYS)
    values = __lsl_qbe_load64(dict + DICT_VALUES)
    while __lsl_qbe_ult(position, count):
        offset = __lsl_qbe_shl(position, 3)
        __lsl_qbe_store64(keys + offset, __lsl_qbe_load64(keys + offset + 8))
        __lsl_qbe_store64(values + offset, __lsl_qbe_load64(values + offset + 8))
        position += 1
    end
    if index != 0:
        call dict_reindex(dict)
    end
    return 0
end

function rt_runtime_dict_keys(dict):
    return __lsl_qbe_call2(__lsl_symbol("rt_runtime_list_new"), __lsl_qbe_load64(dict + DICT_COUNT), __lsl_qbe_load64(dict + DICT_KEYS))
end
