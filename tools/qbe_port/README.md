# QBE 1.3 → LSL working port

Upstream: https://c9x.me/compile/release/qbe-1.3.tar.xz

- Release: **1.3**, 2026-06-01
- SHA256: `d587905d620dc5e1d2bfa7c2cc642b9b837aa89a3188c6e37b53d756cf66e320`
- Upstream commit: `c0818978acec60ebb6167fade60fb7012cbf20ca`
- License: [upstream MIT license](../../vendor/qbe-1.3/LICENSE)
- Scope: every production translation unit listed by upstream `make src`,
  including `gvn.c`, `gcm.c`, `ifopt.c`, the generated instruction matcher,
  and `amd64/winabi.c`. Targets are amd64 SysV/Apple/Windows, ARM64/Apple,
  and RV64. Windows is a code-generation target; the LSL runtime still runs
  on Linux x86_64.

## Integrated compiler, Linux x86_64

The compiler sources frozen at `998ef11` self-host in **46.766 and 46.092
seconds per complete frontend/backend generation**. Frontend generations 2/3
have identical bytes, as do backend generations 2/3. The frontend SHA-256
prefix is `1e123e69`; the native backend remains `38ed1e11` and the runtime
remains `23a85294`. All builds use native LSL QBE under a 4 GiB address-space
limit, with source/runtime hashes unchanged.
[Optimized self-host evidence](../../tests/qbe_port/selfhost-optimized-linux-x86_64.json)
records every command, hash and complete generation time. No cached IL or
assembly, C QBE, or old AST backend participates in these measured builds.

The accepted optimization caches a function's return inference only while the
return-map values it actually read remain unchanged. Ordered fixed-point
iteration, recursive invalidation and inherited aliases remain intact.
[Exact type/SSA and performance checks](../../tests/qbe/return-dependency-cache-linux-x86_64.json)
cover 22 cases, public/internal translation of the old compiler, eleven runtime
outputs and six byte-identical common-source executables. Generic AST scanning,
integer formatter changes and scoped validation gating did not improve measured
performance and were rejected; their separate experiment reports are retained.

[Final targeted checks](../../tests/qbe/final-native-regressions-998ef11-linux-x86_64.json)
pass 43 registered language cases, twelve inherited capture-limit cases,
four nullable/identity checks, 52 HTTP error cases and sixteen numeric-only
rejections: 127 checks in total. Correctness run times are not benchmarks.
[Broader final language checks](../../tests/qbe_port/language-optimized-linux-x86_64.json)
pass 94 cases. [Final specialized checks](../../tests/qbe_port/optimized-linux-x86_64/commands.json)
pass public integer boundaries, 14,256 division/remainder comparisons, 2,480
Float conversions, 2,502 printf calls, 636 bitset cases, process capture,
source-size boundaries, protected deterministic PIE images and public CLI.
[Executable equivalence](../../tests/qbe_port/optimized-linux-x86_64/language-binary-equivalence.json)
confirms all 92 previously maintained language executables retain identical bytes.
The final optimized pair passes
[the complete original runner](../../tests/qbe_port/complete-original-optimized-linux-x86_64.json)
and [isolated managed migration/reinstall/rollback](../../tests/qbe_port/managed-optimized-linux-x86_64.json).
The original runner exercises its full conformance aggregate, sandbox checks,
configuration, fuzzing, GC, native fixed points and resource guards. Source,
compiler, backend, runtime and installed-tool hashes remain unchanged.
[Final scope and remaining limits](../../tests/qbe_port/optimized-summary-linux-x86_64.json)
links every correctness and performance proof. The earlier `0339509` reports
remain historical evidence.
Installed 0.8.9 remains unchanged. CUDA protocol checks pass; GPU hardware was
not exercised. No release 0.9.0 has been published.

Normal public compile/run/config commands use the native LSL QBE pipeline.
Ordinary sources default to safe mode, with explicit unsafe/sandbox modes and
no implicit C QBE or old AST fallback. System `as`/`ld` produce stripped static
PIE executables with separate writable/executable mappings and no libc or
dynamic interpreter. [CLI and bootstrap instructions](../qbe/CLI.md) describe
native resource lookup and the separate initial C-reference bootstrap.

