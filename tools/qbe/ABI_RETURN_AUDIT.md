Native runtime return audit
===========================

The filesystem metadata repair distinguishes integer syscall statuses from
void mutators. Runtime RAX = 0 alone does not establish the language type.

| Calls | Language result | Evidence |
|---|---|---|
| `mkdir`, `__lsl_mkdir_private`, `unlink`, `rmdir` | Int status | The AST backend directly returns the syscall status. `package.ensure_directory`, `host.scratch_program_path` and updater transactions consume success zero and negative errno. The native fixture checks zero, EEXIST, ENOENT and public Any passage. |
| `writefile`, `appendfile`, `writebytes` | None | `io_runtime_linux_x86_64.lsl` success paths return a zero sentinel; failures set the recoverable TLS error. The reference documents file mutation, with no status return. Maintained `io_conformance` uses `call`; `io_error_conformance` tests recoverable exceptions. |
| `float_fill`, `float_axpy` | None | Native kernels return zero after mutating arrays. Reference entries describe in-place operations, and `floatarray_conformance`/`tensor_conformance` use `call`. The emitter's dedicated vector path preserves None. |
| `__lsl_sleep` | None | Explicit `semantic.BUILTIN_RETURN_TYPES` contract. `time.sleep` returns None; invalid durations use the runtime error channel. |
| `__lsl_set_append`, `__lsl_set_store` | None | Explicit semantic contracts; zero is the mutator sentinel. |
| `__lsl_test_small_tables` | None | Private startup-only reset, whose zero sentinel conveys no status. |
| `clock` | String | Dedicated call lowering invokes `__lsl_clock_text` before the generic NATIVE table. The old Float table entry is unreachable for this public call; monotonic/wall-time helpers still return Float. |

The old public raw ABI can interpret the same zero word as None or Int
according to context. Installed 0.8.9 reports `type(raw filesystem zero)` as
None even while comparing and printing its numeric status as zero. The repair
retains numeric filesystem behavior and correctly exposes Int at the public
Any boundary. It does not reclassify void mutators solely because their native
register return happens to contain zero.

Executed filesystem controls are recorded in
`tests/qbe_port/native-filesystem-status-linux-x86_64.json`. This document is a
source audit; it does not claim additional runtime executions or replace the
complete regression runner.
