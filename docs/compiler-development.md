# Vývoj compileru LSL

Tento dokument je určený pro změny lexeru, parseru, linkeru, codegenu, runtime a
standardní knihovny. Uživatelský úvod je v [programming.md](programming.md) a
jazyková specifikace v [language.md](language.md).

## Neměnné požadavky

Produkční compiler, host runtime a build/test toolchain jsou pure LSL a nesmí
získat C/C++, Python, shell launcher, externí assembler ani linker. Compiler
přímo zapisuje statický Linux x86_64 ELF a runtime používá syscalls. Volitelný
izolovaný NVIDIA worker v `cuda/` je výslovná foreign-process hranice a není
součástí self-host řetězce. Každá změna musí zachovat:

1. funkční 2–3stage self-host;
2. bitově shodný fixed point;
3. deterministické pořadí kódu, dat, symbolů a diagnostiky;
4. statický PIE `ET_DYN`, jediný RX `PT_LOAD`, explicitní RW
   `PT_GNU_STACK`, bez `INTERP`, `DYNAMIC` a RWX;
5. veřejný tagged Any ABI a raw-Int/live-pointer collision bezpečnost;
6. původní source path, řádek a sloupec v diagnostice.

Dlouhé fixed-point buildy compileru a běžné nástroje spouštějte sériově s
limitem 1,5 GiB:

```text
ulimit -v 1572864
```

Compiler i kořenové CLI při release buildu 0.6.8 dosahují přibližně 1,25 GiB
peak virtual/RSS kvůli skokovému růstu objektového registru. Generujte každý
artefakt samostatně; limit 1,5 GiB ponechává rezervu, ale stále ukončí
nekontrolovaný růst.

## Mapa implementace

| Soubor | Odpovědnost |
|---|---|
| `compiler/pure/lexer.lsl` | UTF-8 tokenizace a source spans |
| `compiler/pure/parser.lsl` | AST a syntaktická diagnostika |
| `compiler/pure/linker.lsl` | rekurzivní moduly, namespace lowering |
| `compiler/pure/codegen.lsl` | typový tok, optimalizace a native lowering |
| `compiler/pure/x86_64.lsl` | auditable instruction encoder |
| `compiler/pure/assembler.lsl` | labely, rel32 fixups, byte stream |
| `compiler/pure/native_runtime.lsl` | scalar runtime, clock_gettime a nanosleep emission |
| `compiler/pure/heap_runtime.lsl` | allocator, registry, GC, kolekce, SSE2 FloatArray kernely |
| `compiler/pure/thread_runtime.lsl` | futex mutexy, clone spawn/join, stop-the-world handler pro gc() |
| `compiler/pure/io_runtime.lsl` | soubory, argv/env, text/binární I/O a TTY/EOF stav |
| `compiler/pure/process_runtime.lsl` | fork/exec/capture/status/streaming |
| `compiler/pure/native_plugin_runtime.lsl` | omezený ET_DYN loader ABI v1 |
| `compiler/pure/elf_image.lsl` | finální ELF64 image |
| `compiler/pure/dynamic_stdlib.lsl` | LSL helper funkce připojené ke každému programu |
| `compiler/pure/lslc_direct.lsl` | produkční compiler entrypoint |
| `compiler/pure/package.lsl` | bezpečná instalace per-user zdrojových knihoven |
| `stdlib/` | veřejné staticky linkované moduly |
| `tests/test_runner.lsl` | pure-LSL regression runner |

`compiler/pure/` je pouze produkční kód a generované release ELF. Všechny testy,
smoke drivery a fixtures patří do `tests/`.

## Pipeline

`lslc_direct.lsl` provede:

1. načtení a parse `dynamic_stdlib.lsl`;
2. parse root source;
3. rekurzivní link modulů a přidání stabilních prefixů;
4. sestavení class/function tables a fixed-point inference návratů;
5. konzervativní inference parametrů přímých neunikajících funkcí;
6. constant/control-flow optimalizace a x86_64 emission;
7. label/fixup materializaci;
8. připojení deduplikovaných literal dat;
9. přímé vytvoření ELF image a `writebytes`.

AST jsou Dictionary/List hodnoty se `kind`, source spanem a fields konkrétního
uzlu. Linker zachovává `path`; codegen nesmí při syntetickém lowering zahodit
`line`, `column` ani `end_column`.

## Optimalizační model

