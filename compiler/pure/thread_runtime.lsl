# Shared-memory thread runtime: futex mutexes, clone-based spawn, thread table,
# stop-the-world gc() support and join. Pure syscalls only.
#
# State block (RBX) words used by threads:
#   +96  heap mutex word (runtime_alloc / gc() serialization)
#  +104  thread-table mutex word
#  +112  thread table pointer (one anonymous 4096-byte mmap page)
#  +120  main thread stack top (gc() identity check against r15)
#  +128  gc gate word: 1 while the main thread collects, 0 otherwise
#  +136  threads-started flag: set by the first thread_spawn, never cleared
#
# Thread table: [+0 reserved], then 32-byte entries:
#   [+0 kernel tid, +8 stack base (top of the 8 MiB mapping),
#    +16 status, +24 saved rsp of a suspended worker]
# status: 0 = free/exited (cleared by the kernel via CLONE_CHILD_CLEARTID),
# 1 = running, 2 = suspended in the gc handler, 3 = slot reserved by a spawn
# in progress, 4 = signalled by gc() but not yet suspended.
# A worker's stack base is published before its status becomes 1, so gc()
# never sees a live entry with an invalid stack range.
#
# Mutex protocol (0 free, 1 locked, 2 locked with waiters): uncontended
# lock/unlock are single lock-prefixed instructions without syscalls, so
# threaded programs pay two atomic ops per allocation and single-threaded
# programs only a flag load (see the guarded heap mutex below).

load assembler
load x86_64

function emit_mutex_pair(output, lock_label, wait_label, unlock_label, offset, guarded):
    # Clobbers only caller-saved registers; RBX must point at the state block.
    # A guarded mutex is a no-op until the first thread_spawn sets state+136,
    # so single-threaded programs pay nothing on the allocation path.
    call assembler.label(output, lock_label)
    if guarded:
        call assembler.emit(output, x86_64.load_memory(0, 3, 136))
        call assembler.emit(output, x86_64.test_reg_reg(0, 0))
        call assembler.relative(output, [15, 132], "thread_ret")
    end
    call assembler.emit(output, x86_64.xor_reg_reg(0, 0))
    call assembler.emit(output, x86_64.mov_imm64(1, 1))
    call assembler.emit(output, x86_64.lock_cmpxchg_memory(3, offset, 1))
    call assembler.relative(output, [15, 133], wait_label)
    call assembler.emit(output, x86_64.ret())
    call assembler.label(output, wait_label)
    # Mark the word contended; if it was free we now own it.
    call assembler.emit(output, x86_64.mov_imm64(0, 2))
    call assembler.emit(output, x86_64.lock_xchg_memory(3, offset, 0))
    call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
    call assembler.relative(output, [15, 132], "thread_ret")
    # futex_wait(&word, 2); spurious wakeups and EINTR retry the xchg.
    call assembler.emit(output, x86_64.lea_base(7, 3, offset))
    call assembler.emit(output, x86_64.xor_reg_reg(6, 6))
    call assembler.emit(output, x86_64.mov_imm64(2, 2))
    call assembler.emit(output, x86_64.mov_imm64(0, 202))
    call assembler.emit(output, x86_64.xor_reg_reg(10, 10))
    call assembler.emit(output, x86_64.xor_reg_reg(8, 8))
    call assembler.emit(output, x86_64.syscall())
    call assembler.relative(output, [233], wait_label)
    call assembler.label(output, unlock_label)
    if guarded:
        call assembler.emit(output, x86_64.load_memory(0, 3, 136))
        call assembler.emit(output, x86_64.test_reg_reg(0, 0))
        call assembler.relative(output, [15, 132], "thread_ret")
    end
    call assembler.emit(output, x86_64.xor_reg_reg(0, 0))
    call assembler.emit(output, x86_64.lock_xchg_memory(3, offset, 0))
    call assembler.emit(output, x86_64.cmp_reg_imm8(0, 2))
    call assembler.relative(output, [15, 133], "thread_ret")
    # futex_wake(&word, 1)
    call assembler.emit(output, x86_64.lea_base(7, 3, offset))
    call assembler.emit(output, x86_64.mov_imm64(6, 1))
    call assembler.emit(output, x86_64.mov_imm64(2, 1))
    call assembler.emit(output, x86_64.mov_imm64(0, 202))
    call assembler.emit(output, x86_64.xor_reg_reg(10, 10))
    call assembler.emit(output, x86_64.xor_reg_reg(8, 8))
    call assembler.emit(output, x86_64.syscall())
    call assembler.emit(output, x86_64.ret())
