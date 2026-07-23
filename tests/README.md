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
- `compiler/` contains compiler-focused smoke drivers and their local fixtures.
- `config/` and `modules/` contain subsystem-specific fixtures.

The suite requires no C, Python, shell launcher, assembler or linker.
