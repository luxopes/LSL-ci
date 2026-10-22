# Vývoj compileru LSL

Tento dokument je určený pro změny lexeru, parseru, linkeru, codegenu, runtime a
standardní knihovny. Uživatelský úvod je v [programming.md](programming.md) a
jazyková specifikace v [language.md](language.md).

## Rozsah 0.9.0 BETA a požadavky

Výchozí produkční cesta je **LSL frontend → LuxIR (vestavěný assembler
a linker) → statický Linux x86_64 PIE**. Frontend, samostatný LuxIR backend
i host runtime jsou napsané v LSL. Překlad ani spuštění zdroje přes veřejné
CLI nepotřebují binutils. Hotový program používá syscalls, bez libc
nebo dynamického interpreteru. Automatický fallback na C QBE není součástí
produkční cesty. Další OS a architektury tato BETA neslibuje.

Git a Python 3 slouží k přípravě připnutých závislostí a release auditům;
nejsou závislostí běhu hotových programů. Volitelný NVIDIA worker v `cuda/`
je explicitní foreign-process hranice. Každá změna musí zachovat:

1. funkční vícestupňový self-host frontendu i samostatného backendu;
2. bitově shodný fixed point obou překladačů;
3. deterministické pořadí kódu, dat, symbolů a diagnostiky;
4. statický PIE `ET_DYN`, segmenty bez RWX, neproveditelný `PT_GNU_STACK`,
   bez `PT_INTERP`, `DT_NEEDED` a textových relokací;
5. veřejný tagged Any ABI a bezpečnost raw-Int/live-pointer kolizí;
6. původní source path, řádek a sloupec v diagnostice.

Počet `PT_LOAD` a existence section headers či neaktivních dynamických
metadat nejsou převzaté požadavky původního přímého ELF writeru. Hardening
ověřuje nativní image gate; samotná podobnost starému binárnímu layoutu
nenahrazuje kontrolu spustitelného výsledku.

Buildy a výkonová měření provádějte sériově. Release nástroje používají limit
virtuální paměti 4 GiB a vnější timeouty; starší pokyny k limitům 1,5–2 GiB
nejsou současným release postupem. Výkonové vzorky nesmějí běžet souběžně
s regresními testy. GC hranice compileru nejsou stejné jako safepointy
emitované do cílových programů; změny jejich frekvence vyžadují ověření
paměťového tlaku i celého self-hostu.

## Mapa implementace

| Soubor | Odpovědnost |
|---|---|
| `compiler/pure/lexer.lsl` | UTF-8 tokenizace a source spans |
| `compiler/pure/parser.lsl` | AST a syntaktická diagnostika |
| `compiler/pure/linker.lsl` | rekurzivní moduly, namespace lowering |
| `compiler/pure/flow.lsl` | definite-assignment analýza a diagnostika E2002 |
| `compiler/pure/declarations.lsl` | lexikální typové deklarace a kontrola zápisů |
| `compiler/pure/frontend.lsl`, `semantic.lsl`, `validation.lsl` | společná příprava, typový tok a kontrola programu |
| `compiler/pure/qbe_emit.lsl` | lowering do LuxIR |
| `compiler/pure/qbe_toolchain.lsl` | LuxIR, GNU as/ld, finální obraz a úklid |
| `compiler/pure/qbe_runtime_dump.lsl` | sestavení nativního runtime objektu |
| `compiler/pure/codegen.lsl` | kompatibilní API původního přímého backendu |
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
| `compiler/pure/lslc_qbe.lsl` | výchozí nativní compiler entrypoint |
| `compiler/pure/lslc_direct.lsl` | kompatibilní přímý backend |
| `compiler/pure/package.lsl` | bezpečná instalace per-user zdrojových knihoven |
| `compiler/pure/catalog.lsl` | validovaný katalog a offline inventář knihoven |
| `compiler/pure/browser.lsl` | TUI správce balíčků a manuálu |
| `compiler/pure/manual.lsl` | seznam a načítání připnutých offline kapitol LSL-Web |
| `release.json`, `tools/release/prepare_sources.py` | připnutí LuxIR a export manuálů |
| `tools/release/build_release.py`, `verify_release.py` | reprodukce nástrojů a úplný preflight |
| `compiler/pure/console.lsl` | barvy pro TTY, NO_COLOR a sanitizace výpisů |
| `stdlib/` | veřejné staticky linkované moduly |
| `extensions/` | volitelné grafické knihovny, mimo základní instalaci |
| `tests/test_runner.lsl` | pure-LSL regression runner |