end

function emit_mutex(output):
    call assembler.label(output, "thread_ret")
    call assembler.emit(output, x86_64.ret())
    call emit_mutex_pair(output, "runtime_mutex_lock", "mutex_wait", "runtime_mutex_unlock", 96, True)
    call emit_mutex_pair(output, "runtime_table_lock", "table_wait", "runtime_table_unlock", 104, False)
end

function emit_entry_lookup(output, found_label, missing_label):
    # rax = kernel tid -> r9 = entry with that tid, else jump to missing_label.
    call assembler.emit(output, x86_64.load_memory(8, 3, 112))
    call assembler.emit(output, x86_64.xor_reg_reg(1, 1))
    call assembler.label(output, found_label + "_scan")
    call assembler.emit(output, x86_64.cmp_reg_imm32(1, 127))
    call assembler.relative(output, [15, 141], missing_label)
    call assembler.emit(output, x86_64.move_reg_reg(10, 1))
    call assembler.emit(output, x86_64.shift_left_imm(10, 5))
    call assembler.emit(output, x86_64.lea_indexed(9, 8, 10, 0))
    call assembler.emit(output, x86_64.add_reg_imm8(9, 8))
    call assembler.emit(output, x86_64.load_memory(2, 9, 0))
    call assembler.emit(output, x86_64.cmp_reg_reg(2, 0))
    call assembler.relative(output, [15, 132], found_label)
    call assembler.emit(output, x86_64.increment(1))
    call assembler.relative(output, [233], found_label + "_scan")
    call assembler.label(output, found_label)
end

