# Lux Simple Lang (LSL)

LSL 0.7 je self-hostovaný jazyk pro běžné programování, deklarativní konfiguraci a AI orchestrace. Produkční implementace je pouze LSL: compiler přímo zapisuje statický Linux x86_64 ELF a runtime používá přímé syscalls. Není zde C/C++, libc, assembler, linker, Python ani shell launcher.

## Použití

```text
./lsl program.lsl arg1 arg2
./lsl compile program.lsl program
./lsl config examples/config/system.lsl
./compiler/lslc program.lsl program
```

`lsl` i `compiler/lslc` jsou LSL-generované ELF soubory. Výstup compileru je statický syscall-only ELF bez section headeru a bez dynamic interpreteru.

## Čistý build a test

```text
./compiler/pure/lslc-direct compiler/pure/lslc_direct.lsl /tmp/lslc-next
cmp compiler/pure/lslc-direct /tmp/lslc-next
./compiler/pure/lsl-test              # plný suite (výchozí)
./compiler/pure/lsl-test fast         # pozitivní conformance bez auditních kroků
./compiler/pure/lsl-test fixed-point  # pouze bitová reprodukce compileru
```

`lsl-test` bez shellu linkuje pozitivní corpus do jednoho agregovaného ELF se
zachováním původních source spans; plný režim navíc spouští negative corpus,
config a fixed-point kontrolu. Aktuální SHA-256 je v `PURE_LSL_PROGRESS.md`.

## Instalace

```text
./compiler/pure/lsl-install /tmp/lsl-prefix
/tmp/lsl-prefix/bin/lsl program.lsl
```

Bez argumentu installer používá `/usr/local` (podle oprávnění procesu). Installer, build nástroje i test runner jsou LSL-generované ELF soubory. Instalovaný compiler hledá standardní moduly relativně k vlastnímu `/proc/self/exe`, takže funguje z libovolného pracovního adresáře.

## Implementované jádro

- Int, Bool, None a boxed IEEE-754 Float;
- UTF-8 String s code-point `len`, indexací, slicingem, `chr` a `ord`;
- List, Tuple, RealArray, Dictionary a neboxované `IntArray`/`FloatArray`/packed `ByteArray`;
- functions, recursion, first-class Function pointers a callbacks;
- classes/instances, static i bound metody, public/private module class lowering;
- recursive modules, `safe`, `try/else`, `Error`, `check`, `last_error`;
- conservative stack/global-root mark-sweep GC s reusable free-list;
- JSON, čistý config evaluator, filesystem, argv, environment, process/capture, HTTP(S) přes bezpečné `curl` argv a verzované JSON process plugin ABI bez shellu;
- strukturované compile errors: kód, soubor, řádek, sloupec, výřez, caret a help.

`tests/selfhost_conformance.lsl` produkuje přesně `tests/selfhost_conformance.out`. Config příklad produkuje přesně `tests/config_expected.json`.

## Zdroj compileru

Vstupní bod je `compiler/pure/lslc_direct.lsl`. Lexer, parser, linker, x86_64 encoder, ELF writer a runtime jsou moduly v `compiler/pure/`. Standardní moduly jsou v `stdlib/`.

Známé zbývající mezery jsou vedené výhradně v `PURE_LSL_PROGRESS.md`; zejména GPU/device backend, SIMD autovektorizace, širší Tensor operace a obecné foreign shared-object ABI nejsou vydávány za hotové.

Licence: MIT, viz `LICENSE`.
