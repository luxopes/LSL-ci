# Lock-free atomic RMW builtins over IntArray slots. Single-threaded here, so
# results are deterministic; the builtins become real synchronization only
# once several threads share the array.

a = IntArray()
a.append(10)
old = atomic_add(a, 0, 5)
print old, a[0]
old = atomic_xchg(a, 0, 100)
print old, a[0]
old = atomic_cas(a, 0, 100, 200)
print old, a[0]
old = atomic_cas(a, 0, 999, 300)
print old, a[0]
call atomic_pause()
print a[0]
