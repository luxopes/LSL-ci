# LSL parser compatibility and performance plan

## Goal

Restore the specified `input "prompt"` syntax, then reduce self-host compiler
latency and peak RSS toward an optimized C implementation without changing ELF
output semantics, diagnostics, fixed-point determinism, or the pure-LSL-only
constraint.

## Baseline

- Fixed compiler SHA-256 before this task:
  `e3bb05e634d2ffbd2e4d7efff2ce71236b59191868fd47f1e4582572ceedf5e3`
- Self-host compile (3-run baseline): 3.749 / 3.745 / 3.713 s.
- Self-host peak RSS: 782100 KiB (approximately 764 MiB).
- Fast suite: approximately 4.2 s; expanded full suite: approximately 15.0 s.
- Full maintained LSL/compiler/stdlib/test sources: 13207 lines (`wc -l`).

## Plan

- [x] Restore bare `input "prompt"` parsing and add stdin-fed conformance.
- [x] Reach a new multi-stage fixed point and run full/config/install audits.
- [x] Profile compiler phases, allocation growth, and generated-byte pipeline.
- [x] Remove the largest avoidable allocation source without foreign tooling.
- [x] Re-measure time/RSS and iterate on the next measured hotspot.
- [x] Regenerate deterministic tools and run final full/fixed-point/ELF audit.

## Decisions

- “As fast/lean as C” is a direction, not an honest pre-measured guarantee. Each
  optimization must report measured deltas against this baseline.
- Long builds remain serial under `ulimit -v 1048576`.
- No C, Python, assembler, linker, shell launcher, or network dependency.
- Preserve `compiler/pure/hello.lsl` as authored with bare input syntax.

## State

Bare input compatibility is committed. Initial phase profile for self-host
(microseconds): read 60, dynamic stdlib parse 102326, recursive link/parse
1716410, codegen 1826283, write 24890.

The current fixed-point candidate keeps compiler-internal typed Int/Bool/None and
selected Any boundaries raw, materializes diagnostic lines only on failure,
appends little-endian instruction bytes without an intermediate List, and starts
the growable object registry at 8M rather than 16M slots. Five self-host runs are
1.804–1.830 s; sampled peak RSS is 376236 KiB. Against the 3.713–3.749 s /
782100 KiB baseline this is about 51% less wall time and 51.9% less peak RSS.
Latest phase profile (microseconds, before the small byte append/table changes):
read 49, stdlib parse 49038, recursive link/parse 883695, codegen 873937, write
6219.

Rejected experiments: direct-fill List literals enlarged the compiler without a
measured win; explicit `gc()` between phases was pathologically slow; recycling
assembler instruction Lists through the general free list or a one-entry cache
was unsafe/pathological. A 2M registry table reached pathological probe density
(about 693 s). A later allocation benchmark showed that 4M could likewise
collapse above roughly 50% occupancy, so the final 8M table tracks unique entries
and grows before crossing 50% rather than waiting for a complete probe wrap.

Final fixed point: `29d717fde4b57517291ef30c92606e73e6e0cbb4c059e39197db42bbeb794f7a`.
Regenerated full suite passed in 8.843 s, fixed-point mode in 1.831 s, config
output is bit-identical, the installed compiler reproduces the same fixed point,
and every maintained ELF has one RX `PT_LOAD` with no `INTERP`/`DYNAMIC`/RWX.
