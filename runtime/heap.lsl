# lsl: runtime
# Halda: bloky s 32B hlavičkou před objektem. Blok B: +0 kapacita, +8 další
# blok v seznamu všech bloků (hlava ve stavu +0), +16 druh (0 objekt, 1 volný,
# 2 surová data), +24 další volný blok / značka GC; objekt začíná na B+32.
# Volné bloky jsou v segregovaných seznamech (stav +192 + třída * 8): třídy
# 0..127 přesně po 8 B do 1024 B, 128..134 rozsahy se stropem, 135 zbytek.
# Bloky se nedělí ani neslučují. Halda je souvislá oblast se stavem na
# začátku (entry.lsl); nové bloky se berou za ukazatelem (stav +1296)
# a konec (+1304) roste o požadavek + 1 MiB mapováním přesně za něj, jako
# brk, ale přenositelně (brk jiné OS nemají a pod qemu nemusí růst).
# Limit adresního prostoru (prlimit --as) počítá jen skutečně použitou
# paměť, stejně jako u brk.
load core
load os_linux
load sync

HEAP_BLOCKS = 0
GC_ALLOCATED_BYTES = 144
FREE_LISTS = 192
HEAP_BUMP = 1296
HEAP_RESERVED = 1304
OBJECT_BITMAP = 1328
OBJECT_BITMAP_CAPACITY = 1336
HEADER_BYTES = 32
# Zpřístupňuje se po 64 KiB: násobek stránky jader se 4, 16 i 64 KiB.
COMMIT_GRAIN = 65536
MAX_OBJECT_BYTES = 1073741824
REUSE_PROBES = 128

function fatal_allocation():
    message = "LSL runtime error: MemoryError: allocator or object table exhausted\n"
    call os_linux.write(2, message + 16, __lsl_qbe_load64(message + 8))
    call os_linux.exit_process(70)
    return 0
end

function rt_runtime_fatal_allocation():
    return fatal_allocation()
end

# Zarovnaná velikost -> třída volného seznamu 0..135.
function rt_runtime_size_class(size):
    if size <= 1024:
        return __lsl_qbe_lshr(size, 3) - 1
    elif size <= 2048:
        return 128
    elif size <= 4096:
        return 129
    elif size <= 8192:
        return 130
    elif size <= 16384:
        return 131
    elif size <= 65536:
        return 132
    elif size <= 262144:
        return 133
    elif size <= 1048576:
        return 134
    end
    return 135
end

# Strop rozsahové třídy 128..134: všechny bloky třídy mají stejnou velikost.
function class_ceiling(size_class):
    if size_class == 128:
        return 2048
    elif size_class == 129:
        return 4096
    elif size_class == 130:
        return 8192
    elif size_class == 131:
        return 16384
    elif size_class == 132:
        return 65536
    elif size_class == 133:
        return 262144
    end
    return 1048576
end

# Bitmapa začátků objektů musí pokrýt haldu až po zpřístupněný konec.
# Nová oblast má dvojnásobnou velikost; zapíše se ukazatel, pak kapacita,
# stará oblast zůstává namapovaná pro souběžná čtení. Volá se se zámkem haldy.
function rt_runtime_object_bitmap_ensure():
    base = core.state()
    needed = __lsl_qbe_lshr(__lsl_qbe_load64(base + HEAP_RESERVED) - base, 6) + 1
    capacity = __lsl_qbe_load64(base + OBJECT_BITMAP_CAPACITY)
    if __lsl_qbe_ule(needed, capacity):
        return 0
    end
    size = (needed * 2 + 4095) & -4096
    bitmap = os_linux.map_anonymous(size, 16384)
    if bitmap < 0:
        call fatal_allocation()
    end
    old = __lsl_qbe_load64(base + OBJECT_BITMAP)
    offset = 0
    while __lsl_qbe_ult(offset, capacity):
        __lsl_qbe_store64(bitmap + offset, __lsl_qbe_load64(old + offset))
        offset += 8
    end
    __lsl_qbe_store64(base + OBJECT_BITMAP, bitmap)
    __lsl_qbe_store64(base + OBJECT_BITMAP_CAPACITY, size)
    return 0
end

# Nastaví bit začátku objektu (bloky se nedělí, bit se jen nastavuje).
function rt_runtime_register_object(object):
    base = core.state()
    index = __lsl_qbe_lshr(object - base, 3)
    byte = __lsl_qbe_lshr(index, 3)
    if not __lsl_qbe_ult(byte, __lsl_qbe_load64(base + OBJECT_BITMAP_CAPACITY)):
        call fatal_allocation()
    end
    cell = __lsl_qbe_load64(base + OBJECT_BITMAP) + byte
    __lsl_qbe_store8(cell, __lsl_qbe_load8(cell) | __lsl_qbe_shl(1, index & 7))
    return object
