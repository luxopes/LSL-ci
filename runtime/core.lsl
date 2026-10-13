# lsl: runtime
# Model hodnot: surový Int, nebo ukazatel na objekt na haldě.
# Objekt: +0 tag, +8 délka/hodnota, +16 kapacita, +24 data. Blok haldy má
# před objektem 32 B hlavičku (-16: druh bloku, 0 = objekt, 1 = volný,
# 2 = surová data). Bitmapa začátků objektů: bit (adresa - stav) / 8.

# Rozložení stavu (lsl_state, viz compiler/pure/runtime_abi_linux_x86_64.lsl).
OBJECT_BITMAP = 1328
OBJECT_BITMAP_CAPACITY = 1336

TAG_STRING = 1
TAG_BOOL = 4
TAG_NONE = 5
TAG_FLOAT = 6
TAG_INT = 9
TAG_FUNCTION = 10

function state():
    return __lsl_qbe_load64(__lsl_symbol("lsl_state"))
end

# Ukazatel na začátek živého objektu (ne surová data, ne volný blok).
function rt_runtime_is_heap_object(value):
    if value & 7 != 0:
        return 0
    end
    base = __lsl_qbe_load64(__lsl_symbol("lsl_state"))
    index = __lsl_qbe_lshr(value - base, 3)
    # Kapacita se čte před ukazatelem (zapisovatel ukládá opačně).
    if not __lsl_qbe_ult(__lsl_qbe_lshr(index, 3), __lsl_qbe_load64(base + OBJECT_BITMAP_CAPACITY)):
        return 0
    end
    bitmap = __lsl_qbe_load64(base + OBJECT_BITMAP)
    if __lsl_qbe_lshr(__lsl_qbe_load8(bitmap + __lsl_qbe_lshr(index, 3)), index & 7) & 1 == 0:
        return 0
    end
    if __lsl_qbe_load64(value - 16) != 0:
        return 0
    end
    return 1
end

function rt_runtime_type_code(value):
    if rt_runtime_is_heap_object(value):
        return __lsl_qbe_load64(value)
    elif value == 0:
        return TAG_NONE
    end
    return 0
end

function rt_runtime_truth(value):
    if not rt_runtime_is_heap_object(value):
        return value != 0
    end
    tag = __lsl_qbe_load64(value)
    if tag == TAG_NONE:
        return 0
    elif tag == TAG_FLOAT:
        # +0.0 i -0.0 jsou nepravdivé: bity bez znaménka.
        return __lsl_qbe_shl(__lsl_qbe_load64(value + 8), 1) != 0
    end
    # Bool hodnota, délka řetězce nebo počet prvků kolekce.
    return __lsl_qbe_load64(value + 8) != 0
end

function rt_runtime_unbox_dynamic_bool(value):
    if rt_runtime_is_heap_object(value) and __lsl_qbe_load64(value) == TAG_BOOL:
        return __lsl_qbe_load64(value + 8)
    end
    return value
end

function rt_runtime_unbox_dynamic_function(value):
    if rt_runtime_is_heap_object(value) and __lsl_qbe_load64(value) == TAG_FUNCTION:
        return __lsl_qbe_load64(value + 8)
    end
    return value
end

# Surový Int beze změny, Int a Bool rozbalí, ostatní objekty vrátí.
function rt_runtime_unbox_dynamic_int(value):
    if rt_runtime_is_heap_object(value):
        tag = __lsl_qbe_load64(value)
        if tag == TAG_INT or tag == TAG_BOOL:
            return __lsl_qbe_load64(value + 8)
        end
    end
    return value
end

function rt_runtime_unbox_dynamic_float(value):
    if rt_runtime_is_heap_object(value) and __lsl_qbe_load64(value) == TAG_FLOAT:
        return __lsl_qbe_load64(value + 8)
    end
    return value
end