function emit_spawn(output):
    # runtime_thread_spawn: rdi = tagged Function -> kernel tid in rax, or
    # -1 when the table is full or the stack mapping failed. The table lock
    # is held across clone so the kernel tid is published before anyone can
    # observe the entry; the child takes no lock before the parent releases.
    call assembler.label(output, "runtime_thread_spawn")
    call assembler.emit(output, x86_64.function_prologue(64))
    call assembler.emit(output, x86_64.store_stack(-8, 7))
    # Enable heap locking before a second thread can exist.
    call assembler.emit(output, x86_64.store_memory_imm32(3, 136, 1))
    call assembler.relative(output, [232], "runtime_table_lock")
    call assembler.emit(output, x86_64.load_memory(8, 3, 112))
    call assembler.emit(output, x86_64.xor_reg_reg(1, 1))
    call assembler.label(output, "spawn_find_slot")
    call assembler.emit(output, x86_64.cmp_reg_imm32(1, 127))
    call assembler.relative(output, [15, 141], "spawn_no_slot")
    call assembler.emit(output, x86_64.move_reg_reg(10, 1))
    call assembler.emit(output, x86_64.shift_left_imm(10, 5))
    call assembler.emit(output, x86_64.lea_indexed(9, 8, 10, 0))
    call assembler.emit(output, x86_64.add_reg_imm8(9, 8))
    call assembler.emit(output, x86_64.load_memory(2, 9, 16))
    call assembler.emit(output, x86_64.cmp_reg_imm8(2, 0))
    call assembler.relative(output, [15, 132], "spawn_slot_ready")
    call assembler.emit(output, x86_64.increment(1))
    call assembler.relative(output, [233], "spawn_find_slot")
    call assembler.label(output, "spawn_slot_ready")
    # r9 = entry. Claim it (status 3 = reserved: never signalled or scanned)
    # and reuse the previous occupant's stack when the slot has one; the
    # kernel cleared its status only after that thread fully exited.
    call assembler.emit(output, x86_64.store_memory_imm32(9, 16, 3))
    call assembler.emit(output, x86_64.store_memory_imm32(9, 0, 0))
    call assembler.emit(output, x86_64.store_stack(-16, 9))
    call assembler.emit(output, x86_64.load_memory(10, 9, 8))
    call assembler.emit(output, x86_64.store_stack(-24, 10))
    call assembler.relative(output, [232], "runtime_table_unlock")
    call assembler.emit(output, x86_64.load_stack(10, -24))
    call assembler.emit(output, x86_64.cmp_reg_imm8(10, 0))
    call assembler.relative(output, [15, 133], "spawn_stack_ready")
    # mmap a fresh 8 MiB stack (MAP_PRIVATE|MAP_ANONYMOUS|MAP_STACK).
    call assembler.emit(output, x86_64.mov_imm64(0, 9))
    call assembler.emit(output, x86_64.xor_reg_reg(7, 7))
    call assembler.emit(output, x86_64.mov_imm64(6, 8388608))
    call assembler.emit(output, x86_64.mov_imm64(2, 3))
    call assembler.emit(output, x86_64.mov_imm64(10, 131106))
    call assembler.emit(output, x86_64.mov_imm64(8, -1))
    call assembler.emit(output, x86_64.xor_reg_reg(9, 9))
    call assembler.emit(output, x86_64.syscall())
    call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
    call assembler.relative(output, [15, 140], "spawn_stack_failed")
    call assembler.emit(output, x86_64.add_reg_imm32(0, 8388608))
    call assembler.emit(output, x86_64.store_stack(-24, 0))
    call assembler.label(output, "spawn_stack_ready")
    # The child finds its entry and Function at the top of its stack.
    call assembler.emit(output, x86_64.load_stack(10, -24))
    call assembler.emit(output, x86_64.load_stack(9, -16))
    call assembler.emit(output, x86_64.store_memory(10, -16, 9))
    call assembler.emit(output, x86_64.load_stack(7, -8))
    call assembler.emit(output, x86_64.store_memory(10, -8, 7))
    # Publish stack_base and status under the table mutex so a concurrent
    # gc() never observes status=1 with an invalid stack range.
    call assembler.relative(output, [232], "runtime_table_lock")
    call assembler.emit(output, x86_64.load_stack(9, -16))
    call assembler.emit(output, x86_64.load_stack(10, -24))
    call assembler.emit(output, x86_64.store_memory(9, 8, 10))
    call assembler.emit(output, x86_64.store_memory_imm32(9, 16, 1))
    # clone(flags, child_stack = top - 16, parent_tid = 0,
    #       child_tid = &entry.status, tls = 0) with CLONE_VM|CLONE_FS|
    # CLONE_FILES|CLONE_SIGHAND|CLONE_THREAD|CLONE_SYSVSEM|
    # CLONE_CHILD_CLEARTID: the kernel zeroes the status word and wakes its
    # futex only once the thread has fully exited, so joiners and stack
    # reuse never race with a thread still running on that stack.
    call assembler.emit(output, x86_64.lea_base(6, 10, -16))
    call assembler.emit(output, x86_64.lea_base(10, 9, 16))
    call assembler.emit(output, x86_64.mov_imm64(0, 56))
    call assembler.emit(output, x86_64.mov_imm64(7, 2428672))
    call assembler.emit(output, x86_64.xor_reg_reg(2, 2))
    call assembler.emit(output, x86_64.xor_reg_reg(8, 8))
    call assembler.emit(output, x86_64.syscall())
    call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
    call assembler.relative(output, [15, 132], "runtime_thread_entry")
    call assembler.relative(output, [15, 140], "spawn_clone_failed")
    # Parent: publish the kernel tid and return it.
    call assembler.emit(output, x86_64.store_memory(9, 0, 0))
    call assembler.emit(output, x86_64.store_stack(-40, 0))
    call assembler.relative(output, [232], "runtime_table_unlock")
    call assembler.emit(output, x86_64.load_stack(0, -40))
    call assembler.emit(output, x86_64.function_epilogue())
    call assembler.label(output, "spawn_clone_failed")
    # Free the slot again; the stack mapping stays for the next occupant.
    call assembler.emit(output, x86_64.store_memory_imm32(9, 16, 0))
    call assembler.relative(output, [232], "runtime_table_unlock")
    call assembler.emit(output, x86_64.mov_imm64(0, -1))
    call assembler.emit(output, x86_64.function_epilogue())
    call assembler.label(output, "spawn_stack_failed")
    call assembler.relative(output, [232], "runtime_table_lock")
    call assembler.emit(output, x86_64.load_stack(9, -16))
    call assembler.emit(output, x86_64.store_memory_imm32(9, 16, 0))
    call assembler.label(output, "spawn_no_slot")
    call assembler.relative(output, [232], "runtime_table_unlock")
    call assembler.emit(output, x86_64.mov_imm64(0, -1))
    call assembler.emit(output, x86_64.function_epilogue())
