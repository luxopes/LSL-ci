# lsl: runtime
# Konzervativní mark-and-sweep GC. Kořeny: zásobníky všech vláken (pracovní
# vlákna zastaví signál, registry uloží jádro do sigframe), uložené
# callee-saved registry, globály programu, internované literály, čekající
# chyba a poslední stderr z capture(). Značka je slovo B+24 (objekt -8):
# 0 = neviděný, 1 = označený / konec seznamu, adresa = další objekt
# v intruzivním pracovním seznamu (stav +184), takže značkování nealokuje
# a nerekurzí ani na hlubokých a cyklických grafech.
load core
load _runtime_os as os
load heap
load sync

GC_INCOMPLETE = 8
GLOBAL_ROOT_BEGIN = 16
GLOBAL_ROOT_END = 24
INTERN_TABLE = 48
INTERN_MASK = 56
CAPTURE_STDERR = 72
THREAD_TABLE = 112
# Blok hlavního vlákna (+16 vrchol jeho zásobníku). Stav +120 je blok
# argumentů procesu, na Linuxu shodný s vrcholem zásobníku.
MAIN_THREAD_BLOCK = 160
GC_GATE = 128
GC_ALLOCATED_BYTES = 144
GC_BUDGET = 152
GC_WORKLIST = 184
TLS_ERROR = 0
TLS_STACK_TOP = 16
THREAD_SLOTS = 128
GC_BUDGET_FLOOR = 4194304
MAX_TRACED_ITEMS = 134217728
MAX_RAW_ITEMS = 1073741824

# Slovo TLS bloku runtime aktuálního vlákna.
function thread_word(offset):
    return __lsl_qbe_call1(__lsl_symbol("lsl_arch_tls_load"), offset)
end

# Začátek bloku haldy, který není volný (objekt nebo surová data).
function rt_runtime_is_heap_allocation(value):
    if value & 7 != 0:
        return 0
    end
    base = core.state()
    index = __lsl_qbe_lshr(value - base, 3)
    if not __lsl_qbe_ult(__lsl_qbe_lshr(index, 3), __lsl_qbe_load64(base + heap.OBJECT_BITMAP_CAPACITY)):
        return 0
    end
    bitmap = __lsl_qbe_load64(base + heap.OBJECT_BITMAP)
    if __lsl_qbe_lshr(__lsl_qbe_load8(bitmap + __lsl_qbe_lshr(index, 3)), index & 7) & 1 == 0:
        return 0
    end
    if __lsl_qbe_load64(value - 16) == 1:
        return 0
    end
    return 1
end

# Označí platný blok; vrací 1 jen při prvním označení.
function rt_runtime_mark_shallow(value):
    if not rt_runtime_is_heap_allocation(value) or __lsl_qbe_load64(value - 8) != 0:
        return 0
    end
    __lsl_qbe_store64(value - 8, 1)
    return 1
end

# Ověří zálohu kolekce před čtením: surový blok s aspoň `size` bajty. Zastavené
# vlákno může být mezi zveřejněním délky a výměnou zálohy; pak se sweep odloží.
function rt_runtime_gc_buffer(buffer, size):
    if rt_runtime_is_heap_allocation(buffer) and __lsl_qbe_load64(buffer - 16) == 2 and size >= 0 and not __lsl_qbe_ult(__lsl_qbe_load64(buffer - 32), size):
        return 1
    end
    __lsl_qbe_store64(core.state() + GC_INCOMPLETE, 1)
    return 0
end

# Označí hodnotu a objekt s odkazy zařadí do pracovního seznamu.
function rt_runtime_mark(value):
    if rt_runtime_mark_shallow(value) and __lsl_qbe_load64(value - 16) != 2:
        base = core.state()
        link = __lsl_qbe_load64(base + GC_WORKLIST)
        if link == 0:
            link = 1
        end
        __lsl_qbe_store64(value - 8, link)
        __lsl_qbe_store64(base + GC_WORKLIST, value)
    end
    return 0
end

function incomplete():
    __lsl_qbe_store64(core.state() + GC_INCOMPLETE, 1)
    return 0
end

