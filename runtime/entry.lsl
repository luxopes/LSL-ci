# lsl: runtime
# Start programu, chybový stav vlákna a obsluha signálu GC.
# Stav runtime leží na začátku haldy (brk): 1344 B stavu, za ním tabulka
# internovaných řetězců (1 MiB, 65536 párů). Blok hlavního vlákna je na
# stav+160 (+0 čekající chyba, +8 příznak chyby, +16 vrchol zásobníku).
load core
load os_linux
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
    call os_linux.write(2, message + 16, __lsl_qbe_load64(message + 8))
    call os_linux.exit_process(71)
    return 0
end

# Volá _start s ukazatelem na argc (vrchol zásobníku hlavního vlákna).
function lsl_runtime_start(stack):
    base = os_linux.brk(0)
    if os_linux.brk(base + STATE_BYTES + INTERN_BYTES) != base + STATE_BYTES + INTERN_BYTES:
        call heap.fatal_allocation()
    end
    __lsl_qbe_store64(__lsl_symbol("lsl_state"), base)
    registry = os_linux.map_anonymous(REGISTRY_BYTES, 0)
    if registry < 0:
        call heap.fatal_allocation()
    end
    __lsl_qbe_store64(base + 32, registry)
    __lsl_qbe_store64(base + 40, REGISTRY_MASK)
    __lsl_qbe_store64(base + 48, base + STATE_BYTES)
    __lsl_qbe_store64(base + 56, INTERN_MASK)
    # Bitmapa začátků objektů: 1 bit na 8 B od začátku stavu, MAP_NORESERVE.
    bitmap = os_linux.map_anonymous(BITMAP_INITIAL, platform.MAP_NORESERVE)
    if bitmap < 0:
        call heap.fatal_allocation()
    end
    __lsl_qbe_store64(base + OBJECT_BITMAP, bitmap)
    __lsl_qbe_store64(base + OBJECT_BITMAP_CAPACITY, BITMAP_INITIAL)
    # Identita hlavního vlákna pro gc() a seed hashe: vrchol zásobníku.
    __lsl_qbe_store64(base + MAIN_STACK_TOP, stack)
    __lsl_qbe_store64(base + GC_BUDGET, 4194304)
    if __lsl_qbe_call1(__lsl_symbol("lsl_arch_set_thread_pointer"), base + MAIN_THREAD_BLOCK) < 0:
        call cold_fatal_setup()
    end
    call __lsl_qbe_call2(__lsl_symbol("lsl_arch_tls_store"), TLS_STACK_TOP, stack)
    table = os_linux.map_anonymous(8192, 0)
    if table < 0:
        call heap.fatal_allocation()
    end
    __lsl_qbe_store64(base + THREAD_TABLE, table)
    # Obsluha SIGUSR1 pro zastavení světa; SA_RESTART: vnitřní GC nesmí
    # vracet EINTR z I/O ani čekání na procesy.
    action = __lsl_qbe_alloc(32)
    __lsl_qbe_store64(action + platform.SIGACTION_HANDLER, __lsl_symbol("lsl_thread_signal"))
    __lsl_qbe_store64(action + platform.SIGACTION_FLAGS, platform.SA_RESTORER | platform.SA_RESTART)
    # Bez pole restorer (riscv64) jádro vrací ze signálu přes vDSO.
    if platform.SIGACTION_RESTORER >= 0:
        __lsl_qbe_store64(action + platform.SIGACTION_RESTORER, __lsl_symbol("lsl_arch_signal_restorer"))
    end
    __lsl_qbe_store64(action + platform.SIGACTION_MASK, 0)
    if os_linux.syscall6(platform.SYS_RT_SIGACTION, SIGUSR1, action, 0, platform.SIGSET_BYTES, 0, 0) < 0:
        call cold_fatal_setup()
    end
    call __lsl_qbe_call2(__lsl_symbol("rt_runtime_set_global_roots"), base + STATE_BYTES, base + STATE_BYTES)
    status = __lsl_qbe_call0(__lsl_symbol("lsl_entry"))
    return qbe_exit(status)
end

function qbe_exit(status):
    call __lsl_qbe_call0(__lsl_symbol("rt_runtime_stdout_flush"))
    call os_linux.exit_process(status)
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
    entry = threads.find_entry(os_linux.gettid())
    if entry == 0:
        return 0
    end
    registers = __lsl_qbe_alloc(96)
    __lsl_qbe_store64(entry + 24, __lsl_qbe_call1(__lsl_symbol("lsl_arch_spill"), registers))
    __lsl_qbe_store64(entry + 16, 2)
    gate = core.state() + GC_GATE
    while __lsl_qbe_load64(gate) == 1:
        call os_linux.futex_wait(gate, 1)
    end
    __lsl_qbe_store64(entry + 16, 1)
    return 0
end