`compiler/pure/` je pouze produkční kód a generované release ELF. Všechny testy,
smoke drivery a fixtures patří do `tests/`.

Grafické zdroje v `extensions/` a publikované kopie v LSL-Packages musí být
shodné. Jejich raw operace mají explicitní `unsafe`; nelze jim přidělit
důvěru pouze podle názvu importu. Instalované LSL je hledá v uživatelském
adresáři po `lsl install NAME`, vývojový checkout v `extensions/`.

`tests/compiler/safe_codegen_conformance.lsl` nadále kontroluje instrukce
kompatibilního přímého backendu. Správnost `safe` v nativní produkční cestě
musí současně ověřit jazykové testy včetně
`tests/safe_recovery_conformance.lsl`; průchod starým codegen API není sám
o sobě důkazem pro LuxIR. Neodkládejte syntaktické a bezpečnostní kontroly
do runtime: převádějí se pouze podporované sémantické chyby výrazů.

## Pipeline

`lslc_qbe.lsl` a veřejná `pipeline.lsl` používají:

1. načtení zdroje, stdlib a explicitního bezpečnostního režimu;
2. parse a rekurzivní link modulů se stabilními prefixy;
3. tabulky funkcí/tříd, inference návratů a parametrů;
4. definite-assignment, deklarace a sémantické kontroly;
5. lowering analyzovaného programu do LuxIR pomocí `qbe_emit.lsl`;
6. optimalizace, výběr instrukcí a přidělení registrů v samostatném LuxIR;
7. assembler GNU `as`, následně GNU `ld` s `-nostdlib -static -pie`,
   bez dynamického loaderu, s vynuceným zákazem textových relokací;
8. načtení hotového obrazu, úklid privátních dočasných souborů a zápis výsledku.

`qbe_toolchain.lsl` hledá instalovaný `luxir` vedle compileru, při vývoji
`build/luxir/luxir`. `LSL_BACKEND` je explicitní absolutní override; chybějící
backend musí skončit chybou. Nativní runtime je připnutý objekt
`compiler/qbe/runtime.o`, v instalaci `lib/lsl/compiler/qbe/runtime.o`.
`lslc_direct.lsl` a samostatný objektový/image writer API zůstávají udržované
pro kompatibilitu a cílené starší testy.

AST jsou Dictionary/List hodnoty se `kind`, source spanem a fields konkrétního
uzlu. Linker zachovává `path`; codegen nesmí při syntetickém lowering zahodit
`line`, `column` ani `end_column`.

Linker cachuje moduly podle vyřešené cesty. Interní prefix je odvozený ze
stabilního pořadí grafu a používá oddělovač, který zdrojový identifikátor
nemůže obsahovat; dva relativní moduly stejného jména se proto neslijí.

Raw self-host ABI je explicitní provenance, ne vlastnost cesty. Pouze vstupy s
prvním řádkem `# lsl: internal-abi` mohou v nízkoúrovňovém driveru zapnout
interní trust režim; explicitní `--safe` jej odmítne. Veřejné run/compile CLI
libovolnému skriptu tímto řádkem oprávnění nepřiděluje;
linker jej zapíše do AST deklarací compiler trust core. Veřejné zdroje zůstávají
v tagged Any ABI i tehdy, když jejich cesta obsahuje `compiler/pure/`.

## Optimalizační model

Nativní cesta sdílí frontendové inference a lowering v LSL; další
optimalizace a register allocation provádí samostatný LuxIR. Typově doložené
skaláry mohou zůstat neboxované, dynamické hranice musí zachovat reprezentaci
Any a runtime chyby. Přesná pravidla se ověřují také Float/Any, callback,
kolizními a GC regresními testy.

Následující přehled popisuje optimalizace kompatibilního přímého backendu.
Jeho instrukční testy zůstávají užitečné, ale neprokazují stejné instrukce
v LuxIR výsledku:

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