# Projde odkazy jednoho objektu.
function rt_runtime_trace(object):
    tag = __lsl_qbe_load64(object)
    count = __lsl_qbe_load64(object + 8)
    if tag == 2 or tag == 7 or tag == 8 or tag == 16:
        # List, Tuple, RealArray, Set: pole hodnot Any.
        if __lsl_qbe_ult(MAX_TRACED_ITEMS, count):
            return incomplete()
        end
        items = __lsl_qbe_load64(object + 24)
        if not rt_runtime_gc_buffer(items, __lsl_qbe_shl(count, 3)):
            return 0
        end
        call rt_runtime_mark_shallow(items)
        index = 0
        while index < __lsl_qbe_load64(object + 8):
            call rt_runtime_mark(__lsl_qbe_load64(items + __lsl_qbe_shl(index, 3)))
            index += 1
        end
    elif tag == 13 or tag == 14 or tag == 15:
        # IntArray, FloatArray, ByteArray: surová čísla, jen záloha.
        if __lsl_qbe_ult(MAX_RAW_ITEMS, count):
            return incomplete()
        end
        size = count
        if tag != 15:
            if __lsl_qbe_ult(MAX_TRACED_ITEMS, count):
                return incomplete()
            end
            size = __lsl_qbe_shl(count, 3)
        end
        items = __lsl_qbe_load64(object + 24)
        if rt_runtime_gc_buffer(items, size):
            call rt_runtime_mark_shallow(items)
        end
    elif tag == 3:
        # Dictionary: klíče, hodnoty a index.
        if __lsl_qbe_ult(MAX_TRACED_ITEMS, count):
            return incomplete()
        end
        size = __lsl_qbe_shl(count, 3)
        keys = __lsl_qbe_load64(object + 24)
        if not rt_runtime_gc_buffer(keys, size):
            return 0
        end
        call rt_runtime_mark_shallow(keys)
        call rt_runtime_mark_shallow(__lsl_qbe_load64(object + 40))
        values = __lsl_qbe_load64(object + 32)
        if not rt_runtime_gc_buffer(values, size):
            return 0
        end
        call rt_runtime_mark_shallow(values)
        index = 0
        while index < __lsl_qbe_load64(object + 8):
            call rt_runtime_mark(__lsl_qbe_load64(keys + __lsl_qbe_shl(index, 3)))
            call rt_runtime_mark(__lsl_qbe_load64(values + __lsl_qbe_shl(index, 3)))
            index += 1
        end
    elif tag == 12:
        # Nativní funkce drží svou knihovnu.
        call rt_runtime_mark(__lsl_qbe_load64(object + 16))
    end
    return 0
end

# Označí každé slovo v rozsahu [begin, end) jako kořen.
# 32bitové cíle (os.ROOT_WORD_BYTES 4): po 4 bajtech, slovo rozšířené nulami.
function mark_range(begin, finish):
    if os.ROOT_WORD_BYTES == 4:
        while __lsl_qbe_ult(begin, finish):
            call mark_root(__lsl_qbe_load32(begin))
            begin += 4
        end
        return 0
    end
    while __lsl_qbe_ult(begin, finish):
        call mark_root(__lsl_qbe_load64(begin))
        begin += 8
    end
    return 0
end

# Kořen ze zásobníku nebo registru. Kód z LuxIR smí držet i odvozený
# ukazatel (začátek bloku, adresu pole uvnitř objektu): takový ukazatel
# objekt drží také. Hledá se nejbližší začátek objektu v bitmapě do
# INTERIOR_REACH bajtů zpět a ukazatel musí ležet uvnitř jeho bloku.
INTERIOR_REACH = 65536
function mark_root(value):
    if rt_runtime_is_heap_allocation(value):
        return rt_runtime_mark(value)
    end
    base = core.state()
    address = value & -8
    if not __lsl_qbe_ult(address - base, __lsl_qbe_load64(base + heap.HEAP_RESERVED) - base):
        return 0
    end
    # Ukazatel do hlavičky bloku (B .. B+31): objekt začíná za ní.
    candidate = address + 8
    while __lsl_qbe_ule(candidate, address + heap.HEADER_BYTES):
        if rt_runtime_is_heap_allocation(candidate):
            return rt_runtime_mark(candidate)
        end
        candidate += 8
    end
    bitmap = __lsl_qbe_load64(base + heap.OBJECT_BITMAP)
    capacity = __lsl_qbe_load64(base + heap.OBJECT_BITMAP_CAPACITY)
    index = __lsl_qbe_lshr(address - base, 3)
    lowest = 0
    if index > __lsl_qbe_lshr(INTERIOR_REACH, 3):
        lowest = index - __lsl_qbe_lshr(INTERIOR_REACH, 3)
    end
    while index > lowest:
        index -= 1
        byte_index = __lsl_qbe_lshr(index, 3)
        if not __lsl_qbe_ult(byte_index, capacity):
            return 0
        end
        bits = __lsl_qbe_load8(bitmap + byte_index)
        if bits == 0:
            index = __lsl_qbe_shl(byte_index, 3)
        elif __lsl_qbe_lshr(bits, index & 7) & 1:
            start = base + __lsl_qbe_shl(index, 3)
            if __lsl_qbe_load64(start - 16) != 1 and __lsl_qbe_ult(address - start, __lsl_qbe_load64(start - 32)):
                return rt_runtime_mark(start)
            end
            return 0
        end
    end
    return 0