end

# Prodlouží haldu až po konec limit (zaokrouhleno na COMMIT_GRAIN);
# 0 = místo za haldou je obsazené nebo chybí paměť.
function commit_heap(limit):
    base = core.state()
    committed = __lsl_qbe_load64(base + HEAP_RESERVED)
    top = (limit + COMMIT_GRAIN - 1) & -COMMIT_GRAIN
    if __lsl_qbe_ule(top, committed):
        return 1
    end
    if os_linux.map_at(committed, top - committed) == 0:
        return 0
    end
    __lsl_qbe_store64(base + HEAP_RESERVED, top)
    return 1
end

# Nový blok za ukazatelem haldy (zámek haldy je držený).
function fresh_block(need):
    base = core.state()
    block = __lsl_qbe_load64(base + HEAP_BUMP)
    if __lsl_qbe_ule(block + need, __lsl_qbe_load64(base + HEAP_RESERVED)):
        __lsl_qbe_store64(base + HEAP_BUMP, block + need)
        return block
    end
    if commit_heap(block + need + 1048576) == 0:
        # U konce rezervace nebo paměti může selhat právě rezerva navíc:
        # zkusit přesně tento blok.
        if commit_heap(block + need) == 0:
            call fatal_allocation()
        end
    end
    call rt_runtime_object_bitmap_ensure()
    __lsl_qbe_store64(base + HEAP_BUMP, block + need)
    return block
end

function rt_runtime_alloc_kind(size, kind):
    # Záporný nebo nesmyslně velký požadavek nesmí po zarovnání přetéct.
    if size < 0 or size > MAX_OBJECT_BYTES:
        call fatal_allocation()
    end
    call sync.rt_runtime_mutex_lock()
    base = core.state()
    size = (size + 7) & -8
    size_class = rt_runtime_size_class(size)
    if size_class >= 128 and size_class < 135:
        size = class_ceiling(size_class)
    end
    # Tlak na GC počítá i znovu použité bloky.
    __lsl_qbe_store64(base + GC_ALLOCATED_BYTES, __lsl_qbe_load64(base + GC_ALLOCATED_BYTES) + size + HEADER_BYTES)
    head = base + FREE_LISTS + __lsl_qbe_shl(size_class, 3)
    block = __lsl_qbe_load64(head)
    previous = 0
    probes = REUSE_PROBES
    while block != 0:
        probes -= 1
        if probes == 0:
            break
        end
        if __lsl_qbe_load64(block + 16) != 0 and __lsl_qbe_load64(block) >= size:
            following = __lsl_qbe_load64(block + 24)
            if previous == 0:
                __lsl_qbe_store64(head, following)
            else:
                __lsl_qbe_store64(previous + 24, following)
            end
            # Větší blok z vyšší třídy se započítá celou kapacitou.
            __lsl_qbe_store64(base + GC_ALLOCATED_BYTES, __lsl_qbe_load64(base + GC_ALLOCATED_BYTES) + __lsl_qbe_load64(block) - size)
            __lsl_qbe_store64(block + 16, kind)
            __lsl_qbe_store64(block + 24, 0)
            if kind == 0:
                # Pozastavené vlákno nesmí vidět tag a délku předchozího objektu.
                __lsl_qbe_store64(block + 32, 0)
                __lsl_qbe_store64(block + 40, 0)
            end
            object = rt_runtime_register_object(block + HEADER_BYTES)
            call sync.rt_runtime_mutex_unlock()
            return object
        end
        previous = block
        block = __lsl_qbe_load64(block + 24)
    end
    block = fresh_block(size + HEADER_BYTES)
    __lsl_qbe_store64(block, size)
    __lsl_qbe_store64(block + 8, __lsl_qbe_load64(base + HEAP_BLOCKS))
    __lsl_qbe_store64(block + 16, kind)
    __lsl_qbe_store64(block + 24, 0)
    __lsl_qbe_store64(base + HEAP_BLOCKS, block)
    object = rt_runtime_register_object(block + HEADER_BYTES)
    call sync.rt_runtime_mutex_unlock()
    return object
end

function rt_runtime_alloc(size):
    return rt_runtime_alloc_kind(size, 0)
end

function rt_runtime_alloc_raw(size):
    return rt_runtime_alloc_kind(size, 2)
end
