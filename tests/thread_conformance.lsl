# Shared-memory threads: clone-based spawn, futex join, lock-free IntArray
# counter, and a cross-thread conservative gc() while workers hold heap
# objects on their stacks.

counter = IntArray()
counter.append(0)

function bump():
    i = 0
    while i < 50000:
        call atomic_add(counter, 0, 1)
        i += 1
    end
    return None
end

function allocate_worker():
    local = []
    i = 0
    while i < 20000:
        local.append(String(i))
        i += 1
    end
    call atomic_add(counter, 0, 1)
    return None
end

t1 = thread_spawn(bump)
t2 = thread_spawn(bump)
t3 = thread_spawn(bump)
t4 = thread_spawn(bump)
print thread_join(t1), thread_join(t2), thread_join(t3), thread_join(t4)
print counter[0]

# Workers allocate heap objects while the main thread collects; the 8 MiB
# thread-stack scans must keep their live Lists alive.
t5 = thread_spawn(allocate_worker)
t6 = thread_spawn(allocate_worker)
call gc()
print thread_join(t5), thread_join(t6)
print counter[0]