## Final performance

[Installed 0.8.9 comparison](../../tests/qbe_port/comparison-v089-optimized-linux-x86_64.json)
uses identical public source, independent result checks, three alternating build
samples and five alternating runtime samples. All eight programs run faster in
this measurement, with 21–25% smaller executables. Small sources compile in
0.56–0.60 s versus 0.55–0.56 s. The same old compiler source still takes
**12.197 s versus 8.122 s**, a remaining compile-time regression of 50%.
The nine compared native executables (eight workloads and the old compiler)
retain the bytes produced before the inference-cache optimization.

The unchanged native backend has the same SHA-256 as the
[five-run C QBE comparison](../../tests/qbe_port/benchmark-repaired-linux-x86_64.json).
All generated assembly matches the `-O2` C reference exactly:

| Preserved input | Native LSL QBE | C QBE | Native / C |
| --- | ---: | ---: | ---: |
| Frontend IL | 1.658 s | 1.611 s | 1.029 |
| Backend IL | 3.080 s | 4.330 s | 0.711 |

The strict native/C speed goal is **not met** on frontend IL (2.9% slower);
its command returns 1 for this reason. Backend IL is 29% faster. These two
fixed workloads and eight runtime programs do not establish universal speed
or compatibility. Other timing reports below describe historical checkpoints.

The earlier `f63d105` checkpoint's 47.586/47.451-second generations predate
the current runtime and guard repairs and are historical measurements.
The [historical self-host report](../../tests/qbe_port/selfhost-finished-linux-x86_64.json)
retains the earlier 55.948/57.572-second generations. The
[earlier bootstrap report](../../tests/qbe_port/selfhost-before-error-word-fix-linux-x86_64.json)
preserves a contaminated first timing sample and extra convergence generation.

The integration includes checked public numeric/collection boundaries, native
Float arithmetic, direct List slots, efficient joins/repetition, conservative
call inference, classes and callbacks, recoverable validation, stable global
storage representation, typed declarations, native lock-free atomics, process
input/callback capture, and contiguous UTF-8 slices. Runtime objects are rebuilt
from tracked LSL providers; the converter has no ignored-assembly dependency.

Historical combined validation and version comparisons are documented in
[the integration report](../../tests/qbe_port/integration-finished-linux-x86_64.json),
[the 0.8.9 comparison](../../tests/qbe_port/comparison-v089-finished-linux-x86_64.json),
and [the C-QBE comparison](../../tests/qbe_port/benchmark-finished-linux-x86_64.json).
Installed 0.8.9 is unchanged. In those historical measurements, seven of eight
executable workloads improve and allocation/GC is effectively tied. At that
checkpoint the common old compiler source builds more slowly (14.819 s new
versus 8.362 s old). Earlier checkpoint reports below remain historical
measurements; their known failures and ratios describe those earlier binaries.

Native runtime execution is Linux x86_64. QBE assembly generation covers all six
upstream ABI targets across three ISAs; this does not add runtime providers for
other operating systems. These working branches have not published 0.9.0, and
the measured corpus is not a claim of universal compatibility or speed.

## Earlier QBE port checkpoints

The complete generated port builds into a native Linux executable. All **421
functions** (405 production functions and 16 shared inline helpers) are present,
with native control flow and no placeholder implementations. The pre-fix verified
checkpoint passed all **59** upstream executable tests selected by `tools/test.sh
all`, **48** CLI cases, **11** language regressions, and **456/456** upstream
IL/target pairs across all six targets. Successful differential cases compare
exact assembly bytes; the one rejected Windows input matches reference failure.
Windows code generation does not establish Windows host runtime support.

The pre-fix integration benchmark runs **at approximately C speed on frontend IL and
faster on backend IL**. Five alternating runs on the preserved workloads give
these median backend times; all twenty compilations have exact assembly bytes:

| Preserved input | C QBE | LSL QBE | LSL / C |
| --- | ---: | ---: | ---: |
| Frontend IL | 1.663 s | 1.674 s | 1.006 |
| Backend IL | 4.477 s | 3.052 s | 0.682 |

