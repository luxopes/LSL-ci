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
- [ ] Follow with `FloatArray`/native Tensor kernels and `ByteArray` for OS I/O.
- [ ] Replace the fixed initial object registry reservation with a small mmap-backed
  growable table so tiny programs do not reserve compiler-sized metadata.

## Notes / decisions

- Dynamic `List` remains heterogeneous and boxed. Silently changing its ABI would
  break pointer-collision guarantees and generic rendering/equality.
- The measured bottleneck is dynamic element typing, not the generated loop: the
  proven raw+typed path is already roughly 6x C instead of ~425x.
- C benchmark artifacts stay in `/tmp`; the production tree remains pure LSL.

## State

`IntArray` object code 13 is implemented. Seven runs of the exact workload now
have a 9070 us / 9780 KiB median versus C 1850 us / 3240 KiB: about 4.9x time
and 3.0x RSS, down from dynamic List's ~425x / 58.5x. Fixed point
`25f26c531189d54e3659093dab3d81f6a10572e36661c34408e34962ff84ab37`
is stable; regenerated full/config/install/ELF audits pass. Next implement
`FloatArray`/native Tensor kernels, then `ByteArray` and a small mmap-backed
object registry.
