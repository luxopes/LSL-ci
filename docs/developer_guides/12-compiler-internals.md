# 12. Interní architektura compileru

Tato kapitola popisuje, jak LSL compiler funguje uvnitř — od zdrojového
kódu v `.lsl` souboru až po spustitelný ELF. Je určena pro ty, kteří
chtějí rozumět implementaci, přispívat do compileru nebo rozšiřovat
jazyk o nové vlastnosti.

## Proč rozumět compileru

I když píšete "jen" LSL programy, znalost toho, co compiler dělá, vám
pomůže psát výkonnější kód a lépe rozumět chybovým hláškám. Pokud chcete
přidat novou jazykovou vlastnost, tato kapitola vás provede celým
procesem.

## Filozofie a neměnné požadavky

Produkční toolchain je **pure LSL** — celý compiler je napsán v LSL a
překládá se sám sebou. V toolchainu nesmí být C/C++, Python, shell launcher,
externí assembler ani linker.

Každá změna musí zachovat:

1. **Funkční 2–3 stage self-host** — compiler musí být schopen přeložit
   sám sebe.
2. **Bitově shodný fixed point** — stage 2 a stage 3 musí být identické
   bit po bitu.
3. **Deterministické pořadí** — kódu, dat, symbolů a diagnostiky.
4. **Jeden RX `PT_LOAD`** — žádný `INTERP`, `DYNAMIC` ani RWX segment.
5. **Veřejný tagged Any ABI** — raw Int/live pointer collision bezpečnost.
6. **Původní source path, řádek a sloupec** — v diagnostice.

## Mapa zdrojových souborů

Produkční kód compileru je v `compiler/pure/`:

| Soubor | Odpovědnost |
|---|---|
| `lexer.lsl` | UTF-8 tokenizace, generování source spans |
| `parser.lsl` | Sestavení AST, syntaktická diagnostika |
| `linker.lsl` | Rekurzivní moduly, namespace lowering |
| `codegen.lsl` | Typový tok, optimalizace, native lowering |
| `x86_64.lsl` | Auditovatelný instrukční encoder |
| `assembler.lsl` | Labely, rel32 fixups, byte stream |
| `native_runtime.lsl` | Skalární runtime, clock_gettime a nanosleep emise |
| `heap_runtime.lsl` | Allokátor, registr, GC, kolekce |
| `io_runtime.lsl` | Soubory, argv/env, text/bin I/O, TTY/EOF stav |
| `process_runtime.lsl` | fork/execve/wait4/capture/status/streaming |
| `native_plugin_runtime.lsl` | Omezený ET_DYN loader ABI v1 |
| `elf_image.lsl` | Finální ELF64 image |
| `dynamic_stdlib.lsl` | LSL helper funkce připojené ke každému programu |
| `lslc_direct.lsl` | **Produkční compiler entrypoint** |
| `package.lsl` | Bezpečná instalace per-user zdrojových knihoven |

Vstupní bod compileru je `compiler/pure/lslc_direct.lsl`. CLI wrapper
(`compiler/pure/cli.lsl`) spouští compiler a přidává argument handling.

## Překladová pipeline

`lslc_direct.lsl` provede tuto sekvenci:

### 1. Načtení a parsování dynamic_stdlib.lsl

Standardní LSL helper funkce jsou připojeny ke každému programu.
`dynamic_stdlib.lsl` se parsuje jako první.

### 2. Parsování root source

Zdrojový kód se rozdělí na tokeny (`lexer.lsl`) a ty se složí do AST
(`parser.lsl`).

**Lexer** (lexikální analyzátor):
- Zpracovává UTF-8 vstup.
- Rozpoznává: klíčová slova, identifikátory, literály, operátory,
  oddělovače.
- Ke každému tokenu připojí **source span**: `path`, `line`, `column`,
  `end_column`.
- Ignoruje komentáře (od `#` do konce řádku) a whitespace.

**Parser** (syntaktický analyzátor):
- Sestavuje AST z tokenů.
- AST uzly jsou Dictionary/List hodnoty s polem `kind` (typ uzlu),
  source spanem a fields konkrétního uzlu.
- Provádí syntaktickou diagnostiku (ParseError).

### 3. Rekurzivní linkování modulů

`linker.lsl` rekurzivně zpracuje všechny `load` direktivy:

- Vyhledá soubor podle modulových pravidel.
- Parsuje ho.
- Rekurzivně zpracuje jeho `load` direktivy.
- Detekuje cyklické importy (compile-time chyba).
- Přidá deterministické namespace prefixy.

Linker zachovává `path` a `line`/`column`/`end_column` pro přesnou
diagnostiku.

### 4. Sestavení class/function tables

- Sestaví tabulku tříd (class definitions).
- Sestaví tabulku funkcí (function definitions).
- Provede fixed-point inference návratových typů.
- Projde všechny call sites a ověří signatury.

### 5. Konzervativní typová inference

`codegen.lsl` provádí konzervativní inference parametrů přímých
neunikajících funkcí:

- Sleduje, zda je funkce použita jako first-class callback.
- Pokud neuniká, analyzuje stabilní typy argumentů z call sites.
- Stabilní typy umožňují specializaci (neboxovaný fast path).

### 6. Optimalizace a x86_64 emission

**Constant/control-flow optimalizace**:

- Rekurzivní Int constant folding (s Int64 wrap sémantikou).
- Constant `if`/`while` pruning (zachování efektů dynamických podmínek).
- Ukončení emission za terminátorem (`return`, `break`, `continue`, `Error()`).
- Immediate `+`, `-`, `*`, compare a přímý flag branch.
- Power-of-two a magic-number signed floor division.
- Deduplikace immutable String templates.

**Bezpečnostní pravidla** (nikdy neporušit):

- Nezdvojovat ani nepřehazovat výraz, který může volat funkci, alokovat,
  provést I/O nebo vyvolat chybu.
- `x * 0` smí odstranit násobení, ale `x` se musí stále vyhodnotit.
- `//` a `%` musí zachovat floor sémantiku pro záporné hodnoty.
- Float folding nepoužívat (IEEE-754 komplikace).
- Raw Int může mít stejné bity jako živý heap pointer — na Any hranici
  se scalar tag nesmí odvodit jen z adresního rozsahu.

**x86_64 emission**:

`x86_64.lsl` produkuje auditovatelné instrukce s korektními sign-extensions
a kompaktními encodings.

### 7. Label/fixup materializace

`assembler.lsl` řeší:

- Labely (skoky vpřed i vzad).
- Rel32 call/jump fixups.
- Data reference fixups (RIP-relative String adresy).

### 8. Připojení literal dat

Deduplikované String literály se připojí za kód jako read-only data.

### 9. Vytvoření ELF image

`elf_image.lsl` vytvoří finální ELF64:

- Jeden RX `PT_LOAD` segment (read + execute).
- `PT_LOAD` offsety, virtuální adresy, filesz, memsz.
- Žádný `PT_INTERP`, `PT_DYNAMIC`, `PT_GNU_STACK` ani `PT_TLS`.
- Symbol table (volitelná, pro debug).
- Entry point.

Výstup se zapíše přes `writebytes`.

## Native ABI a registry

### Volací konvence

Volání je **SysV-like** (Linux x86\_64):

- Argumenty: `rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9`, další na stacku.
- Návratová hodnota: `rax`.

### Rezervované registry

| Registr | Význam |
|---|---|
| `rbx` | Allokátor/GC/process state |
| `r12` | Main/global frame (ukazatel na globální proměnné) |
| `r13` | Pending error String |
| `r14` | Pending error flag (0 = OK, ≠ 0 = error) |
| `r15` | Původní procesový stack (pro GC root scanning) |

### Boxovaný vs neboxovaný ABI

- **Veřejné dynamické hranice** (callbacky, Any) boxují Int/Bool/None/Function.
- **Staticky známá lokální aritmetika** a trusted self-host cesta mohou
  držet raw skaláry (Int64 přímo v registru, bez heap alokace).

## Garbage collector

GC je **konzervativní mark-sweep** s:

- **Stack roots**: skenování zásobníku od `r15` po aktuální `rsp`.
- **Global roots**: skenování globálního frame (`r12`).
- **Free-list**: recyklace uvolněných bloků pro rychlé `malloc`.
- **Mark fáze**: projde všechny dosažitelné objekty.
- **Sweep fáze**: uvolní nedosažitelné bloky do free-listu.

Heap typy:
- `type_code`: každý heap objekt má v hlavičce typový kód (String=1,
  List=2, Dictionary=3, Bool=4, None=5, Float=6, Tuple=7, RealArray=8, ...).
- GC traversal: každý typ má definovaná pravidla pro hledání pointerů
  (pro mark fázi).
- Ownership: GC rozhoduje, kdy objekt uvolnit.

## Self-host a fixed point

### Třístupňový build

```bash
ulimit -v 1048576

# Stage 1 — přeloží předchozí compiler
./compiler/pure/lslc-direct compiler/pure/lslc_direct.lsl /tmp/lslc-s1

# Stage 2 — přeloží nový compiler sám sebe
/tmp/lslc-s1 compiler/pure/lslc_direct.lsl /tmp/lslc-s2

# Stage 3 — ověření fixed pointu
/tmp/lslc-s2 compiler/pure/lslc_direct.lsl /tmp/lslc-s3

# Stage 2 a 3 musí být bitově shodné
cmp /tmp/lslc-s2 /tmp/lslc-s3
sha256sum /tmp/lslc-s1 /tmp/lslc-s2 /tmp/lslc-s3
```

Stage 1 se může lišit od stage 2 (emitoval ji předchozí compiler).
Stage 2 a 3 **musí** být identické — to je definice self-host fixed-pointu.

### Regenerace release nástrojů

Až po ověření fixed pointu se generují všechny tracked ELF:

```bash
# Compiler
/tmp/lslc-s3 compiler/pure/lslc_direct.lsl compiler/pure/lslc-direct
cp compiler/pure/lslc-direct compiler/lslc

# CLI wrapper
/tmp/lslc-s3 compiler/pure/cli.lsl compiler/pure/lsl-cli
cp compiler/pure/lsl-cli lsl

# Installer
/tmp/lslc-s3 compiler/pure/install.lsl compiler/pure/lsl-install

# Config evaluator
/tmp/lslc-s3 stdlib/configure.lsl compiler/pure/lsl-configure

# Test runner
/tmp/lslc-s3 tests/test_runner.lsl tests/lsl-test
```

## Jak přidat jazykovou vlastnost

Postup pro přidání nové jazykové vlastnosti:

### 1. Token (pokud potřeba)

Přidejte nový token do `lexer.lsl` pouze pokud stávající tokeny nestačí.
Token musí nést přesné `path`, `line`, `column`.

### 2. Parser

Parser musí pro novou syntaxi vytvořit stabilní AST uzel s:
- `kind` — jednoznačný identifikátor uzlu.
- Source span.
- Fields specifické pro daný uzel.

### 3. Linker

Linker musí rekurzivně přepsat nová name-bearing pole (pokud uzel
obsahuje odkazy na jména z jiných modulů).

### 4. Typová inference

Rozšiřte type inference v `codegen.lsl`. Nikdy tiše neoznačujte dynamickou
hodnotu jako scalar.

### 5. Lowering

Přidejte lowering (překlad do nižších konstrukcí) s runtime error cestou,
ne CPU trapem.

### 6. Testy

Přidejte:
- **Pozitivní test** — vlastnost funguje pro správný vstup.
- **Edge test** — hraniční případy (prázdné, minimální, maximální).
- **Negative test** — vlastnost správně hlásí chyby pro nesprávný vstup.

### 7. Dokumentace

Aktualizujte `docs/language.md` a uživatelský průvodce.

### 8. Fixed point

Spusťte třístupňový build a ověřte, že fixed point zůstal zachován.

### Nový builtin

Nový builtin navíc potřebuje:

- Diagnostiku nesprávného počtu argumentů.
- Statický návratový typ.
- Codegen větev (emise volání).
- Runtime implementaci.
- Test dynamického Any vstupu.

### Nový heap typ

Nový heap typ (např. nová kolekce) navíc potřebuje:

- `type_code` — unikátní kód v hlavičce.
- Registry zápis — jak se typ zapisuje do globálního registru.
- GC traversal pravidla — jak GC prochází pointery uvnitř objektu.
- Ownership pravidla.
- Stringovou reprezentaci (pro `print`/`String()`).
- Equality (pro `==`).
- Podporu v `type()`.
- Kolekční boxing.
- Runtime ABI dokumentaci.

## Testování

### Testovací runner

```text
./tests/lsl-test              # plný suite
./tests/lsl-test fast         # pozitivní conformance, bez auditních kroků
./tests/lsl-test fixed-point  # pouze bitová reprodukce compileru
```

### Struktura testů

- `tests/test_runner.lsl` — pure-LSL test runner.
- Pozitivní corpus — testy, které musí projít.
- Negative corpus — testy, které musí selhat s konkrétní chybou.
- Každý deterministický program má odpovídající `.out` soubor.

### Kompletní audit

Po každé změně:

```bash
# 1. Konfigurace
./lsl config examples/config/system.lsl > /tmp/config.json
cmp tests/config_expected.json /tmp/config.json

# 2. Instalace
./compiler/pure/lsl-install /tmp/lsl-prefix-new
/tmp/lsl-prefix-new/bin/lslc compiler/pure/lslc_direct.lsl /tmp/installed-fixed
cmp compiler/pure/lslc-direct /tmp/installed-fixed

# 3. ELF audit
readelf -W -l compiler/pure/lslc-direct
# Ověř: jeden LOAD, flags R E, žádný INTERP, DYNAMIC, RWE
```

## Runtime syscalls

Runtime používá přímo Linux syscalls (x86\_64: přes `syscall` instrukci):

- **I/O**: `read`, `write`, `open`, `close`, `lseek`, `access`
- **Paměť**: `brk` (heap), `mmap` (ET_DYN plugin)
- **Procesy**: `fork`, `execve`, `wait4`, `pipe`, `dup2`, `exit`
- **Souborový systém**: `readlink`, `mkdir`, `unlink`, `rename` (přes mv)
- **Čas**: `clock_gettime`, `nanosleep`
- **TTY**: `ioctl(TCGETS)` pro detekci terminálu

Žádné volání libc — runtime je plně soběstačný.

## Bezpečnostní model

Běžný programovací režim **není** sandbox. LSL program má plná práva
aktuálního procesu: může číst/zapisovat soubory, spouštět procesy,
měnit systémové balíčky.

Oddělený `lsl config` režim staticky odmítá ambientní I/O, síť,
environment a process capabilities — je to čistý evaluator pro
reprodukovatelnou konfiguraci.

## Kam dál

- [Jazyková specifikace](../language.md) — formální definice jazyka.
- [Compiler development](../compiler-development.md) — podrobný průvodce vývojem compileru.
- [Runtime ABI](../../compiler/runtime-abi.md) — interní ABI specifikace.