end

function emit_entry(output):
    # Child start: rsp = stack top - 16 with [rsp] = entry, [rsp+8] = tagged
    # Function. rbx, r12 and r13 are inherited from the spawning thread.
    call assembler.label(output, "runtime_thread_entry")
    call assembler.emit(output, x86_64.lea_base(15, 4, 16))
    call assembler.emit(output, x86_64.load_memory(7, 4, 8))
    call assembler.emit(output, x86_64.push(5))
    call assembler.emit(output, x86_64.move_reg_reg(5, 4))
    call assembler.emit(output, x86_64.sub_reg_imm(4, 24))
    call assembler.relative(output, [232], "runtime_unbox_dynamic_function")
    call assembler.emit(output, x86_64.move_reg_reg(11, 0))
    call assembler.emit(output, x86_64.call_reg(11))
    # Thread exit: the kernel clears entry.status and wakes joiners.
    call assembler.emit(output, x86_64.xor_reg_reg(7, 7))
    call assembler.emit(output, x86_64.mov_imm64(0, 60))
    call assembler.emit(output, x86_64.syscall())
end

function emit_signal_handler(output):
    # SIGUSR1 stop-the-world handler. Runs on the interrupted worker's stack
    # with its registers saved by the kernel in the sigframe, so the
    # collector's conservative scan from the saved rsp up to the stack base
    # sees every live pointer. RBX is the state block (a callee-saved global
    # invariant); rsp stays untouched so the final `ret` reaches the restorer.
    call assembler.label(output, "thread_signal_handler")
    call assembler.emit(output, x86_64.mov_imm64(0, 186))
    call assembler.emit(output, x86_64.syscall())
    call emit_entry_lookup(output, "handler_found", "handler_return")
    call assembler.emit(output, x86_64.store_memory(9, 24, 4))
    call assembler.emit(output, x86_64.store_memory_imm32(9, 16, 2))
    call assembler.label(output, "handler_gate_wait")
    # futex_wait(&state+128, 1) until the collector drops the gate.
    call assembler.emit(output, x86_64.lea_base(7, 3, 128))
    call assembler.emit(output, x86_64.xor_reg_reg(6, 6))
    call assembler.emit(output, x86_64.mov_imm64(2, 1))
    call assembler.emit(output, x86_64.mov_imm64(0, 202))
    call assembler.emit(output, x86_64.xor_reg_reg(10, 10))
    call assembler.emit(output, x86_64.xor_reg_reg(8, 8))
    call assembler.emit(output, x86_64.syscall())
    call assembler.emit(output, x86_64.load_memory(2, 3, 128))
    call assembler.emit(output, x86_64.cmp_reg_imm8(2, 1))
    call assembler.relative(output, [15, 132], "handler_gate_wait")
    call assembler.emit(output, x86_64.store_memory_imm32(9, 16, 1))
    # `ret` pops the frame return slot into the restorer, which leaves rsp at
    # the kernel ucontext as rt_sigreturn expects.
    call assembler.label(output, "handler_return")
    call assembler.emit(output, x86_64.ret())
    call assembler.label(output, "thread_signal_restorer")
    call assembler.emit(output, x86_64.mov_imm64(0, 15))
    call assembler.emit(output, x86_64.syscall())
end