Nativní x86_64 volání používají SysV registry `rdi`, `rsi`, `rdx`, `rcx`,
`r8`, `r9`, další argumenty na zásobníku a výsledek v `rax`. Registry uvnitř
uživatelských/LSL funkcí přiděluje LuxIR. Historický předpoklad přímého
backendu `rbx = runtime state` neplatí obecně pro přerušený LuxIR kód;
vláknový GC handler musí získat správný runtime state přes svůj runtime/TLS
kontrakt. Přesné offsety a volací adaptéry kontrolujte proti
`runtime_abi_linux_x86_64.lsl` a aktuálnímu runtime, nikoli proti starému
rozložení registrových lokálů.

Veřejné dynamické hranice boxují Int/Bool/None/Function; staticky známá lokální
aritmetika a trusted self-host cesta mohou držet raw skaláry. Heap type codes a
layout jsou v [`compiler/runtime-abi.md`](../compiler/runtime-abi.md). Tento
interní ABI není veřejné plugin ABI.

Codegen smí volit raw/public hranici jen z `internal_abi` pole deklarace.
Heuristika podle názvu souboru nebo adresáře je zakázaná; dovolila by obyčejné
cestě nechtěně vypnout veřejné runtime kontroly.

Kompatibilní přímý assembler používá rel32 call/jump fixups. Pokud jej měníte
nebo přidáváte branch relaxation,
musíte současně přemapovat label offsets, fixups i codegen data relocations;
pouhé odebrání bytes po emission poškodí RIP-relative String adresy.

## Typický vývojový cyklus

### 1. Minimální reprodukce

Nejdřív vytvořte malý zdroj pod `/tmp` a zapište očekávaný stdout/status. Pro
výkon uchovejte i checksum výsledku, aby benchmark neměřil odstraněnou práci.

### 2. Připnuté závislosti a stage build

```text
python3 tools/release/prepare_sources.py
python3 tools/release/build_release.py
```

Tyto dva kroky platí **pro Git checkout**. `release.json` připíná commity
LuxIR a LSL-Web. `prepare_sources.py` potřebuje Git metadata a síť;
pro lokální Git kopie přijímá `--luxir-checkout` a `--web-checkout`. Manuály
exportuje z připnutého webu do `build/manual-source` se souborem
`SOURCE.json`; `docs/developer_guides` je lokální pohled na tento export.
Webové stránky a jejich vývoj patří do samostatného projektu LSL-Web.

**Vydaný zdrojový archiv** už obsahuje přesný strom LuxIR v
`build/dependencies/LuxIR` bez `.git`, offline kapitoly jako skutečný adresář
`docs/developer_guides` včetně `SOURCE.json` a kanonické kopie runtime
`build/qbe/runtime.o` a backendu `build/luxir/luxir` bez symlinků.
Přípravný Git nástroj v něm nespouštějte. Reprodukce z rozbaleného archivu
nepotřebuje síť ani Git a začíná přímo:

```text
python3 tools/release/build_release.py
```

Build používá dodané nativní LSL bootstrap binárky a sestaví dvě další
generace frontendu i samostatného backendu. Fixed point ověřuje bajtově,
pak stejnou sestavou přegeneruje CLI, instalátor, config nástroj a test runner.
Report `build/release-build/build.json` zaznamená skutečné příkazy a hashe.
Samotný úspěch build skriptu nenahrazuje úplný release preflight.

Ruční frontendová reprodukce z kořene checkoutu:

```text
./compiler/lslc compiler/pure/lslc_qbe.lsl /tmp/lslc-next ./build/luxir/luxir
cmp compiler/lslc /tmp/lslc-next
```

Po změně nového runtime builtinu může být nutný samostatný kompatibilní
bootstrap krok. Takový krok musí uvést použitou stdlib a seed; nelze jej
zaměnit za finální self-host aktuálního zdrojového grafu. Překlad uchovává
source paths, takže fixed-point příkazy musí zachovat stejné relativní cesty
jako release build.

### 3. Cílené a úplné testy

```text
LUXIR_SOURCE="$PWD/build/dependencies/LuxIR/lsl/luxir.lsl" ./tests/lsl-test qbe ./compiler/lslc
./tests/lsl-test qbe-fast ./compiler/lslc
LUXIR_SOURCE="$PWD/build/dependencies/LuxIR/lsl/luxir.lsl" ./tests/lsl-test qbe-fixed-point ./compiler/lslc
python3 tools/release/verify_release.py --luxir-source build/dependencies/LuxIR/lsl/luxir.lsl --old-installer /cesta/k/lsl-0.8.9/bin/lsl-install
```

