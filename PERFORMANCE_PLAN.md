# LSL parser compatibility and performance plan

## Goal

Restore the specified `input "prompt"` syntax, then reduce self-host compiler
latency and peak RSS toward an optimized C implementation without changing ELF
output semantics, diagnostics, fixed-point determinism, or the pure-LSL-only
constraint.

## Baseline

- Fixed compiler SHA-256 before this task:
  `e3bb05e634d2ffbd2e4d7efff2ce71236b59191868fd47f1e4582572ceedf5e3`
- Self-host compile: approximately 3.6–3.7 s.
- Self-host peak RSS: approximately 764 MiB.
- Fast suite: approximately 4.2 s; expanded full suite: approximately 15.0 s.
- Full maintained LSL/compiler/stdlib/test sources: 13207 lines (`wc -l`).

## Plan

- [x] Restore bare `input "prompt"` parsing and add stdin-fed conformance.
- [x] Reach a new multi-stage fixed point and run full/config/install audits.
- [ ] Profile compiler phases, allocation growth, and generated-byte pipeline.
- [ ] Remove the largest avoidable allocation source without foreign tooling.
- [ ] Re-measure time/RSS and iterate on the next measured hotspot.
- [ ] Regenerate deterministic tools and run final full/fixed-point/ELF audit.

## Decisions

- “As fast/lean as C” is a direction, not an honest pre-measured guarantee. Each
  optimization must report measured deltas against this baseline.
- Long builds remain serial under `ulimit -v 1048576`.
- No C, Python, assembler, linker, shell launcher, or network dependency.
- Preserve `compiler/pure/hello.lsl` as authored with bare input syntax.

## State

Bare input lowers to the normal call AST. Fixed compiler
`d3657e13366ccdad3e601a11da4614b35b405b9c29400ef0427eecf4931f32e0`, full,
config, installed fixed point, hello, and stdin-fed conformance pass. Next:
commit this compatibility milestone, then profile compiler phases and memory.