The strict `--max-ratio 1.0` threshold is not met on the integrated frontend
workload: its median is 0.65% slower than C. Keep that result visible in the
[benchmark report](../../tests/qbe_port/benchmark-linux-x86_64.json). A separate
[independent five-run check](../../tests/qbe_port/benchmark-parity-independent.json)
of the agent's delivered binary gave C/LSL medians 1.811/1.759 s and
4.485/3.126 s, meeting the strict threshold on both. The original
[candidate report](../../tests/qbe_port/parity-linux-x86_64.json) records the
agent's own 1.627/1.609 s and 4.251/3.039 s measurements. Frontend timings
are close and the small lead changes across runs; backend IL consistently
has a larger margin. These measurements cover two fixed workloads, not a
universal speed guarantee.

**At this earlier integer-fix checkpoint, native self-host completed under
60 seconds.** Independently measured frontend generations
take **6.860 and 6.873 seconds**, and backend generations **46.993 and 47.024
seconds**. Both successive binary pairs are identical. All four builds use
native LSL QBE under a 4 GiB address-space limit, with sources/runtime unchanged.
The [integration report](../../tests/qbe_port/public-int-integration-linux-x86_64.json)
records commands, source/runtime hashes, times and binary fixed points. The
[earlier self-host report](../../tests/qbe_port/selfhost-linux-x86_64.json)
retains the measurements before this fix.

Performance changes include native scalar locals and packed Ref operations,
activation-owned aggregate buffers, native function pointers and small memory
copies, call-graph based GC/error checks, pooled rooted literals, slab allocation
for QBE-owned raw memory, native word-vector variadic calls, direct short-circuit branches,
direct packed-value construction, and buffered byte I/O with cached format plans
whose arithmetic stays native. An SSA fast path avoids redundant instruction scans
for unique definitions that are not live on entry and dominate all ordinary uses.
It preserves the original renaming order and falls back for PHI operands,
loop-carried values, use-before-definition and non-dominating definitions.
The general phi insertion scan also uses an ordered index of defining blocks,
starting at the first definition in each block while retaining visit resets,
instruction order, and the original frontier algorithm. Small static helpers
with one callsite share the existing scalar/assert-only inlining filters.
Pinned, checkout-independent C body hashes guard specialized allocation and
bitset lowerings. Function allocations use zeroed, aligned arenas with a
16 MiB retention bound; bitsets use grouped word operations and a first-bit
lookup. Immutable word printf plans and a pure input-cache probe keep the
hot byte paths free of managed collection lookups. Mutable or unsupported
formats, stream activation, and stdin retain their complete stdio paths. Dedicated
fixtures compare these cases across all six targets, including accepted undefined
inputs whose output is deliberately not executed. Exact
integer-based decimal/hexadecimal conversion rounds directly to binary32 or
binary64, avoiding intermediate rounding through binary64 for `strtof`.

Memory, primitive, GC, effect, stdio, libc and float-conversion conformance tests
pass through the native backend. The output fixture compares 204,639 bytes across
buffer boundaries and mixed output operations. A C conversion oracle additionally
checks 10,080 bit patterns/end offsets per run; C is used only as a test oracle.
An independent layout oracle checks 20 struct/union tags, 38 public typedefs,
field offsets, long-double alignment and the Ref bitfield representation.
The new word-format oracle checks 2,088 calls and 50,313 exact bytes against
host libc, including cache collisions, GC, stream switches, and oversized
output. Bitset iteration checks 636 independent cases. Dedicated arena and
input-cache fixtures cover zeroing, alignment, lifetime/reset, UTF-8, embedded
NUL, unread bytes, EOF, and closed handles.

QBE-owned memory uses explicitly freed Linux mappings and reusable aligned
slabs, outside the LSL managed object graph. The syscall bridge forwards the
seventh SysV argument. C literals have static storage duration and returned
aggregates use caller-owned buffers.

`vendor/qbe-1.3` is an unmodified reference release, not the intended runtime
backend. Python and `cc -E` are used only to regenerate/review the source
migration. The generated LSL does not interpret C, invoke QBE, or use FFI.
Native compiler intrinsics provide raw memory, integer/IEEE arithmetic,
stack storage and control flow with QBE IL instructions. The reference C QBE
remains an explicit bootstrap tool and differential oracle. The ordinary
compiler pipeline selects the native LSL backend.

