# Known-issue reproductions

Standalone programs that reproduce open runtime defects. They are NOT part of
`tests/lsl-test`; they hang or fail by design until the defect is fixed.

- `gc_thread_bigheap_hang.lsl` — after a ~9 MiB HTTP body round-trips through
  a `serve_listener` running in a worker thread, a later `gc()` on the main
  thread (with another worker running) completes, but the next allocation on
  the main thread spins forever holding the heap mutex while the worker
  blocks on that mutex. Single-threaded processes and parked-worker
  topologies are unaffected; the practical rule until this is fixed is to run
  a long-lived listener in its own process, which `tests/httpserver_conformance.lsl`
  exercises. Recorded in the 0.7.5 release notes.
