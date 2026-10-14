# lsl: runtime
# Zámky runtime nad slovy ve stavu: 0 volný, 1 zamčený, 2 zamčený s čekajícími.
# Nezatížený lock/unlock je jedna atomická operace bez systémového volání.
# Zámek haldy (stav +96) nic nedělá, dokud první thread_spawn nenastaví
# příznak +136: program bez vláken platí jen jedno čtení.
load core
load _runtime_os as os

NATIVE_MUTEX = 88
HEAP_MUTEX = 96
TABLE_MUTEX = 104
THREADS_STARTED = 136

function atomic_cas(address, expected, value):
    return __lsl_qbe_call3(__lsl_symbol("lsl_arch_cas64"), address, expected, value)
end

function atomic_xchg(address, value):
    return __lsl_qbe_call2(__lsl_symbol("lsl_arch_xchg64"), address, value)
end

function atomic_add(address, delta):
    return __lsl_qbe_call2(__lsl_symbol("lsl_arch_add64"), address, delta)
end

# Rychlá cesta bez smyčky se vkládá do volajícího (jedno atomické volání);
# spor řeší lock_contended.
function lock(word):
    if atomic_cas(word, 0, 1) != 0:
        call lock_contended(word)
    end
    return 0
end

function lock_contended(word):
    # Slovo označí za sporné; byl-li zámek mezitím volný, patří nám.
    while atomic_xchg(word, 2) != 0:
        call os.futex_wait(word, 2)
    end
    return 0
end

function unlock(word):
    if atomic_xchg(word, 0) == 2:
        call os.futex_wake(word, 1)
    end
    return 0
end

function rt_runtime_mutex_lock():
    base = core.state()
    if __lsl_qbe_load64(base + THREADS_STARTED) == 0:
        return 0
    end
    return lock(base + HEAP_MUTEX)
end

function rt_runtime_mutex_unlock():
    base = core.state()
    if __lsl_qbe_load64(base + THREADS_STARTED) == 0:
        return 0
    end
    return unlock(base + HEAP_MUTEX)
end

function rt_runtime_native_lock():
    return lock(core.state() + NATIVE_MUTEX)
end

function rt_runtime_native_unlock():
    return unlock(core.state() + NATIVE_MUTEX)
end

function rt_runtime_table_lock():
    return lock(core.state() + TABLE_MUTEX)
end

function rt_runtime_table_unlock():
    return unlock(core.state() + TABLE_MUTEX)
end
