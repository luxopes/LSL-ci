# lsl: runtime
# Vlákna: tabulka vláken (stav +112, 127 položek po 64 B od +8), spawn
# (vrstva OS: clone se sdílenou pamětí, CreateThread), join a vstup vlákna. Položka: +0 tid jádra
# (horní bit = už připojené), +8 vrchol zásobníku, +16 stav (0 volno/skončilo,
# 1 běží, 2 uspané GC, 3 rezervované spawnem, 4 signál odeslán), +24 uložený
# rsp uspaného vlákna (před startem vlákna jeho funkce), +32.. blok vlákna (thread pointer): +32 čekající chyba,
# +40 příznak chyby, +48 vrchol zásobníku, +56 ukazatel na stav runtime.
load core
load _runtime_os as os
load sync
load gc

THREAD_TABLE = 112
THREADS_STARTED = 136
GC_ALLOCATED_BYTES = 144
GC_BUDGET = 152
GC_GATE = 128
THREAD_SLOTS = 127
STACK_BYTES = 8392704
GUARD_BYTES = 4096
REAPED = -9223372036854775808
TAG_FUNCTION = 10

function entry_at(index):
    return __lsl_qbe_load64(core.state() + THREAD_TABLE) + __lsl_qbe_shl(index, 6) + 8
end

# Položka s tímto tid (bez bitu připojení), nebo 0.
function find_entry(tid):
    if tid == 0:
        return 0
    end
    index = 0
    while index < THREAD_SLOTS:
        entry = entry_at(index)
        if __lsl_qbe_load64(entry) & 9223372036854775807 == tid:
            return entry
        end
        index += 1
    end
    return 0
end

# Volná položka: nejdřív nikdy nepoužitá nebo už připojená, jinak jakákoli
# skončená (join na zapomenutý tid pak vrátí 126 jako dosud).
function free_entry():
    index = 0
    while index < THREAD_SLOTS:
        entry = entry_at(index)
        if __lsl_qbe_load64(entry + 16) == 0:
            tid = __lsl_qbe_load64(entry)
            if tid == 0 or tid & REAPED != 0:
                return entry
            end
        end
        index += 1
    end
    index = 0
    while index < THREAD_SLOTS:
        entry = entry_at(index)
        if __lsl_qbe_load64(entry + 16) == 0:
            return entry
        end
        index += 1
    end
    return 0
end

# thread_spawn(funkce) -> tid, nebo -1 (neplatná funkce, plná tabulka,
# chybějící paměť pro zásobník, selhání clone).
function rt_runtime_thread_spawn(function):
    call __lsl_qbe_call0(__lsl_symbol("rt_runtime_stdio_direct"))
    # Jen živá Function: surové číslo jako adresa kódu by ukončilo celý proces.
    if not core.rt_runtime_is_heap_object(function) or __lsl_qbe_load64(function) != TAG_FUNCTION or __lsl_qbe_load64(function + 8) == 0:
        return -1
    end
    base = core.state()
    # Zamykání haldy musí platit dřív, než druhé vlákno existuje.
    __lsl_qbe_store64(base + THREADS_STARTED, 1)
    call sync.rt_runtime_table_lock()
    entry = free_entry()
    if entry == 0:
        call sync.rt_runtime_table_unlock()
        return -1
    end
    # Rezervace (stav 3 se nesignalizuje ani neprohledává); zásobník
    # předchozího vlákna se použije znovu, jádro stav vynuluje až po jeho konci.
    __lsl_qbe_store64(entry + 16, 3)
    __lsl_qbe_store64(entry, 0)
    top = __lsl_qbe_load64(entry + 8)
    call sync.rt_runtime_table_unlock()
    # Zásobník vytvoří vrstva OS (Linux: vlastní mapování se strážní
    # stránkou, znovu použité; Windows: systém s vláknem, vrchol 0).
    top = os.thread_stack(top, STACK_BYTES, GUARD_BYTES)
    if top < 0:
        return cold_spawn_failed(entry)
    end
    # Vrchol zásobníku a stav zveřejnit pod zámkem tabulky: gc() nesmí
    # vidět běžící vlákno s neplatným rozsahem zásobníku. Vlákno, jehož
    # zásobník zná až ono samo (os.THREAD_SELF_PUBLISH), zůstane ve stavu 3
    # a zveřejní se v lsl_thread_begin; funkci do té doby drží +24 (GC ji
    # ve stavu 3 označí).
    call sync.rt_runtime_table_lock()
    __lsl_qbe_store64(entry + 8, top)
    if not os.THREAD_SELF_PUBLISH:
        __lsl_qbe_store64(entry + 16, 1)
    end
    __lsl_qbe_store64(entry + 24, function)
    __lsl_qbe_store64(entry + 32, 0)
    __lsl_qbe_store64(entry + 40, 0)
    __lsl_qbe_store64(entry + 48, top)
    __lsl_qbe_store64(entry + 56, base)
    tid = os.thread_start(entry, top, function)
    if tid < 0:
        # Zásobník zůstává pro dalšího obyvatele položky.
        __lsl_qbe_store64(entry + 16, 0)
        call sync.rt_runtime_table_unlock()
        return -1
    end
    __lsl_qbe_store64(entry, tid)
    call sync.rt_runtime_table_unlock()
    # Systém bez vláken (WASI) spustí vlákno teď, mimo zámek tabulky.
    call os.thread_run_pending(entry)
    return tid
