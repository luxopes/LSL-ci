# Pure LSL compiler

Udržovaný compiler je `pure/lslc_direct.lsl`. Je napsaný pouze v LSL a přímo
generuje statický Linux x86_64 PIE ELF s ASLR a neproveditelným stackem:

- `lexer.lsl`, `parser.lsl`, `linker.lsl` — frontend a moduly;
- `codegen.lsl`, `x86_64.lsl`, `assembler.lsl` — přímý machine-code backend;
- `elf_image.lsl` — ELF64 image writer;
- `heap_runtime.lsl`, `io_runtime.lsl`, `process_runtime.lsl`, `native_runtime.lsl` — syscall-only runtime.

Kanonický fixed-point ELF je `pure/lslc-direct`; veřejná kopie je `compiler/lslc`.

```text
./compiler/lslc source.lsl output
./compiler/pure/lslc-direct compiler/pure/lslc_direct.lsl /tmp/next
cmp ./compiler/pure/lslc-direct /tmp/next
./tests/lsl-test
./tests/lsl-test fast
./tests/lsl-test fixed-point
```

Další čisté nástroje:

- `pure/lsl-cli` — veřejné run/compile/config/install CLI;
- `pure/lsl-configure` — config wrapper generator;
- `pure/lsl-install` — toolchain installer;
- `pure/package.lsl` — ověřená per-user instalace zdrojových knihoven;
- `tests/lsl-test` — agregovaný conformance runner s `fast`, `full` a
  `fixed-point` režimy (`full` je výchozí); jeho zdroj je `tests/test_runner.lsl`
  (cesty jsou relativní ke kořeni repozitáře).

Repozitář neobsahuje C seed ani cizí produkční toolchain. Binární trust root je auditovatelný LSL-generovaný ELF a musí reprodukovat sám sebe bit po bitu. Architektura, optimalizační pravidla, stage build a release checklist jsou v `docs/compiler-development.md`; aktuální hash a ověřené testy jsou v `PURE_LSL_PROGRESS.md`.