end

function thread_entry(index):
    return __lsl_qbe_load64(core.state() + THREAD_TABLE) + __lsl_qbe_shl(index, 6) + 8
end

# Zastaví běžící pracovní vlákna (vrstva OS: Linux SIGUSR1, obsluha signálu
# vlákno uspí; Windows SuspendThread) a počká, až jsou všechna uspaná
# (status 2). Stav 4 = zastavení vyžádané, vlákno ještě běží.
function suspend_workers():
    process = os.getpid()
    while True:
        pending = 0
        index = 0
        while index < THREAD_SLOTS - 1:
            entry = thread_entry(index)
            status = __lsl_qbe_load64(entry + 16)
            # 1 -> 4 atomicky: končící vlákno mezitím může stav vynulovat
            # (CLONE_CHILD_CLEARTID) a zapsaná 4 by pak zůstala navždy.
            if status == 1 and sync.atomic_cas(entry + 16, 1, 4) == 1:
                call os.thread_suspend(process, entry)
                pending = 1
            elif status == 4:
                pending = 1
            end
            index += 1
        end
        if pending == 0:
            return 0
        end
        call __lsl_qbe_call0(__lsl_symbol("lsl_arch_pause"))
    end
    return 0
end

# Vrstva OS, která vlákna zastavuje sama (Windows), je zase spustí; na
# Linuxu se vlákna probudí na bráně.
function resume_workers():
    if not os.THREAD_RESUME:
        return 0
    end
    index = 0
    while index < THREAD_SLOTS - 1:
        entry = thread_entry(index)
        if __lsl_qbe_load64(entry + 16) == 2:
            call os.thread_resume(entry)
        end
        index += 1
    end
    return 0
end

function wait_resumed():
    index = 0
    while index < THREAD_SLOTS - 1:
        if __lsl_qbe_load64(thread_entry(index) + 16) == 2:
            call os.sched_yield()
        else:
            index += 1
        end
    end
    return 0
end

# Uspaná vlákna: čekající chyba a zásobník od uloženého rsp k základně.
function mark_workers():
    index = 0
    while index < THREAD_SLOTS - 1:
        entry = thread_entry(index)
        status = __lsl_qbe_load64(entry + 16)
        if status == 2:
            call rt_runtime_mark(__lsl_qbe_load64(entry + 32))
            call mark_range(__lsl_qbe_load64(entry + 24), __lsl_qbe_load64(entry + 8))
            # Registry zastaveného vlákna, které vrstva OS uložila mimo jeho
            # zásobník (Windows: kontext z GetThreadContext).
            registers = os.thread_registers(entry)
            if registers != 0:
                call mark_range(registers, registers + os.THREAD_REGISTER_BYTES)
            end
        elif status == 3:
            # Spuštěné vlákno, které se ještě nezveřejnilo: jeho funkce.
            call rt_runtime_mark(__lsl_qbe_load64(entry + 24))
        end
        index += 1
    end
    return 0
end

# Uvolní neoznačené bloky do volných seznamů; vrací počet uvolněných bloků
# s prvním slovem 1..8 a do live uloží živé bajty mimo surová data.
function sweep(live):
    base = core.state()
    keep_all = __lsl_qbe_load64(base + GC_INCOMPLETE) != 0
    freed = 0
    live_bytes = 0
    block = __lsl_qbe_load64(base + heap.HEAP_BLOCKS)
    while block != 0:
        kind = __lsl_qbe_load64(block + 16)
        # Volný blok: +24 je odkaz volného seznamu, ne značka.
        if kind != 1:
            if keep_all or __lsl_qbe_load64(block + 24) != 0:
                __lsl_qbe_store64(block + 24, 0)
                if kind != 2:
                    live_bytes += __lsl_qbe_load64(block) + heap.HEADER_BYTES
                end
            else:
                tag = __lsl_qbe_load64(block + 32)
                if kind != 2 and tag == 11 and __lsl_qbe_load64(block + 40) != 0 and __lsl_qbe_load64(block + 48) >= 64:
                    # Nedosažitelná nativní knihovna: odmapovat její obraz.
                    call os.unmap(__lsl_qbe_load64(block + 40), __lsl_qbe_load64(block + 48))
                end
                __lsl_qbe_store64(block + 16, 1)
                head = base + heap.FREE_LISTS + __lsl_qbe_shl(heap.rt_runtime_size_class(__lsl_qbe_load64(block)), 3)
                __lsl_qbe_store64(block + 24, __lsl_qbe_load64(head))
                __lsl_qbe_store64(head, block)
                # Počítá se podle prvního slova i u surových bloků (jako dosud).
                if tag >= 1 and tag <= 8:
                    freed += 1
                end
            end
        end
        block = __lsl_qbe_load64(block + 8)
    end
    __lsl_qbe_store64(live, live_bytes)
    return freed