Optimalizace jsou záměrně konzervativní a probíhají v codegenu, aby nevznikl
druhý neauditovatelný IR. Aktuální vrstvy:

- rekurzivní Int constant folding s Int64 wrap sémantikou;
- constant `if`/`while` pruning při zachování efektů dynamických podmínek;
- ukončení emission/variable/type/return scan za terminátorem;
- immediate `+`, `-`, `*`, compare a přímý flag branch;
- přímá equality pouze pro shodné statické `Int`/`Bool`/`None` typy;
- přímé flag větvení celých short-circuit stromů `and`/`or`/`not` bez
  materializace dočasných Bool hodnot;
- přímé předání prvního argumentu a 32bytové zarovnání vstupů funkcí;
- lokální hoisting datového ukazatele opakovaného `IntArray` v čistém výrazu;
- přímý read-modify-write pro unchecked složené přiřazení `IntArray`;
- power-of-two a magic-number signed floor division;
- konstantní posuny složené při překladu, jinak immediate `shl`/`sar`;
- deduplikované immutable String templates, ale nový runtime String clone;
- typová specializace přímých funkcí pouze pokud funkce neuniká jako callback a
  program nepoužívá dynamickou introspekční hranici;
- kompaktní, signed-correct x86 MOV/imm/disp/prologue encodings.

### Bezpečnostní pravidla optimalizací

- Nikdy nezdvojujte ani nepřehazujte výraz, který může volat funkci, alokovat,
  provést I/O nebo vyvolat chybu.
- `# lsl: unchecked-intarray` je explicitní unsafe opt-in pro celý root source.
  Bez něj musí každý typovaný `IntArray` přístup zachovat normalizaci záporného
  indexu a `IndexError`; s ním smí validitu indexů předpokládat pouze program.
- `x * 0` smí odstranit násobení, ale `x` se musí stále jednou vyhodnotit.
- `//` a `%` musí zachovat floor sémantiku pro záporné hodnoty a zvláštní
  `INT64_MIN // -1` wrap případ.
- Float folding nepoužívejte bez bitově shodné IEEE-754 strategie včetně NaN,
  Infinity, signed zero a subnormal hodnot.
- Raw Int může mít stejné bity jako živý heap pointer. Na Any/callback/collection
  hranici se scalar tag nesmí odvodit pouze z adresního rozsahu.
- Funkce použitá jako first-class hodnota musí zachovat veřejný boxed ABI.
- Kratší x86 immediate je korektní jen tehdy, když jeho sign/zero extension dává
  přesně původní 64bit hodnotu.

`tests/codegen_optimization_conformance.lsl` kontroluje výsledky i maximální
velikost standalone ELF. `tests/pointer_collision_conformance.lsl` je povinný
regresní test pro každou změnu typové specializace nebo boxingu.

## Native ABI a registry

Volání je SysV-like: `rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9`, další argumenty na
stacku, výsledek v `rax`. Rezervované hodnoty:

- `rbx` — allocator/GC/process state;
- `r12` — main/global frame;
- `r13` — pending error String;
- `r14` — pending error flag;
- `r15` — původní process stack.

Veřejné dynamické hranice boxují Int/Bool/None/Function; staticky známá lokální
aritmetika a trusted self-host cesta mohou držet raw skaláry. Heap type codes a
layout jsou v [`compiler/runtime-abi.md`](../compiler/runtime-abi.md). Tento
interní ABI není veřejné plugin ABI.

Assembler dnes používá rel32 call/jump fixups. Pokud přidáte branch relaxation,
musíte současně přemapovat label offsets, fixups i codegen data relocations;
pouhé odebrání bytes po emission poškodí RIP-relative String adresy.

## Typický vývojový cyklus

### 1. Minimální reprodukce

Nejdřív vytvořte malý zdroj pod `/tmp` a zapište očekávaný stdout/status. Pro
výkon uchovejte i checksum výsledku, aby benchmark neměřil odstraněnou práci.

### 2. Stage build

```text
ulimit -v 1048576
./compiler/pure/lslc-direct compiler/pure/lslc_direct.lsl /tmp/lslc-s1
/tmp/lslc-s1 compiler/pure/lslc_direct.lsl /tmp/lslc-s2
/tmp/lslc-s2 compiler/pure/lslc_direct.lsl /tmp/lslc-s3
sha256sum /tmp/lslc-s1 /tmp/lslc-s2 /tmp/lslc-s3
cmp /tmp/lslc-s2 /tmp/lslc-s3
```

