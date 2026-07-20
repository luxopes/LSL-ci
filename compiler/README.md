# Pure LSL compiler

Udržovaný compiler je `pure/lslc_direct.lsl`. Je napsaný pouze v LSL a přímo generuje statický Linux x86_64 ELF:

- `lexer.lsl`, `parser.lsl`, `linker.lsl` — frontend a moduly;
- `codegen.lsl`, `x86_64.lsl`, `assembler.lsl` — přímý machine-code backend;
- `elf_image.lsl` — ELF64 image writer;
- `heap_runtime.lsl`, `io_runtime.lsl`, `process_runtime.lsl`, `native_runtime.lsl` — syscall-only runtime.

Kanonický fixed-point ELF je `pure/lslc-direct`; veřejná kopie je `compiler/lslc`.

```text
./compiler/lslc source.lsl output
./compiler/pure/lslc-direct compiler/pure/lslc_direct.lsl /tmp/next
cmp ./compiler/pure/lslc-direct /tmp/next
./compiler/pure/lsl-test
```

Další čisté nástroje:

- `pure/lsl-cli` — veřejné run/compile/config CLI;
- `pure/lsl-configure` — config wrapper generator;
- `pure/lsl-install` — installer;
- `pure/lsl-test` — conformance a fixed-point runner.

Repozitář neobsahuje C seed ani cizí produkční toolchain. Binární trust root je auditovatelný LSL-generovaný ELF a musí reprodukovat sám sebe bit po bitu. Aktuální hash a ověřené testy jsou v `PURE_LSL_PROGRESS.md`.