end

function rt_runtime_gc():
    # Kořeny v callee-saved registrech volajících (kód LuxIR je tam smí držet).
    registers = __lsl_qbe_alloc(96)
    stack = __lsl_qbe_call1(__lsl_symbol("lsl_arch_spill"), registers)
    base = core.state()
    # Sbírá jen hlavní vlákno; pracovní vlákna se vrátí hned.
    if thread_word(TLS_STACK_TOP) != __lsl_qbe_load64(base + MAIN_THREAD_BLOCK + TLS_STACK_TOP):
        return 0
    end
    call sync.rt_runtime_mutex_lock()
    __lsl_qbe_store64(base + GC_WORKLIST, 0)
    __lsl_qbe_store64(base + GC_INCOMPLETE, 0)
    call rt_runtime_mark(thread_word(TLS_ERROR))
    # Zastavení světa: vlákna se uspí na bráně (stav +128) až do konce sweepu.
    call sync.rt_runtime_table_lock()
    __lsl_qbe_store64(base + GC_GATE, 1)
    call suspend_workers()
    call mark_workers()
    # Paměťové kořeny až po zastavení vláken: vlákno mohlo do globálu
    # uložit nový objekt, který drží už jen tam.
    call rt_runtime_mark(__lsl_qbe_load64(base + CAPTURE_STDERR))
    call mark_range(stack, thread_word(TLS_STACK_TOP))
    call mark_range(__lsl_qbe_load64(base + GLOBAL_ROOT_BEGIN), __lsl_qbe_load64(base + GLOBAL_ROOT_END))
    table = __lsl_qbe_load64(base + INTERN_TABLE)
    index = 0
    while index <= __lsl_qbe_load64(base + INTERN_MASK):
        literal = __lsl_qbe_load64(table + __lsl_qbe_shl(index, 4) + 8)
        if literal != 0:
            call rt_runtime_mark(literal)
        end
        index += 1
    end
    call sync.rt_runtime_table_unlock()
    # Trasování až po zastavení všech vláken: délky ani zálohy se nemění.
    while True:
        object = __lsl_qbe_load64(base + GC_WORKLIST)
        if object == 0:
            break
        end
        following = __lsl_qbe_load64(object - 8)
        if following == 1:
            following = 0
        end
        __lsl_qbe_store64(base + GC_WORKLIST, following)
        __lsl_qbe_store64(object - 8, 1)
        call rt_runtime_trace(object)
    end
    live = __lsl_qbe_alloc(8)
    freed = sweep(live)
    # Rozpočet 3× živé haldy, aspoň 4 MiB; odložený sweep ho nemění.
    if __lsl_qbe_load64(base + GC_INCOMPLETE) == 0:
        budget = __lsl_qbe_load64(live) * 3
        if budget < GC_BUDGET_FLOOR:
            budget = GC_BUDGET_FLOOR
        end
        __lsl_qbe_store64(base + GC_BUDGET, budget)
    end
    __lsl_qbe_store64(base + GC_ALLOCATED_BYTES, 0)
    __lsl_qbe_store64(base + GC_WORKLIST, 0)
    # Probudit uspaná vlákna až po sweepu.
    __lsl_qbe_store64(base + GC_GATE, 0)
    call os.futex_wake(base + GC_GATE, 2147483647)
    call resume_workers()
    # Počkat, až všechna uspaná vlákna opustí bránu (stav 2 -> 1). Jinak by
    # další gc() viděl stav 2 z tohoto cyklu a pokládal by běžící vlákno za
    # zastavené.
    call wait_resumed()
    call sync.rt_runtime_mutex_unlock()
    # Stejný výsledek jako dosud: nejnižší bajt nahrazený příznakem freed != 0.
    return (freed & -256) | (freed != 0)
end

function rt_runtime_maybe_gc():
    base = core.state()
    if __lsl_qbe_load64(base + GC_ALLOCATED_BYTES) < __lsl_qbe_load64(base + GC_BUDGET):
        return 0
    end
    return cold_collect()
end

function cold_collect():
    base = core.state()
    if thread_word(TLS_STACK_TOP) != __lsl_qbe_load64(base + MAIN_THREAD_BLOCK + TLS_STACK_TOP):
        return 0
    end
    if __lsl_qbe_load64(base + GC_ALLOCATED_BYTES) < __lsl_qbe_load64(base + GC_BUDGET):
        return 0
    end
    call rt_runtime_gc()
    return 0
end