Stage 1 se může lišit, protože jej emitoval předchozí compiler. Stage 2 a 3 se
musí shodovat bit po bitu.

### 3. Cílené a úplné testy

```text
/tmp/lslc-s3 tests/test_runner.lsl /tmp/lsl-test-next
/tmp/lsl-test-next /tmp/lslc-s3
/tmp/lsl-test-next fixed-point /tmp/lslc-s3
```

Režimy veřejného runneru:

```text
./tests/lsl-test fast
./tests/lsl-test full
./tests/lsl-test fixed-point
```

Pozitivní běžný corpus je agregovaný kvůli cold startu. Test, který potřebuje
vlastní proces, compile failure, resource fault, CLI stdin nebo quality limit,
přidejte samostatně do `tests/test_runner.lsl`. Každý deterministický program má
odpovídající `.out`.

### 4. Regenerace release nástrojů

Až po fixed pointu generujte všechny tracked ELF stejným stage-3 compilerem:

```text
/tmp/lslc-s3 compiler/pure/lslc_direct.lsl compiler/pure/lslc-direct
cp compiler/pure/lslc-direct compiler/lslc
/tmp/lslc-s3 compiler/pure/cli.lsl compiler/pure/lsl-cli
cp compiler/pure/lsl-cli lsl
/tmp/lslc-s3 compiler/pure/install.lsl compiler/pure/lsl-install
/tmp/lslc-s3 stdlib/configure.lsl compiler/pure/lsl-configure
/tmp/lslc-s3 tests/test_runner.lsl tests/lsl-test
```

`compiler/pure/lslc-direct` musí být identický s `compiler/lslc` a
`compiler/pure/lsl-cli` s root `lsl`.

### 5. Config, installer a ELF audit

```text
./lsl config examples/config/system.lsl > /tmp/config.json
cmp tests/config_expected.json /tmp/config.json
./compiler/pure/lsl-install /tmp/lsl-prefix-new
/tmp/lsl-prefix-new/bin/lslc compiler/pure/lslc_direct.lsl /tmp/installed-fixed
cmp compiler/pure/lslc-direct /tmp/installed-fixed
readelf -W -l compiler/pure/lslc-direct
```

Použijte nový neexistující install prefix. Auditujte všechny tracked ELF:
`ET_DYN`, právě jeden `LOAD` s nulovou virtuální bází a flags `R E`, jeden RW
`GNU_STACK`, žádný `INTERP`, `DYNAMIC` ani `RWE`. Spuštěním stejného ELF vícekrát
a kontrolou `/proc/$pid/maps` ověřte měnící se load bias.

Test runner vytváří vlastní `/tmp/lsl-test-PID[-N]` kořen. Fixture ani pomocný
compiler nesmí používat globální pevnou `/tmp/lsl-*` cestu; agregovanému
programu se kořen předává jako `arg(1)`. Při mismatchi zachovejte actual i
expected artefakt a uveďte první rozdílný byte.

## Jak přidat jazykovou vlastnost

1. Přidejte token pouze pokud stávající tokeny nestačí.
2. Parser musí vytvořit stabilní AST a přesný span.
3. Linker musí rekurzivně přepsat nové name-bearing fields.
4. Rozšiřte type inference bez tichého označení dynamické hodnoty jako scalar.
5. Přidejte lowering s runtime error cestou, ne CPU trapem.
6. Přidejte pozitivní, edge a negative test.
7. Aktualizujte `docs/language.md` a uživatelský průvodce.
8. Proveďte fixed point a celý audit.

Nový builtin navíc potřebuje arity diagnostiku, statický návratový typ, codegen
větev, runtime implementaci a test dynamického Any vstupu. Nový heap typ potřebuje
type code, registry zápis, GC traversal/ownership pravidla, rendering, equality,
`type()`, kolekční boxing a runtime ABI dokumentaci.

## Benchmarky

Měřte před i po na stejném stroji, sériově a s identickým výstupem. Reportujte:

- medián alespoň pěti běhů;
- compile wall time a peak RSS;
- velikost ELF;
- runtime wall time a peak RSS;
- vstupní rozměr a checksum/stdout;
- přesný compiler hash.

Oddělte compiler cold start od runtime. Pro numeriku porovnávejte jak scalar
LSL zápis, tak typed-array bulk kernel. Experiment, který nezlepší měřený hot
path nebo poruší fixed point, neudržujte jen proto, že vypadá obecněji.
