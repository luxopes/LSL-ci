# lsl: runtime
# Start programu, chybový stav vlákna a obsluha signálu GC.
# Stav runtime leží na začátku haldy (souvislá oblast, heap.lsl): 1344 B
# stavu, za ním bloky. Tabulka internovaných řetězců
# (1 MiB, 65536 párů) je samostatné mapování. Blok hlavního vlákna je na
# stav+160 (+0 čekající chyba, +8 příznak chyby, +16 vrchol zásobníku).
load core
load _runtime_os as os
load heap
load threads
load _platform as platform

STATE_BYTES = 1344
INTERN_BYTES = 1048576
INTERN_MASK = 65535
REGISTRY_BYTES = 524288
REGISTRY_MASK = 65535
OBJECT_BITMAP = 1328
OBJECT_BITMAP_CAPACITY = 1336
BITMAP_INITIAL = 4194304
# Začátek haldy: 1 GiB za koncem obrazu programu (tam, kde by byl brk),
# daleko od mapování jádra, která rostou shora dolů; obsazené místo ->
# o 1 GiB dál, nejvýš 64 pokusů.
HEAP_GAP = 1073741824
HEAP_ATTEMPTS = 64
THREAD_TABLE = 112
MAIN_STACK_TOP = 120
GC_GATE = 128
GC_BUDGET = 152
MAIN_THREAD_BLOCK = 160
TLS_ERROR = 0
TLS_STACK_TOP = 16
SIGUSR1 = 10

function cold_fatal_setup():
    message = "LSL runtime error: OSError: required process protection is unavailable\n"
    call os.write(2, message + 16, __lsl_qbe_load64(message + 8))
    call os.exit_process(71)
    return 0
end

# Volá _start s vrcholem zásobníku hlavního vlákna (Linux: ukazatel na argc).
function lsl_runtime_start(stack):
    base = os.heap_base((__lsl_symbol("lsl_state") + HEAP_GAP) & -heap.COMMIT_GRAIN)
    attempt = 0
    while os.map_at(base, heap.COMMIT_GRAIN) == 0:
        attempt += 1
        if attempt >= HEAP_ATTEMPTS:
            call heap.fatal_allocation()
        end
        base += HEAP_GAP
    end
    __lsl_qbe_store64(__lsl_symbol("lsl_state"), base)
    __lsl_qbe_store64(base + heap.HEAP_RESERVED, base + heap.COMMIT_GRAIN)
    __lsl_qbe_store64(base + heap.HEAP_BUMP, base + STATE_BYTES)
    intern = os.map_anonymous(INTERN_BYTES, 0)
    if intern < 0:
        call heap.fatal_allocation()
    end
    registry = os.map_anonymous(REGISTRY_BYTES, 0)
    if registry < 0:
        call heap.fatal_allocation()
    end
    __lsl_qbe_store64(base + 32, registry)
    __lsl_qbe_store64(base + 40, REGISTRY_MASK)
    __lsl_qbe_store64(base + 48, intern)
    __lsl_qbe_store64(base + 56, INTERN_MASK)
    # Bitmapa začátků objektů: 1 bit na 8 B od začátku stavu, MAP_NORESERVE.
    bitmap = os.map_anonymous(BITMAP_INITIAL, platform.MAP_NORESERVE)
    if bitmap < 0:
        call heap.fatal_allocation()
    end
    __lsl_qbe_store64(base + OBJECT_BITMAP, bitmap)
    __lsl_qbe_store64(base + OBJECT_BITMAP_CAPACITY, BITMAP_INITIAL)
    # Blok argumentů procesu (argc, argv, 0, prostředí, 0) a seed hashe. Na
    # Linuxu ho jádro předalo na zásobníku (= vrchol zásobníku), jinde ho
    # vrstva OS sestaví. Hlavní vlákno pozná gc() podle bloku vlákna +16.
    arguments = os.process_arguments(stack)
    if arguments == 0:
        call heap.fatal_allocation()
    end
    __lsl_qbe_store64(base + MAIN_STACK_TOP, arguments)
    __lsl_qbe_store64(base + GC_BUDGET, 4194304)
    if __lsl_qbe_call1(__lsl_symbol("lsl_arch_set_thread_pointer"), base + MAIN_THREAD_BLOCK) < 0:
        call cold_fatal_setup()
    end
    call __lsl_qbe_call2(__lsl_symbol("lsl_arch_tls_store"), TLS_STACK_TOP, stack)
    table = os.map_anonymous(8192, 0)
    if table < 0:
        call heap.fatal_allocation()
    end
    __lsl_qbe_store64(base + THREAD_TABLE, table)
    # Zastavení světa pro GC (Linux: obsluha SIGUSR1 lsl_thread_signal).
    if os.install_thread_suspend() < 0:
        call cold_fatal_setup()
    end
    call __lsl_qbe_call2(__lsl_symbol("rt_runtime_set_global_roots"), base + STATE_BYTES, base + STATE_BYTES)
    status = __lsl_qbe_call0(__lsl_symbol("lsl_entry"))
    return qbe_exit(status)
end

function qbe_exit(status):
    call __lsl_qbe_call0(__lsl_symbol("rt_runtime_stdout_flush"))
    call os.exit_process(status)
    return 0
end

# Čekající chyba vlákna. Statický záznam String (chyby runtime) se při
# prvním čtení zkopíruje na haldu, aby last_error měl stálou identitu.
function qbe_error_pending():
    error = __lsl_qbe_call1(__lsl_symbol("lsl_arch_tls_load"), TLS_ERROR)
    if error == 0 or core.rt_runtime_is_heap_object(error):
        return error
    end
    copy = __lsl_qbe_call1(__lsl_symbol("rt_runtime_string_clone"), error)
    call __lsl_qbe_call2(__lsl_symbol("lsl_arch_tls_store"), TLS_ERROR, copy)
    return copy
end

# SIGUSR1 v pracovním vlákně: uspat se na bráně GC. Jádro uložilo registry
# do rámce signálu na zásobníku vlákna; GC prohledá zásobník od rámce této
# obsluhy k základně, takže vidí i je. rt_sigreturn je pak obnoví.
function lsl_thread_signal(signal):
    entry = threads.find_entry(os.gettid())
    if entry == 0:
        return 0
    end
    registers = __lsl_qbe_alloc(96)
    __lsl_qbe_store64(entry + 24, __lsl_qbe_call1(__lsl_symbol("lsl_arch_spill"), registers))
    __lsl_qbe_store64(entry + 16, 2)
    gate = core.state() + GC_GATE
    while __lsl_qbe_load64(gate) == 1:
        call os.futex_wait(gate, 1)
    end
    __lsl_qbe_store64(entry + 16, 1)
    return 0
end