end

function cold_spawn_failed(entry):
    call sync.rt_runtime_table_lock()
    __lsl_qbe_store64(entry + 16, 0)
    call sync.rt_runtime_table_unlock()
    return -1
end

# Vstup vlákna, jehož zásobník vytvořil systém (Windows, z arch vrstvy):
# zveřejní vrchol zásobníku a blok vlákna. Během GC (brána +128) čeká:
# nové vlákno nesmí měnit objekty, když GC trasuje nebo uklízí.
function lsl_thread_begin(entry, top):
    base = __lsl_qbe_load64(entry + 56)
    call sync.rt_runtime_table_lock()
    while __lsl_qbe_load64(base + GC_GATE) == 1:
        call sync.rt_runtime_table_unlock()
        call os.futex_wait(base + GC_GATE, 1)
        call sync.rt_runtime_table_lock()
    end
    callee = __lsl_qbe_load64(entry + 24)
    __lsl_qbe_store64(entry + 8, top)
    __lsl_qbe_store64(entry + 48, top)
    call __lsl_qbe_call1(__lsl_symbol("lsl_arch_set_thread_pointer"), entry + 32)
    __lsl_qbe_store64(entry + 16, 1)
    call sync.rt_runtime_table_unlock()
    return lsl_thread_main(entry, callee)
end

# Vstup nového vlákna; končí jen os.thread_exit.
function lsl_thread_main(entry, function):
    code = core.rt_runtime_unbox_dynamic_function(function)
    call __lsl_qbe_call0(code)
    # Nezachycená chyba workeru se vypíše, jinak by vlákno zaniklo tiše.
    if __lsl_qbe_load64(entry + 40) != 0:
        message = __lsl_qbe_load64(entry + 32)
        prefix = "LSL worker error: "
        call os.write(2, prefix + 16, __lsl_qbe_load64(prefix + 8))
        call os.write(2, message + 16, __lsl_qbe_load64(message + 8))
        newline = "\n"
        call os.write(2, newline + 16, 1)
    end
    call os.thread_exit(entry)
    return 0
end

# thread_join(tid) -> 0 po skončení vlákna, 126 bez položky s tímto tid.
function rt_runtime_thread_join(tid):
    call sync.rt_runtime_table_lock()
    entry = find_entry(tid)
    call sync.rt_runtime_table_unlock()
    if entry == 0:
        return 126
    end
    base = core.state()
    # Ohraničené čekání: hlavní vlákno mezitím obslouží tlak na alokace.
    timeout = __lsl_qbe_alloc(16)
    while True:
        if __lsl_qbe_load64(base + GC_ALLOCATED_BYTES) >= __lsl_qbe_load64(base + GC_BUDGET):
            call gc.rt_runtime_maybe_gc()
        end
        status = __lsl_qbe_load64(entry + 16)
        if status == 0:
            break
        end
        __lsl_qbe_store64(timeout, 0)
        __lsl_qbe_store64(timeout + 8, 10000000)
        call os.futex_wait_timeout(entry + 16, status, timeout)
    end
    call sync.rt_runtime_table_lock()
    entry = find_entry(tid)
    if entry != 0:
        __lsl_qbe_store64(entry, __lsl_qbe_load64(entry) | REAPED)
    end
    call sync.rt_runtime_table_unlock()
    return 0
end

# Počet CPU v masce afinity, 1 při chybě.
function rt_runtime_cpu_count():
    mask = __lsl_qbe_alloc(128)
    size = os.sched_getaffinity(128, mask)
    if size <= 0:
        return 1
    end
    count = 0
    index = 0
    while index < size:
        bits = __lsl_qbe_load8(mask + index)
        while bits != 0:
            count += bits & 1
            bits = __lsl_qbe_lshr(bits, 1)
        end
        index += 1
    end
    if count <= 0:
        return 1
    end
    return count
end

function rt_runtime_atomic_add(address, delta):
    return sync.atomic_add(address, delta)
end

function rt_runtime_atomic_xchg(address, value):
    return sync.atomic_xchg(address, value)
end

function rt_runtime_atomic_cas(address, expected, value):
    return sync.atomic_cas(address, expected, value)
end

function rt_runtime_atomic_pause():
    call __lsl_qbe_call0(__lsl_symbol("lsl_arch_pause"))
    return 0
end