## Regeneration and component checks

```sh
python3 -m venv build/qbe-port-tools
build/qbe-port-tools/bin/pip install -r tools/qbe_port/requirements.txt
build/qbe-port-tools/bin/python tools/qbe_port/inventory.py
build/qbe-port-tools/bin/python tools/qbe_port/check_layout.py
build/qbe-port-tools/bin/python tools/qbe_port/translate.py

# External C-reference bootstrap: the native backend does not exist yet.
# C QBE is selected explicitly only until qbe-lsl has been built below.
build/qbe/stage4 compiler/pure/lslc_qbe.lsl build/qbe-port-tools/compiler build/qbe/qbe
build/qbe-port-tools/compiler tests/qbe_port/memory_conformance.lsl build/qbe-port-tools/memory-test build/qbe/qbe
build/qbe-port-tools/memory-test
build/qbe-port-tools/compiler tests/qbe_port/primitives_conformance.lsl build/qbe-port-tools/primitives-test build/qbe/qbe
build/qbe-port-tools/primitives-test
build/qbe-port-tools/compiler tests/qbe_port/stdio_conformance.lsl build/qbe-port-tools/stdio-test build/qbe/qbe
build/qbe-port-tools/stdio-test
build/qbe-port-tools/compiler tests/qbe_port/libc_conformance.lsl build/qbe-port-tools/libc-test build/qbe/qbe
build/qbe-port-tools/libc-test

# Additional optimization checks:
build/qbe-port-tools/compiler tests/qbe_port/function_arena_conformance.lsl build/qbe-port-tools/arena-test build/qbe/qbe
build/qbe-port-tools/arena-test
build/qbe-port-tools/compiler tests/qbe_port/input_cache_conformance.lsl build/qbe-port-tools/input-cache-test build/qbe/qbe
build/qbe-port-tools/input-cache-test
python3 tests/qbe_port/word_stdio_oracle.py --compiler build/qbe-port-tools/compiler \
  --report build/qbe-port-tools/word-stdio.json
python3 tests/qbe_port/bitset_iteration_oracle.py --compiler build/qbe-port-tools/compiler \
  --source compiler/pure/qbe_port/qbe_backend.lsl --report build/qbe-port-tools/bitset-iteration.json

# Full generated native port:
build/qbe-port-tools/compiler compiler/pure/qbe_port/qbe_backend.lsl build/qbe-port-tools/qbe-lsl build/qbe/qbe
```

## Integration checks

```sh
# Compare all upstream IL cases on all six targets with the C reference.
python3 tools/qbe_port/verify_backend.py --backend build/qbe-port-tools/qbe-lsl

# Compile and run the upstream Linux native corpus.
env bin="$PWD/build/qbe-port-tools/qbe-lsl" binref="$PWD/build/qbe/qbe" \
  sh vendor/qbe-1.3/tools/test.sh all

# Compile two frontend and two backend generations through native LSL QBE.
python3 tools/qbe_port/verify_selfhost.py \
  --compiler build/qbe-port-tools/compiler --backend build/qbe-port-tools/qbe-lsl

# Compare the installed 0.8.9 compiler with the native self-hosted compiler.
python3 tools/qbe_port/compare_v089.py \
  --large-source "$HOME/.local/lib/lsl/compiler/pure/lslc_direct.lsl" \
  --report build/qbe-port-tools/v089-comparison/latest.json
```

The version comparison uses identical public LSL sources, three alternating
complete builds and five alternating executable runs. Independent Python
checksums gate runtime ratios. This compares each version's runtime and stdlib
as well as its compiler; it does not isolate backend performance. The optional
common compiler source is an additional compatibility/build-time check.

The self-host verifier records command lines, binary/source/runtime hashes,
wall-clock times, failures and fixed-point comparisons. Acceptance requires
identical successive frontend binaries, identical successive backend binaries,
and each build plus the latest complete frontend/backend cycle under 60 seconds.
An older bootstrap may need a third generation to converge. C QBE is not
invoked by these measured commands.
The verification report is written even on timeout; do not infer success from
source-generation coverage or the C-reference bootstrap.
