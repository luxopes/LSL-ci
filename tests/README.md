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

The original AST suite requires no C, Python, shell launcher, assembler or linker.
The native QBE path uses the same complete runner and fixtures:

```text
./tests/lsl-test qbe ./compiler/pure/lslc-qbe
./tests/lsl-test qbe-fast ./compiler/pure/lslc-qbe
./tests/lsl-test qbe-fixed-point ./compiler/pure/lslc-qbe
python3 tools/qbe/verify_integration.py --compiler ./compiler/pure/lslc-qbe \
  --build-directory build/qbe-integration --report build/qbe-integration.json
```

The native path requires its own `lsl-qbe`, trusted compiler resources and
runtime object, plus a system assembler/linker. Low-level private-runtime tests
explicitly request `--unsafe`; tests of the ordinary CLI retain safe defaults.
ELF checks require static PIE, no dynamic interpreter, W^X, no text relocations
and a non-executable stack. AST-specific object/encoder tests remain present;
the production pipeline is checked for equivalent behavior. Both paths retain the original 110400-byte standalone ELF ceiling.
The native QBE optimization fixture measures 86064 bytes after stripping.
Fixed-point mode checks both native frontend and native QBE backend. Optional
CUDA hardware and capability-sandbox gates are unchanged. Signed public-release
archive and managed-install migration tests are separate optional integrations
and are not claimed by the ordinary full runner.

CUDA 0.7.7: `cuda_session_conformance.lsl` runs on CPU by default; the runner
also compares its complete output against an NVIDIA device when
`LSL_CUDA_HARDWARE_TEST=1`. The hardware corpus checks recursive reductions,
matmul work/transport limits, tall grids and explicit device selection. Policy
tests use malformed/missing workers and check fallback without partial mutation.
`cuda_session_benchmark.lsl` reports five-run medians and verifies checksums.

Build compilers serially with a 2 GiB address-space limit. For the full suite,
use 4 GiB: the existing 9 MiB HTTP/GC stress needs roughly 2.6 GiB. That fixture
has a 180-second process alarm and allows 30 seconds per client request.