`qbe` je plný nativní režim; jméno je zachované kvůli kompatibilitě. `qbe-fast`
vynechá pozdější auditní kroky. `LUXIR_SOURCE` je povinný při vydání, protože
bez něj runner přeskočí fixed point samostatného backendu. Neoznačujte
částečný nebo post-aggregate diagnostický běh za kompletní corpus.

Pozitivní běžný corpus je agregovaný kvůli cold startu. Test, který potřebuje
vlastní proces, compile failure, resource fault, CLI stdin nebo quality limit,
přidejte samostatně do `tests/test_runner.lsl`. Každý deterministický program má
odpovídající `.out`. Nízkourovňové regresní fixtures mohou explicitně používat
`--unsafe`; veřejné CLI kontroly musí dál ověřovat bezpečný výchozí režim.

### 4. Release nástroje a instalace

`build_release.py` přegeneruje `compiler/pure/lslc-qbe`, `compiler/lslc`,
`compiler/pure/luxir`, CLI a další nástroje. Kopie frontendu musí být totožné;
stejně tak `compiler/pure/lsl-cli` a root `lsl`. Použijte až finální sestavu,
nikoli diagnostický compiler z jiné větve.

Preflight ověřuje úplný původní runner, nativní image a veřejné CLI gate,
registrované regrese i izolovanou migraci z předchozího instalátoru,
opakované reinstalace a rollbacky. Spravovaná instalační integrace potřebuje
bezpečný domovský rodičovský adresář, nikoli `/tmp`. Pracuje se soukromým HOME
a prefixem, nesmí přepsat běžnou instalaci vývojáře. Migrační gate má externí
předpoklad: funkční předchozí balík 0.8.9 s instalátorem, sousedními nástroji
a zdroji. Výchozí starý instalátor je `~/.local/bin/lsl-install`, alternativu
určuje `--old-installer`. Běžný self-host přes `build_release.py` ani plný
původní runner tuto starší instalaci nepotřebují. Bez ní lze provést
self-host a corpus; nelze poctivě prohlásit úplný migrační preflight za PASS.
Offline audit vyžaduje mít starší balík připravený předem, nic se nestahuje.

Strojová verze CLI a instalátoru je `0.9.0`; označení **BETA** je oddělené.
Updater přijímá kanonické `MAJOR.MINOR.PATCH` a health gate porovnává přesný
výstup `lsl version`. Prerelease v Gitea automaticky nezveřejňuje podepsaný
stabilní kanál. Test podepsaného finálního archivu je samostatný krok až po
přípravě jeho odpovídajícího manifestu a podpisu.

### 5. ELF a diagnostický audit

```text
readelf -W -l compiler/lslc
python3 tools/qbe/verify_image.py --compiler compiler/lslc --backend build/luxir/luxir --build-directory build/image-audit --report build/image-audit/verification.json
```

Ověřujte `ET_DYN`, žádný RWX segment, explicitní neproveditelný `GNU_STACK`,
žádný dynamický interpreter, závislost na libc ani textové relokace. Více
`LOAD` segmentů je přípustných. Nativní image gate kontroluje také ASLR,
source-entry, determinismus a úklid po chybě backendu.

Test runner vytváří vlastní `/tmp/lsl-test-PID[-N]` kořen. Fixture ani pomocný
compiler nesmí používat globální pevnou `/tmp/lsl-*` cestu; agregovanému
programu se kořen předává jako `arg(1)`. Při mismatchi zachovejte actual i
expected artefakt a uveďte první rozdílný byte. Výsledky vydání dokládají
konkrétní reporty a hashe; připravený skript není prohlášení o průchodu testů.

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

## Benchmarky a známé omezení 0.9.0 BETA

Měření LuxIR proti 0.8.9 ukázalo u velkého společného zdroje compileru
**11,399 s proti 8,062 s, tedy +41,4 % času překladu**. Tato regrese zůstává
otevřená pro **0.9.1**. Osm měřených výsledných programů bylo rychlejších;
nejde o důkaz univerzálního zrychlení ani vyřešení compile-time výkonu.
Vzorky, hashe a podmínky jsou v
[měření LuxIR](../tools/qbe/LUXIR_BENCHMARK_20261011.md).

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