function emit_join(output):
    # runtime_thread_join: rdi = kernel tid -> 0 once the worker exited, 126
    # if no table entry carries that tid (never spawned, or already reused).
    # Futex-waits on the entry status word with whatever value it holds.
    call assembler.label(output, "runtime_thread_join")
    call assembler.emit(output, x86_64.function_prologue(48))
    call assembler.emit(output, x86_64.move_reg_reg(0, 7))
    call emit_entry_lookup(output, "join_found", "join_missing")
    call assembler.label(output, "join_wait")
    call assembler.emit(output, x86_64.load_memory(2, 9, 16))
    call assembler.emit(output, x86_64.cmp_reg_imm8(2, 0))
    call assembler.relative(output, [15, 132], "join_done")
    call assembler.emit(output, x86_64.lea_base(7, 9, 16))
    call assembler.emit(output, x86_64.xor_reg_reg(6, 6))
    call assembler.emit(output, x86_64.mov_imm64(0, 202))
    call assembler.emit(output, x86_64.xor_reg_reg(10, 10))
    call assembler.emit(output, x86_64.xor_reg_reg(8, 8))
    call assembler.emit(output, x86_64.syscall())
    call assembler.relative(output, [233], "join_wait")
    call assembler.label(output, "join_done")
    call assembler.emit(output, x86_64.xor_reg_reg(0, 0))
    call assembler.emit(output, x86_64.function_epilogue())
    call assembler.label(output, "join_missing")
    call assembler.emit(output, x86_64.mov_imm64(0, 126))
    call assembler.emit(output, x86_64.function_epilogue())
end

function emit_cpu_count(output):
    # runtime_cpu_count: number of CPUs in this thread's affinity mask, or 1
    # when sched_getaffinity fails. Programs use it to size worker pools.
    call assembler.label(output, "runtime_cpu_count")
    call assembler.emit(output, x86_64.function_prologue(144))
    call assembler.emit(output, x86_64.lea_base(2, 5, -136))
    call assembler.emit(output, x86_64.xor_reg_reg(7, 7))
    call assembler.emit(output, x86_64.mov_imm64(6, 128))
    call assembler.emit(output, x86_64.mov_imm64(0, 204))
    call assembler.emit(output, x86_64.syscall())
    call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
    call assembler.relative(output, [15, 142], "cpu_count_fallback")
    call assembler.emit(output, x86_64.move_reg_reg(1, 0))
    call assembler.emit(output, x86_64.lea_base(9, 5, -136))
    call assembler.emit(output, x86_64.xor_reg_reg(8, 8))
    call assembler.emit(output, x86_64.xor_reg_reg(10, 10))
    call assembler.label(output, "cpu_count_byte")
    call assembler.emit(output, x86_64.cmp_reg_reg(10, 1))
    call assembler.relative(output, [15, 141], "cpu_count_done")
    call assembler.emit(output, x86_64.load_byte_indexed(11, 9, 10))
    call assembler.label(output, "cpu_count_bit")
    call assembler.emit(output, x86_64.test_reg_reg(11, 11))
    call assembler.relative(output, [15, 132], "cpu_count_next")
    call assembler.emit(output, x86_64.move_reg_reg(0, 11))
    call assembler.emit(output, x86_64.and_reg_imm8(0, 1))
    call assembler.emit(output, x86_64.add_reg_reg(8, 0))
    call assembler.emit(output, x86_64.shift_right_logical_imm(11, 1))
    call assembler.relative(output, [233], "cpu_count_bit")
    call assembler.label(output, "cpu_count_next")
    call assembler.emit(output, x86_64.increment(10))
    call assembler.relative(output, [233], "cpu_count_byte")
    call assembler.label(output, "cpu_count_done")
    call assembler.emit(output, x86_64.move_reg_reg(0, 8))
    call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
    call assembler.relative(output, [15, 143], "cpu_count_return")
    call assembler.label(output, "cpu_count_fallback")
    call assembler.emit(output, x86_64.mov_imm64(0, 1))
    call assembler.label(output, "cpu_count_return")
    call assembler.emit(output, x86_64.function_epilogue())
end

function emit_all(output):
    call emit_cpu_count(output)
    call emit_mutex(output)
    call emit_spawn(output)
    call emit_entry(output)
    call emit_signal_handler(output)
    call emit_join(output)
end
