# Tests

All test runners, fixtures and generated test tools live under this tree.
`compiler/pure/` is reserved for production compiler/runtime/tool code.

```text
./tests/lsl-test              # full suite (default)
./tests/lsl-test fast         # positive aggregate + smoke checks
./tests/lsl-test fixed-point  # compiler bit reproducibility only
```

- `test_runner.lsl` is the pure-LSL source of `lsl-test`.
- `*_conformance.lsl` with matching `.out` files form the maintained regression
  corpus; `full_conformance.lsl` aggregates positive cases.
- `*_negative.lsl` files are compile-failure checks.
- `codegen_optimization_conformance.lsl` is a standalone semantic and generated-ELF size guard for optimizer changes.
- `time_conformance.lsl` covers realtime/monotonic/sleep; `os_conformance.lsl` covers command tokenization, PATH, argv, capture/status/stderr and exec failure; `lconf_conformance.lsl` covers strict apt/lux/lsl dependency manifests; `system_conformance.lsl` covers Lux-first package operations and apt fallback; `system_os_conformance.lsl` covers repository refresh, services, accounts, atomic files, mounts and LuxOS generations through hermetic command stand-ins.
- The runner separately drives the no-argument CLI through a pipe, `exit`, EOF and module lookup.
- `compiler/` contains compiler-focused smoke drivers and their local fixtures.
- `config/` and `modules/` contain subsystem-specific fixtures.

The suite requires no C, Python, shell launcher, assembler or linker.
