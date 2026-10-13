# lsl: runtime
# Kořeny globálů programu (stav +16 začátek, +24 konec) a tabulky ve stavu:
# tabulka objektů (+32 adresa, +40 maska, +80 počet záznamů; nahradila ji
# bitmapa začátků objektů, zůstává kvůli testům a rezervě kompilátoru)
# a tabulka internovaných literálů (+48 adresa, +56 maska, strops).
load core
load heap
load os_linux

GLOBAL_ROOT_BEGIN = 16
GLOBAL_ROOT_END = 24
OBJECT_TABLE = 32
OBJECT_MASK = 40
INTERN_TABLE = 48
INTERN_MASK = 56
OBJECT_ENTRIES = 80

function rt_runtime_set_global_roots(begin, finish):
    base = core.state()
    __lsl_qbe_store64(base + GLOBAL_ROOT_BEGIN, begin)
    __lsl_qbe_store64(base + GLOBAL_ROOT_END, finish)
    return 0
end

# Při startu (před literály a vlákny) nahradí malou tabulku objektů
# tabulkou size bajtů s maskou mask, pokud ještě nic neobsahuje.
function rt_runtime_reserve_object_table(size, mask):
    base = core.state()
    if __lsl_qbe_load64(base + OBJECT_ENTRIES) != 0:
        return 0
    end
    if not __lsl_qbe_ult(__lsl_qbe_load64(base + OBJECT_MASK), mask):
        return 0
    end
    old = __lsl_qbe_load64(base + OBJECT_TABLE)
    old_size = __lsl_qbe_shl(__lsl_qbe_load64(base + OBJECT_MASK) + 1, 3)
    table = os_linux.map_anonymous(size, 0)
    if table < 0:
        call heap.fatal_allocation()
    end
    __lsl_qbe_store64(base + OBJECT_TABLE, table)
    __lsl_qbe_store64(base + OBJECT_MASK, mask)
    call os_linux.unmap(old, old_size)
    return 0
end

# __lsl_test_small_tables: obě tabulky na 8 slotů (vynulované) pro testy růstu.
function rt_runtime_test_small_tables():
    base = core.state()
    objects = __lsl_qbe_load64(base + OBJECT_TABLE)
    index = 0
    while index < 8:
        __lsl_qbe_store64(objects + __lsl_qbe_shl(index, 3), 0)
        index += 1
    end
    interned = __lsl_qbe_load64(base + INTERN_TABLE)
    index = 0
    while index < 16:
        __lsl_qbe_store64(interned + __lsl_qbe_shl(index, 3), 0)
        index += 1
    end
    __lsl_qbe_store64(base + OBJECT_MASK, 7)
    __lsl_qbe_store64(base + INTERN_MASK, 7)
    __lsl_qbe_store64(base + OBJECT_ENTRIES, 0)
    return 0
end

function rt_runtime_object_table_mask():
    return __lsl_qbe_load64(core.state() + OBJECT_MASK)
end

function rt_runtime_intern_table_mask():
    return __lsl_qbe_load64(core.state() + INTERN_MASK)
end

# Rozptyl zarovnaných adres před maskováním (jako x86 emit_object_hash).
function object_hash(pointer):
    hash = __lsl_qbe_lshr(pointer, 3) * -7046029254386353131
    return hash ~ __lsl_qbe_lshr(hash, 32)
end

# Dvojnásobná tabulka objektů z mmap se znovu rozmístěnými záznamy; stará
# zůstává namapovaná pro souběžná čtení. Vrací argument.
function rt_runtime_grow_object_table(value):
    base = core.state()
    old = __lsl_qbe_load64(base + OBJECT_TABLE)
    mask = __lsl_qbe_load64(base + OBJECT_MASK)
    if mask > 33554431:
        call heap.fatal_allocation()
    end
    capacity = (mask + 1) * 2
    new_mask = capacity - 1
    table = os_linux.map_anonymous(__lsl_qbe_shl(capacity, 3), 0)
    if table < 0:
        call heap.fatal_allocation()
    end
    index = 0
    while index <= mask:
        entry = __lsl_qbe_load64(old + __lsl_qbe_shl(index, 3))
        if entry != 0:
            slot = object_hash(entry) & new_mask
            while __lsl_qbe_load64(table + __lsl_qbe_shl(slot, 3)) != 0:
                slot = (slot + 1) & new_mask
            end
            __lsl_qbe_store64(table + __lsl_qbe_shl(slot, 3), entry)
        end
        index += 1
    end
    __lsl_qbe_store64(base + OBJECT_TABLE, table)
    __lsl_qbe_store64(base + OBJECT_MASK, new_mask)
    return value
end
