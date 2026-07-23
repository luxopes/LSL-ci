# Native-performance plan

## Goal

Make typed numeric/byte workloads suitable for AI kernels and OS-level code while
preserving dynamic `List` semantics. The first acceptance benchmark is the
200000-element Int workload from `/tmp/lsl-vs-c-bench.*`: move from ~425x C and
185 MiB toward single-digit C overhead and low single-digit MiB RSS.

## Plan

- [x] Establish 7-run LSL/C baseline: LSL 785331 us / 189472 KiB; C 1850 us /
  3240 KiB (same checksum).
- [x] Prove the fast path with raw compiler-internal storage plus statically typed
  indexing: 11405–12583 us and 5648–9780 KiB.
- [x] Add an explicit public `IntArray` with contiguous raw Int64 slots, static Int
  indexing, checked mutation, iteration, rendering/type support, and GC safety.
- [x] Add conformance tests and benchmark `IntArray` against C.
- [x] Reach 3-stage fixed point; regenerate tools; run full/config/install/ELF
  audits.
- [x] Add raw `FloatArray` storage plus native sum/dot/axpy/matmul kernels and
  route Tensor numeric work through them.
- [x] Add packed `ByteArray` plus direct `readbytes`/`writebytes` integration for
  OS-level binary I/O.
- [x] Replace the fixed initial object registry reservation with a small mmap-backed
  growable table so tiny programs do not reserve compiler-sized metadata.

## Notes / decisions

- Dynamic `List` remains heterogeneous and boxed. Silently changing its ABI would
  break pointer-collision guarantees and generic rendering/equality.
- The measured bottleneck is dynamic element typing, not the generated loop: the
  proven raw+typed path is already roughly 6x C instead of ~425x.
- C benchmark artifacts stay in `/tmp`; the production tree remains pure LSL.

## State

All planned CPU/native-memory foundations are implemented. Final measured
medians (7 serial runs, same checksums):

- IntArray workload: 8288 us / 3584 KiB versus C 1850 us / 3240 KiB
  (4.5x time, 1.1x RSS; dynamic List was ~425x / 58.5x).
- Float64 dot kernel: 18526 us / 3072 KiB versus C 15289 us / 4776 KiB
  (1.2x time, lower RSS).
- 64x64 Float64 matmul, 20 passes: 7161 us / 1716 KiB versus C 3096 us /
  1776 KiB (2.3x time, comparable RSS).
- Packed byte loop: 27610 us / 2048 KiB versus C 1284 us / 2600 KiB; bulk file
  I/O itself is zero-copy through ByteArray backing. Scalar byte-loop range
  analysis/vectorization remains a future optimizer opportunity.
- Tiny generated program peak RSS is about 1776 KiB with a 64K-slot public mmap
  registry; compiler-profile outputs retain an 8M initial registry to avoid
  rehash cost.

Current LuxOS system-library fixed point: `7822a3a60e3361ce05ecbfdc2890a0bb538d1c01de0dfe402acb6d026b1928a8`.
Regenerated full suite (15.159 s), fixed point (2.071 s), config, installed fixed
point, ELF and pure-production-tree audits pass. Remaining high-performance work
is optional SIMD/vectorization, unchecked/range-proven byte loops, and broader
Tensor ops; the required compact CPU/AI/OS substrate is present.
