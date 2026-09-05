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
- The runner separately drives the no-argument CLI through a pipe, `exit`, EOF and module lookup, plus hermetic per-user package hash/compile/install failures and built-in-first user module resolution.
- `compiler/` contains compiler-focused smoke drivers and their local fixtures.
- `config/` and `modules/` contain subsystem-specific fixtures.

The suite requires no C, Python, shell launcher, assembler or linker.

CUDA 0.7.7: `cuda_session_conformance.lsl` runs on CPU by default; the runner
also compares its complete output against an NVIDIA device when
`LSL_CUDA_HARDWARE_TEST=1`. The hardware corpus checks recursive reductions,
matmul work/transport limits, tall grids and explicit device selection. Policy
tests use malformed/missing workers and check fallback without partial mutation.
`cuda_session_benchmark.lsl` reports five-run medians and verifies checksums.

Build compilers serially with a 2 GiB address-space limit. For the full suite,
use 4 GiB: the existing 9 MiB HTTP/GC stress needs roughly 2.6 GiB. That fixture
has a 180-second process alarm and allows 30 seconds per client request.
