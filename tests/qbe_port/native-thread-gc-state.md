The automatic GC/thread regression exposed an asynchronous ABI mismatch.
The old runtime assumes RBX always points at its state block. QBE preserves
RBX across calls, but legitimately uses it for local values between calls.
SIGUSR1 could interrupt that code and enter the GC handler with an ordinary
heap object in RBX. The handler then dereferenced an invalid thread-table
address. The captured crash is at `handler_found_scan`, ELF offset `0x112c9`.

Each worker now receives the runtime state pointer in its unused TLS word
at offset 24 (thread-table entry+56), initialized before clone/CLONE_SETTLS.
The GC handler loads this pointer into RBX. The kernel signal frame keeps
the interrupted RBX and rt_sigreturn restores it, so QBE locals survive.
GC only signals worker-table entries. The main thread is not in that table;
its TLS layout and adjacent GC worklist word remain unchanged.

`native-thread-gc-state.json` records 14 SIGSEGV failures in 80 original runs
at concurrency four, followed by 100/100 correct runs after relinking the
identical production program object with only the runtime fix. Five other
maintained thread/GC controls passed with the fixed runtime. Their program
objects were also checked against the actual production ELF before relinking.
These are correctness checks, with no performance claim.

The repeatable stress check uses the maintained test's exact expected output:

```sh
FRONTEND --unsafe tests/automatic_gc_threads_conformance.lsl BUILD/thread-gc BACKEND
python3 tools/qbe/verify_thread_gc.py --executable BUILD/thread-gc \
    --repeat 100 --jobs 4 --report BUILD/thread-gc-stress.json
```

The final maintained harness independently passed another 100/100 runs with
the isolated fixed runtime. A combined runtime/self-host build must still run
this harness again when other runtime changes are integrated.
