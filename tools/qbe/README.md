> **LuxIR:** od větve `luxir/frontend` compiler emituje LuxIR a používá
> samostatný backend [LuxIR](https://git.lux-ai.cz/LuxAI/LuxIR) místo QBE
> portu v `compiler/pure/qbe_port/`. Aktuální příkazy jsou v [CLI.md](CLI.md);
> [Nezávislé srovnání s LSL 0.8.9](LUXIR_BENCHMARK_20261011.md) ověřuje
> novou sestavu. Následující text popisuje historický QBE port a jeho měření.

# Native LSL compiler with QBE

The Linux x86_64 public compiler pipeline uses the existing LSL lexer, parser,
module linker, semantic analysis and validation, followed by the LSL QBE emitter
and the QBE 1.3 backend written in LSL. Normal `lsl compile`, source execution
and configuration compilation use this pipeline. Ordinary source defaults to
safe mode; explicit unsafe and sandbox modes retain their respective checks.
See [CLI modes and bootstrap commands](CLI.md).

The default backend is installed `lsl-qbe`, or the development
`build/qbe-port-tools/native-selfhost/qbe-stage3`. Missing native resources
produce an error; there is no implicit C QBE or AST-backend fallback. Trusted
system `as` and `ld` construct a stripped static PIE with separate writable and
executable mappings, a non-executable stack and no dynamic interpreter, libc
or C compiler invocation. Native program execution currently supports only
Linux x86_64. Other QBE assembly targets still need LSL runtime providers.

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

The external bootstrap/reference backend is the pinned official
[QBE 1.3 release](https://c9x.me/compile/), built with `-O2`.
Its [IL specification](https://c9x.me/compile/doc/il.html) defines the shared
interface. C QBE is used explicitly for initial bootstrap and differential
oracles, separately from normal compilation and the measured native self-host.

## Initial C-reference bootstrap

This initial bootstrap explicitly uses external C QBE before the LSL backend
exists. It is separate from the measured all-LSL frontend/backend self-host.
Ordinary compiler invocations select the native LSL backend and never fall back
to C QBE. See [the current native command path](CLI.md) for the subsequent
all-LSL bootstrap and verification commands.

Prerequisites: Linux x86_64, Python 3, `make`, a C toolchain (`/usr/bin/cc`), and
an existing native LSL compiler accepting `SOURCE OUTPUT` for initial bootstrap.
Run from the repository root:

```sh
python3 tools/qbe/bootstrap.py --bootstrap /absolute/path/to/existing/lslc
python3 tools/qbe/verify.py --backend build/qbe/qbe
build/qbe/stage4 examples/hello.lsl build/qbe/hello build/qbe/qbe
build/qbe/hello
```

The bootstrap compiler is used only to create stage1 and the runtime library.
Stage1 emits the QBE-compiled stage2. The verification script uses stage2 to
compile the **complete compiler source graph** into stage3, then stage3 to
compile it into stage4. Each measured command includes frontend preparation,
QBE emission, QBE execution, assembly and linking. It requires both compiles to
finish below 60 seconds, requires stages 2/3/4 to have identical ELF bytes, and
uses stage4 for the executable regression tests. No cached SSA or assembly is
used. QBE and the runtime object are build dependencies, not recompiled during
each source compilation.

Artifacts live in ignored `build/qbe/`: `qbe`, `runtime.o`, `stage1` through
`stage4`, generated `.ssa`/`.s`, and `verification.json`. The report records
wall-clock seconds, maximum child RSS, source hashes, dependency hashes, binary
hashes and test results. The latest checked-in report is
`tests/qbe/selfhost-report.json`.

Public integer-boundary regressions can also be run independently:

```sh
python3 tools/qbe/verify_public_int.py --compiler /path/to/frontend \
    --backend /path/to/native-qbe --baseline /path/to/previous-frontend
```

`--baseline` is optional. The collision fixture deliberately uses integers
whose bits equal live boxed Int/Bool addresses; it checks explicit unboxing,
`Int(Any)`, decimal parsing, arithmetic and collection updates. A second
fixture repeats public function calls up to one million times and compares
each result with a Python integer oracle. The standard verifier also tests
eight live boxed arguments across automatic and explicit GC.

The QBE emitter must pass the original value to explicit unbox helpers and
treat the successful `__lsl_int_any` result as a raw Int. Probing that result
again can dereference an unrelated live object with the same numeric address.
Likewise, `__lsl_text_digits` returns a raw Int, not a boxed Float. These
lowering errors caused the address-dependent public-call checksum failures;
the fix leaves the runtime object and GC unchanged. Recorded evidence is in
`tests/qbe/public-int-linux-x86_64.json`, including separate pre-existing
failures from broader public-language probes. This is not a claim of full
public-language compatibility or a new performance comparison.

Additional endurance results are in
`tests/qbe/public-int-endurance-linux-x86_64.json`: public calls at two and
five million iterations, and List/Dictionary updates at one and two million,
each in three fresh candidate processes. All 18 candidate checks match the
Python oracle and six installed-0.8.9 control runs. The report identifies the
unchanged fixtures and original comparison by commit/hash; it does not replace
the historical `comparison-v089-linux-x86_64.json` or measure a speed ratio.

## Historical combined native validation (2026-10-10)

At this earlier checkpoint, complete frontend/backend generations took
**55.948 and 57.572 seconds**. Both successive frontend binaries and
both backend binaries are byte-identical. No C QBE is invoked by these builds.
The final combined binary passes **91 maintained language/output fixtures**,
**40 codegen fixtures**, **558 QBE input/target pairs** across all six upstream
ABI targets, and **59 upstream native executable tests**. Exact numeric,
public ABI/GC, process-capture and CLI controls are included in the
[combined report](../../tests/qbe_port/integration-finished-linux-x86_64.json).

The historical comparison against unchanged installed **0.8.9** uses identical
sources and shared iteration counts, three alternating builds and five alternating
executable runs. All eight workloads match independent checksums. Ratios below
1 mean faster executable runtime. These compare the complete versions,
including their runtimes and standard libraries.

| Workload | 0.8.9 median (s) | New median (s) | New / 0.8.9 |
| --- | ---: | ---: | ---: |
| integer_loop | 0.407475 | 0.304057 | 0.746 |
| function_calls | 0.334916 | 0.005773 | 0.017 |
| float_loop | 0.109856 | 0.042329 | 0.385 |
| intarray_access | 0.076797 | 0.048825 | 0.636 |
| list_access | 0.218390 | 0.139476 | 0.639 |
| dictionary_access | 0.190682 | 0.143909 | 0.755 |
| string_split_join | 0.482870 | 0.201278 | 0.417 |
| allocation_gc | 0.274321 | 0.274576 | 1.001 |

[Raw version comparison](../../tests/qbe_port/comparison-v089-finished-linux-x86_64.json)
records every build/run, iteration count, checksum and dependency hash.
Allocation/GC is effectively tied; the small difference is below one percent.
The identical installed compiler source translates in **14.819 s new versus
8.362 s on 0.8.9**, or 1.772 times the old compile time.
This is a translation-time regression despite faster generated programs; it
is separate from the new compiler's own full frontend/backend self-host.

The backend-only comparison requires exact assembly on the same preserved IL.
Three alternating samples give **C/LSL 1.654/1.621 s** for frontend IL and
**4.307/3.039 s** for backend IL. This establishes parity on these workloads,
not universal speed. [Raw backend comparison](../../tests/qbe_port/benchmark-finished-linux-x86_64.json).

One earlier immediate source-budget error was not reproduced. The later full
self-host and language tests pass, but its root cause is not established; see
[the retained observation](../../tests/qbe_port/final-linux-x86_64/startup-budget-observation.json).
Native execution remains **Linux x86_64**; other QBE targets do not supply
additional LSL host runtimes. These are working-branch results, not a 0.9.0 release.

The older checkpoint below retains its original timings and failures.

## Historical integrated public-performance checkpoint (2026-10-10)

Both the integer/IntArray and native Float branches are now integrated.
The [new combined comparison](../../tests/qbe_port/comparison-v089-integrated-public-perf-linux-x86_64.json)
uses the installed 0.8.9 compiler, identical sources and shared iteration counts,
three alternating complete builds and five alternating executable runs. All
8 workloads match independent Python checksums. This compares whole compiler
versions, including runtime and stdlib, on Linux x86_64. Ratios below 1 mean
that the integrated version is faster.

| Workload | 0.8.9 median (s) | Integrated median (s) | New / 0.8.9 |
| --- | ---: | ---: | ---: |
| integer_loop | 0.372042 | 0.283650 | 0.762 |
| function_calls | 0.123082 | 0.475007 | 3.859 |
| float_loop | 0.106005 | 0.099094 | 0.935 |
| intarray_access | 0.074890 | 0.038335 | 0.512 |
| list_access | 0.111171 | 0.391902 | 3.525 |
| dictionary_access | 0.120275 | 0.314071 | 2.611 |
| string_split_join | 0.152998 | 0.474011 | 3.098 |
| allocation_gc | 0.170730 | 0.362296 | 2.122 |

The identical installed compiler source builds in **14.320 s versus
8.010 s**, or 1.788 times the old compile time. This
checks translation only, not behavior of those resulting old-source compilers.
The new compiler's own self-host is a different source graph: frontend builds
6.690/6.805 s and backend builds 45.962/45.524 s,
all using native LSL QBE under 4 GiB, with byte-identical successive generations.

The [combined integration report](../../tests/qbe_port/public-performance-integration-linux-x86_64.json)
records source hashes, both merged parent commits, targeted regressions,
constant-division oracles, QBE differential checks and current known gaps.
Full language conformance and universal performance parity remain incomplete.
The independent integer and Float checkpoint reports below retain their
original measurements; they are historical, separate measurements.

## Historical public integer performance checkpoint (2026-10-10)

The IntArray and integer-loop regressions are resolved in this checkpoint.
The other public workloads and compiler throughput still need optimization.
The final native self-hosted pair was measured with the unchanged
`tools/qbe_port/compare_v089.py` and eight `tests/benchmarks/v089` fixtures:
three alternating complete compiles and five alternating process runs per
compiler, identical input counts and independent checksums. All eight pass.

| Workload | 0.8.9 median (s) | New median (s) | New / 0.8.9 |
| --- | ---: | ---: | ---: |
| integer_loop | 0.384455 | 0.288413 | 0.750 |
| function_calls | 0.127310 | 0.472750 | 3.713 |
| float_loop | 0.068828 | 0.351796 | 5.111 |
| intarray_access | 0.074196 | 0.035464 | 0.478 |
| list_access | 0.110283 | 0.391428 | 3.549 |
| dictionary_access | 0.123184 | 0.316289 | 2.568 |
| string_split_join | 0.151836 | 0.463613 | 3.053 |
| allocation_gc | 0.159915 | 0.334382 | 2.091 |

The preceding independent report recorded integer/IntArray ratios of
4.09/17.53. Those are separate calibrated runs; the diagnostic fixed-count
before/after samples are retained as well. Small complete compiles remain
1.26–1.30 times slower. Compiling the identical installed compiler source
takes 14.479 s versus 8.114 s (three-run medians, ratio 1.784). That comparison
checks compilation success, not execution of the resulting old compiler.

The changes are split into three production commits:

- `db2b822`: emit a checked raw IntArray store for proven Int values and
  Int/Bool indices; keep negative-index normalization, bounds checks,
  evaluation order and the dynamic fallback. Load length/data after index
  side effects. Remove an unused box from typed append.
- `e7ceb70`: remove a loop's GC poll only if its emitted condition and body
  contain no allocation-capable runtime/indirect calls. Direct LSL callees
  already poll their own allocations. Allocating loops retain their polls.
- `e86f1e9`: share the existing signed constant-division analysis with the
  native backend. QBE uses shifts/masks for positive powers of two. For
  other positive literal divisors below 2^31, a signed-32-bit dividend guard
  permits a widening multiply; larger Int64 values retain division. Floor
  quotient/remainder semantics are preserved. The legacy helper's default
  64-bit algorithm is unchanged and separately tested.

The fixed-count IntArray diagnostic takes 0.544 s globally and 0.511 s
inside a function before these changes, versus 0.032/0.025 s with 0.8.9.
Global access is not the main cause. At 100,000 iterations, emitted
`box_int` calls fall from 201,026 to 2, `dynamic_set` from 100,000 to zero,
and GC polls from 101,103 to 1,103 after both store and poll changes.
Old-native disassembly already uses inline checked stores and constant
division; baseline QBE uses helper calls and hardware division. Profiling
uses call counters in a separate assembly copy, disassembly and timed
ablations. CPU sampling was unavailable (`ptrace` denied); call counts are
not cycle samples. No globals are cached or promoted, no runtime/GC object
is changed, and public Any/Float call and storage conventions are unchanged.

Final validation: 14 language fixtures (the original 13 plus typed-store
boundaries/aliases/side effects), 30 public integer collision/recurrence
runs, 14,256 signed division/remainder pairs against Python, five GC-root
fixture processes, and 18 long public-function/List/Dictionary candidate
runs plus six 0.8.9 controls. The generated division fixture also passes
through the current legacy backend after moving the shared analysis.
Native frontend generations take 6.873/7.853 s and backend generations
48.799/47.113 s, with both byte-identical fixed points under 60 s and 4 GiB.
QBE differential checks pass 456 upstream, 78 fast-path and six generated
division target/case pairs; both frozen large IL inputs produce assembly
identical to the unchanged C reference.

`boxed_int_infrastructure_conformance`, `boxed_int_operations_conformance`
and `automatic_gc_conformance` still **fail** exactly as the baseline did;
they are recorded as known failures, not passes. `gc_raw_buffer_conformance`
passes both before and after.

Raw evidence, commands, source/binary hashes and assembly excerpts:

- [Final comparison](../../tests/qbe_port/comparison-v089-after-integer-perf-linux-x86_64.json)
- [First typed-store checkpoint](../../tests/qbe_port/comparison-v089-intarray-store-linux-x86_64.json)
- [Profiles, diagnostics and validation](../../tests/qbe_port/public-integer-performance-linux-x86_64.json)

For a fresh comparison use a new report filename. For example, after creating
the native pair with `tools/qbe_port/verify_selfhost.py`:

```sh
python3 tools/qbe/verify_constant_division.py \
    --compiler build/qbe-port-tools/native-selfhost/frontend-stage3 \
    --backend build/qbe-port-tools/native-selfhost/qbe-stage3
python3 tools/qbe_port/compare_v089.py \
    --new build/qbe-port-tools/native-selfhost/frontend-stage3 \
    --backend build/qbe-port-tools/native-selfhost/qbe-stage3 \
    --large-source /absolute/path/to/installed/compiler/pure/lslc_direct.lsl \
    --report build/qbe-port-tools/new-public-comparison.json
```

`tools/qbe_port/profile_calls.py --assembly INPUT.s --runtime RUNTIME.o
--output COPY --report COUNTS.json 100000` instruments only a diagnostic
copy. Do not use its executable for timing.

## Historical native Float checkpoint

The isolated Float checkpoint starts at `4f730f7`; it does not include the
parallel integer/IntArray performance changes. Proven Float/Int/Bool arithmetic
uses portable QBE double operations instead of generic runtime arithmetic.
Pure arithmetic trees keep intermediate values and literals in double
temporaries and allocate one ordinary Float at the expression boundary.
Calls and indexing prevent tree fusion. The general binary path loads payloads
after both operands have been evaluated, preserving mutation and GC ordering.

Public Float values, locals, arguments, returns and collections keep their
boxed word representation. Unary plus preserves object identity; independent
Float literals remain independent objects. The language scalar `is` operator
compares Float values using IEEE equality, so equal values in separate boxes
compare true; `is` retains object identity for collections. Int subexpressions wrap before
conversion to double. There is no reassociation, FMA contraction, comparison
rewrite, or Float-local storage change. Float division retains IEEE infinity
and NaN behavior, while Int/Int division retains its zero exception.

The [Float integration report](../../tests/qbe_port/public-float-performance-linux-x86_64.json)
records three baseline-controlled fixtures, all 16 language regressions,
30 public integer checks, native self-host fixed points, 456 upstream and
18 generated-Float target/input differential pairs, and both preserved large
IL comparisons. All six QBE ABI targets produce assembly identical to C QBE;
execution tests remain Linux x86_64 only. Frontend builds take 7.327/6.702 s;
backend builds take 48.098/45.608 s under the 4 GiB limit.

The [complete 0.8.9 comparison](../../tests/qbe_port/comparison-v089-after-float-perf-linux-x86_64.json)
uses three alternating full builds and five alternating execution runs per
workload. Its Float ratio is **0.922 new/old**. A separate seven-run check at
the same 504,001 iterations measures medians of **0.73271 s before this change,
0.09780 s after, and 0.10518 s for 0.8.9**. This is one Float workload, not
universal Float or whole-language performance parity. Other workloads in this
isolated branch retain the earlier performance gaps.

Diagnostic counters at 100,000 iterations show Float allocations falling from
400,003 to 100,002, all runtime allocations from 1,200,082 to 100,079, and GC
calls from 15 to 1. Counter-instrumented timings are not performance evidence.
The profiler verifies that its original assembly reproduces the production
runtime object before instrumenting a separate copy:

```sh
python3 tools/qbe/profile_float_allocations.py \
    --baseline /path/to/4f730f7/frontend \
    --compiler /path/to/current/frontend --backend /path/to/native-qbe \
    --runtime-assembly /path/to/matching/runtime.s \
    --iterations 1000 --iterations 10000 --iterations 100000
```

`native_float_arithmetic`, `native_float_boundaries` and `native_float_effects`
cover binary64 rounding, signed zero, subnormals, overflow, NaN payloads,
Float/Any and collection boundaries, callbacks, eight arguments across GC,
identity, mutation order and integer division errors. Baseline controls also
document pre-existing Float gaps. The combined audit corrects the original
FloatArray probe's expectation: `FloatArray(existing)` is a checked cast, not
an iterable constructor, and must reject List. That checkpoint incorrectly
accepted it, and some Float comparison results printed as `1` instead of `True`.
The combined report tests these independently against 0.8.9 and preserves the
superseded probe transparently. The typed-array boundary fixture uses the valid
empty constructor plus append path.

## Implementation and ABI

- `compiler/pure/lslc_qbe.lsl`: native frontend/backend driver.
- `compiler/pure/qbe_emit.lsl`: reachable-function traversal, AST control flow,
  QBE operations and calls. Mutable temporary definitions let QBE build SSA;
  there are no block parameters for every source local.
- `compiler/pure/qbe_runtime_dump.lsl` and `runtime_object.py`: build the existing
  LSL Linux runtime into a relocatable object, preserving label relocations.
  The runtime emitters are build-time library providers, not compiler imports.
- SysV bridges restore the runtime's RBX state pointer while preserving QBE's
  RBX. Explicit GC captures roots in R12–R15 and scans caller stack slots;
  globals register a start/end address range. Raw Int/Bool and public boxed Any
  use the existing LSL value layout. Function calls use QBE's SysV lowering,
  including stack arguments.
- QBE binary output has a fixed assembler file symbol and no ELF build ID, so
  temporary assembler filenames cannot defeat byte-for-byte reproducibility.

## Historical integration checkpoints and remaining work

The reports below retain the failures and successes of their recorded source
revisions. They do not replace current self-host evidence or the pending full
integration and version comparison.

Class lowering is covered by the targeted checkpoint in
[`classes-checkpoint-linux-x86_64.json`](../../tests/qbe/classes-checkpoint-linux-x86_64.json).
The four maintained class fixtures previously failed at `QBE statement: class`
while installed 0.8.9 passed. QBE now emits the existing Dictionary-based class
and instance representation, class-body conditions/fields, constructor calls,
static/instance methods, inherited initializers/methods, `origin`, and field
deletion. Class calls reuse the shared frontend's method resolution and
prepared positional/default/keyword arguments. Their right-to-left argument
evaluation follows the native backend. Public `type` reports `Class` or
`Instance`; the internal class-name suffix is not exposed. Class-specific
recoverable validation errors follow the existing QBE exception path.

All ten candidate class checks pass: five maintained positive fixtures,
two new fixtures, and three negative diagnostics identical to 0.8.9. Nine old
controls pass. The remaining new `class_default_call_flow` fixture exposes an
existing 0.8.9 inference bug: skipped default-bearing method bodies can pass
Float/String values into a callee specialized from an unrelated Int call.
The old compiler prints large address-derived integers; the fixed shared class
inference guard produces the independent expected output `4`, `3.0`, `zz`,
`xx`. Its failed old control is preserved, not counted as a compatibility pass.
The new class boundary fixture also covers aliasing, constructor exceptions,
argument binding errors, and an instance plus eight arguments across explicit
GC. No runtime provider or ABI layout changes are required.

This is a targeted source checkpoint; the combined integration audit owns the
full language/self-host/backend checks. It is not a claim that every class or
public-language behavior matches 0.8.9. In particular, scalar class fields use
ordinary public boxing here; the older native class-body field path did not
box scalars consistently. Further compatibility probes should distinguish
representation bugs in old output from intended Int/Bool/None semantics.

```sh
python3 tools/qbe/verify_classes.py --compiler /path/to/frontend \
    --backend /path/to/native-qbe --old /path/to/installed/lslc
```

The validation checkpoint (`agent/qbe-validation-20261010`, source `b3a48d8`)
adds the existing frontend's recoverable error decisions to QBE emission,
preserving source locations and short-circuit evaluation. Public Function
values use small Any-return entry wrappers; direct calls retain their inferred
ABI. `safe`/`try` exits clear caught errors, `last_error()` boxes absent errors
as None, and `rang`, `help`, `thread_spawn` and `thread_join` use existing helpers.
Range counters retain the native visible-binding semantics, including empty
ranges, body assignments, continue and break. No runtime source was changed.

Eight candidate fixtures and the same eight installed 0.8.9 controls pass.
Two complete frontend self-compiles took 7.385/7.065 seconds under 4 GiB and
produced identical bytes. Raw commands, hashes, successful checks and earlier
failed probes are retained in
[`validation-checkpoint-linux-x86_64.json`](../../tests/qbe/validation-checkpoint-linux-x86_64.json).
Reproduce the targeted checks with:

```sh
python3 tools/qbe/verify_validation.py --compiler /path/to/verified/frontend \
  --backend /path/to/native/lsl/qbe --build-directory build/qbe-validation/check \
  --self-host
```

Bootstrap this checkpoint using a verified pre-collections frontend, or an
already corrected generation. An intermediate compiler emitted public
`iter_get` for internal raw indices; index zero then appeared as None to the
new checked runtime. The source now retains the internal `get` path, confirmed
by the two-generation fixed point. On this branch's `8cf20ba` base,
`rang_value_conformance` and `comprehension_conformance` still fail and need
the coordinator's numeric integration and further investigation. Full backend
self-host and differential verification remain integration checks.
The follow-up source checkpoint `e22f8a2` keeps global storage encoding fixed
to `unit.types`, matching global reads. Comprehension analysis can refine the
emitter's local type map; previously a refined global was written as raw Int
and later read as public Any. In particular, integer zero then appeared as
None to a dynamic arithmetic helper. This general representation correction
fixes both maintained `comprehension_conformance` and `rang_value_conformance`
without changing arithmetic helpers or the runtime.

All ten cases in `tools/qbe/verify_validation.py` pass for the candidate and
installed 0.8.9. The complete candidate bootstrap took 7.581 seconds, using the
coordinator's integrated numeric source and unchanged runtime
`f46a1c9d8e7f3eb7d87407954453c840c5c7761acab799993efe8de4e2c1a05d`.
[`global-representation-checkpoint-linux-x86_64.json`](../../tests/qbe/global-representation-checkpoint-linux-x86_64.json)
records the original failing diagnostic, source, commands, hashes and passing
controls. Full combined self-host, differential tests and performance reports
remain coordinator integration checks; these ten controls do not certify
complete language compatibility.

This proves a native, reproducible self-host below one minute. It does **not**
complete release 0.9.0 or certify the full language/stdlib corpus. The original
installed 0.8.9 control compiler is unchanged; the current source pipeline
defaults to native LSL QBE. The maintained QBE verification covers its own
core fixture and selected existing public-language regressions, including
Unicode, boxed collections, Float/String conversions, integer boundaries,
bitwise operations, parameter inference and recursive returns.

Integration checkpoints below address the earlier collection, class, numeric,
validation and runtime catalog failures. Their individual results have narrower
scope than a release certification. Native execution is Linux x86_64;
additional CPU/OS runtime and ABI providers remain separate work. QBE's other
assembly targets do not make the LSL runtime portable. Consult the latest
combined audit for the exact tested corpus and source/runtime hashes.

Collection checkpoint `67f9986` fixes checked IntArray/FloatArray/ByteArray casts,
Set tagging and boxed slots/private iteration, RealArray constructor/literal
validation and tags, and public method boundaries. List literals allocate their
complete backing storage before evaluating elements in order. Proven List stores
use checked direct slots; String joins over List/Tuple validate every element and
copy UTF-8 bytes into one result, preserving empty/single-piece identity. String
repetition uses powers of two with the existing size limit and fresh-result rule.

The QBE runtime provider now starts public programs with the same 512 KiB growing
object registry as 0.8.9. Internal compiler units reserve 64 MiB before creating
literals. Rebuild the provider with the native frontend/backend, run the dumper,
then `python3 tools/qbe/runtime_object.py PREFIX`; no ignored assembly patch is
required. Runtime SHA256 at this checkpoint is
`59e4dc4f36ea755a74eb00d032f7d972944cf1f15e182378aa60ce8ed79654a5`.
The converter also registers static native diagnostic Strings on first inspection
while preserving subsequent `last_error()` identity and the None result.

Raw checkpoint evidence is
`tests/qbe_port/public-collection-performance-linux-x86_64.json`: 23 registered
fixtures pass; the original boxed integer and automatic-GC conformance tests pass.
Five alternating old/new runs with identical long counts give execution ratios
List **0.6423**, Dictionary **0.8273**, strings **0.4709**, allocation **1.0943**.
Allocation remains slower and public membership still needs the root-owned checked
dispatch fix, so this is not a final release/parity claim. Diagnostic counts are
separate from timings and include the preceding root Any arithmetic changes.

Collection load followup `b2755a75fea73cfdbce1a30e75ab6fa9873e41fc`
adds a runtime tag guard before direct boxed-slot reads through public Any
receivers with Int/Bool indices. List, Tuple, and RealArray use checked negative
indexing and bounds; other receivers retain checked dynamic dispatch. It also
fixes checked keys/slice/insert/pop indices, typed declaration casts, List.find,
and the terminating range-loop binding without changing break behavior.

The independent report
`tests/qbe_port/public-collection-load-followup-linux-x86_64.json` records 24/24
language fixtures and five existing/new old-compiler controls passing. Five
alternating allocation runs at N=500000 have medians0.395659s candidate versus
0.396327s0.8.9 (ratio0.998314), within0.2% of parity; no meaningful speedup is
claimed. The tracked runtime remains59e4dc4f. Full collection membership remains
an integration check with the coordinator's separate comparison fix.

Native atomic runtime checkpoint `364653095f91cad7ce9b7a4d905347c526c99ac0`
provides four leaf services using the existing Linux x86_64 lock-prefixed
xadd, xchg, cmpxchg, and pause encoders. The QBE emitter preserves IntArray
validation, negative-index normalization, source-aware bounds errors, and
operand evaluation order. It loads backing storage after value expressions,
so allocation or array growth in those expressions cannot stale the address.

`tools/qbe/verify_runtime_catalog.py` reproducibly builds the tracked runtime
provider and compiler, then compares unchanged runtime fixtures with installed
0.8.9. `tests/qbe_port/native-runtime-catalog-linux-x86_64.json` preserves source
and artifact hashes, commands, native disassembly, and exact old/new outputs.
Eight owned controls pass on both compilers: atomics, the new atomic effect/GC
fixture, time, raw-buffer GC, GC stress, automatic GC with threads, threads,
and thread reuse. A ninth security control passes on 0.8.9 and remains blocked
on the coordinator's separate missing `native_size` lowering. No final combined
selfhost or performance claim is made by this checkpoint.

The runtime object SHA is
`6780bb856d07a9017e40a90931487b0905c58dbe30b1ee08bc1f8f1d3e0d691b`.
Rebuild it from this source using the seed frontend and QBE backend:

```sh
FRONTEND compiler/pure/qbe_runtime_dump.lsl DUMP BACKEND
DUMP PREFIX
python3 tools/qbe/runtime_object.py PREFIX
```

Native installation contract: staged binaries are `compiler/pure/lslc-qbe`
(the native frontend), `compiler/pure/lsl-qbe` (the native QBE backend), and the
existing CLI/configure/test/installer tools. The installer installs these as
`bin/lslc`, `bin/lsl-qbe` and their ordinary public tool names. It copies all
six `compiler/pure/qbe_port/*.lsl` modules, `qbe_emit.lsl`, `qbe_toolchain.lsl`,
`lslc_qbe.lsl`, `qbe_runtime_dump.lsl` and the trusted runtime object to
`lib/lsl/compiler/qbe/runtime.o`. A source checkout obtains the object from
`build/qbe/runtime.o`; a downloaded/installed bundle retains its trusted
`compiler/qbe/runtime.o` resource. Native installs never substitute C QBE.
Managed updates include `lsl-qbe` in their atomic generation switch; old
signed generations remain usable for rollback without requiring that tool.

`tools/qbe/verify_integration.py` compiles and executes the **complete original**
`tests/test_runner.lsl` in native QBE mode, including process fixtures, stdin,
config snapshots/limits, package install/update/provenance, compiler diagnostics,
installed resources and native frontend/backend fixed points. It keeps the
runner's explicit hardware/sandbox gates and records them in its JSON report.

Native image API
---------------

`compiler/pure/qbe_toolchain.lsl` provides `image(unit, selected, entry_source="", backend_path="")` for the low-level compiler and the public CLI. It returns the complete ELF as a `ByteArray`, builds in an atomic private scratch directory, and removes scratch artifacts on success or recoverable `CompileError`. The default backend is the installed `lsl-qbe` executable (the native LSL QBE); development builds use `build/qbe-port-tools/native-selfhost/qbe-stage3`. There is no implicit C QBE fallback. Installed runtime resources live in `compiler/qbe/runtime.o` under the LSL resource prefix; repository builds use `build/qbe/runtime.o`.

Image construction invokes trusted system `as` and `ld` directly, without `cc`, libc, startup CRT objects, or a dynamic interpreter. The stripped output is static PIE (`ET_DYN`), with separate writable and executable mappings and a non-executable stack. Linker `-z text` rejects text relocations. `entry_source` is separate from the diagnostic source path: source execution uses its source directory for `.env`, while a standalone compiled executable uses its executable directory, matching the original backend.

`python3 tools/qbe/verify_image.py --compiler FRONTEND --backend LSL_QBE --build-directory BUILD --report REPORT` checks deterministic bytes across private scratch paths, ELF segment and relocation protections, runtime ASLR, both source-entry modes, and cleanup after an actual failing backend process.

Full-run integration discovered missing filesystem return metadata: `mkdir`,
`__lsl_mkdir_private`, `unlink` and `rmdir` return integer syscall statuses,
including success zero. Native QBE now retains these results as Int instead of
None. `tests/qbe_port/native_filesystem_status.lsl` checks success, EEXIST, ENOENT
and passage through a public Any function; the original runner includes it in
native mode. The 0.8.9 control agrees on numeric statuses but has an existing
`type(raw zero status) == "None"` defect; the native result is correctly Int.

The startup verifier and allocation profilers request intermediate artifacts explicitly through `tools/qbe/source_artifacts.py` and the tracked `qbe_emit_diagnostic.lsl` tool. A compiler that still emits its own `.ssa` and `.s` supplies those files directly. For the current compiler, the diagnostic tool regenerates them and links an uninstrumented executable; its bytes must equal the actual production ELF before any startup inspection or counter instrumentation proceeds. Each diagnostic run retains an `.artifacts.json` provenance record. Production compilation continues to clean all private intermediate files.

When an earlier aggregate failure blocks diagnosis, `verify_integration.py
--phase post-aggregate --mode qbe` runs the unchanged later checks from the
maintained runner: language diagnostics, JSON/frontend fuzz, GC, process fault
injection, configuration limits/purity/snapshots and native byte fixed points.
It copies the original preamble and post-aggregate body into an isolated
runner and labels its output/report as a diagnostic phase. A phase PASS does
not establish a complete-corpus PASS; the default still runs every check.

Descriptor fault injection uses the existing `runtime_test_fd_fault` service
and retains its integer result. The original slots0/slots2 fixtures exercise
pipe and memfd setup failures and match installed0.8.9 exactly. Output checks
require the expected process status; configuration type errors explicitly
expect exit1 as well as their original source-aware diagnostic.

The final combined Linux x86_64 integration reports are
`tests/qbe_port/complete-original-native-linux-x86_64.json` and
`tests/qbe_port/managed-and-bundle-final-linux-x86_64.json`. Both pass using
source freeze0339509, native frontend d26a3b71 and backend38ed1e11, with runtime
23a85294. The complete original runner includes the shared positive aggregate,
public CLI, standard library, process/I/O/threads/GC, negative diagnostics,
package/update/config, ELF protections and both native byte fixed points.
The capability sandbox ran successfully. CUDA protocol tests passed; real
CUDA hardware was not requested. Signed public release archives remain a
separate external-artifact check.

The staged native bundle also passes isolated migration from installed0.8.9,
two managed reinstalls, two rollbacks and health compilation/execution. Actual
installed tool hashes and the complete runner's source snapshot remain
unchanged. These shared correctness runs make no performance claim. Earlier
checkpoint reports intentionally retain their failures for diagnosis; they
are superseded by these complete final reports.
