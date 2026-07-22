# LSL completion handoff

## Goal

Dokončit produkční LSL 0.7 tak, aby udržovaná implementace obsahovala pouze LSL
zdroje a LSL-generované Linux x86_64 ELF soubory. Compiler musí přímo generovat
statický syscall-only ELF bez C/C++, libc, assembleru, linkeru, Pythonu nebo
shell launcheru a musí reprodukovat sám sebe bit po bitu.

Tento soubor je stručný zdroj pravdy pro pokračování po ztrátě/kompakci
kontextu. Historie hashů a důkazů je v `PURE_LSL_PROGRESS.md`; veřejný seznam je
v `TODO.md`.

## Aktuální Git stav

- Repo: `/home/antonin/lsl`
- Větev: `complete-roadmap`
- Base větev: `master`
- Poslední commit: `e3ddd0b Pass wide class initializers on the stack`
- Pracovní strom byl při vytvoření tohoto souboru čistý.
- Aktuální fixed-point compiler SHA-256:
  `a147d1366d6528103e6bffe486eea467e917ca513494dfb4513c7983094b1dd7`
- `compiler/pure/lslc-direct` je bitově shodný s `compiler/lslc`.
- `compiler/pure/lsl-cli` je bitově shodný s top-level `lsl`.
- ELF má jediný RX `PT_LOAD`, žádný `INTERP` a žádné RWX.
- Ve stromu nejsou `.c`, `.h`, `.py` ani `.sh` produkční soubory.

Před každou změnou:

```text
git status --short --branch
git log -5 --oneline
```

Používat jednu logickou změnu na commit. Před commitem vždy `git diff`,
`git diff --check`, explicitní `git add <files>` a kontrola staged diffu. Nic
nepushovat bez výslovného požadavku.

## Tvrdé provozní podmínky

- Dlouhé kroky pouze sériově, nikdy paralelně.
- Před buildem používat `ulimit -v 1048576`.
- Nepoužívat C/Python/assembler/linker ani jako dočasný backend.
- Síť nespouštět bez výslovného požadavku.
- Starý transition host/seed je odstraněn a nesmí se obnovovat.
- Neoznačovat částečnou implementaci za hotovou.
- Každý compiler/runtime zásah: conformance test → 2 až 3 self-host stage →
  SHA/cmp → deterministická regenerace nástrojů → celý suite → config.

## Co je ověřeně hotové

- Pure-LSL lexer/parser/linker/x86_64 encoder/ELF writer/runtime/compiler.
- Self-host fixed point, veřejné ELF launchery, installer a pure test runner.
- UTF-8 code-point String operace, Unicode case map alespoň Latin-1/Extended-A.
- Int/Bool/None/boxed Float, List/Tuple/RealArray/Dictionary, deep equality.
- Funkce, recursion, callbacks, classes, široké register/stack ABI, exceptions.
- Modules, private/public classes, přesné linked-module diagnostics.
- JSON, config evaluator, env, filesystem, process, neomezený `capture`, HTTP
  přes bezpečný curl argv a JSON process plugin ABI.
- Mark-sweep cycle GC a free-list reuse.
- Float NaN/Infinity, comparisons, power, floor division/modulo a round-trip
  textový formatter.
- Dokumentované collection/String metody, Dictionary conversion, member delete.
- Dynamický `rang` step, indexed augmented assignment, neomezený line `input`.
- Aktuální `compiler/pure/lsl-test` a config conformance jsou zelené.

Nedávné commity na větvi:

```text
ccd1e5c Support indexed augmented assignment
7a750a4 Allow dynamic rang steps
fe45de4 Format Floats as round-trip decimals
7bd31e9 Complete documented collection methods
c5e125a Support deleting instance fields
e187ccc Read unbounded input lines
17b0d78 Grow capture output without a fixed limit
e3ddd0b Pass wide class initializers on the stack
```

## Zbývající blokery — v pořadí

### 1. Jednoznačný dynamic scalar tag ABI (hlavní blocker)

Současný stav:

- Heap pointery se rozpoznávají přes exact open-addressed allocation registry.
- Bool/None jsou v collections boxované, Float je heap objekt.
- Dynamický Int je stále často raw 64bit hodnota.
- Pokud raw Int bits přesně odpovídají adrese živého heap objektu, generic
  `is_heap/type/equality/render/arithmetic` jej může chybně považovat za objekt.
- Raw Bool 0/1 versus raw Int 0/1 způsobuje obdobné chyby přes Any parametry;
  například statické cesty jsou opravené, ale jednotný ABI ještě neexistuje.

Doporučený návrh: **boxed dynamic ABI, unboxed typed fast path**.

- Staticky inferovaný Int/Bool může zůstat raw pouze uvnitř typed výrazu.
- Každá hodnota ukládaná do Any slotu, collection slotu, Dictionary key/value,
  Any parametru nebo Any return musí mít jednoznačný runtime tag.
- Přidat heap type `9 = boxed Int`; stávající 4/5/6 jsou Bool/None/Float.
- Function hodnoty musí mít vlastní box/tag, pokud přecházejí přes Any.
- Přidat `runtime_box_int`, `runtime_unbox_int`, generic scalar classifier a
  checked unbox helpers.
- Přepsat generic add/sub/mul/div/mod/pow/compare/equal/truth/print/render,
  indexing a konverze tak, aby nikdy neinterpretovaly raw bits jako pointer.
- `runtime_type_code` musí pro boxed Int veřejně hlásit Int, ale interně musí být
  možné tag 9 rozlišit.
- Codegen musí boxovat na každé typed→Any hranici a unboxovat Any→typed hranici.
- GC musí boxed Int považovat za leaf.
- Až poté lze odstranit teoretickou kolizi a případně zmenšit/změnit pointer
  registry; registry je stále užitečná pro GC, ale nesmí určovat jazykový typ.

Bezpečné migrační fáze:

1. Přidat type 9 a runtime helpers, zatím je nepoužívat; fixed point + commit.
2. Naučit všechny generic runtime operace přijmout raw i boxed Int; test + commit.
3. Boxovat Int v collections/dictionary, opravit JSON/render/index; test + commit.
4. Boxovat scalar argumenty/returns na Any ABI hranicích; test + commit.
5. Boxovat Function/Bool/None konzistentně, odstranit raw fallback heuristiky.
6. Přidat test-only/internal způsob vytvořit hodnotu se stejnými bits jako heap
   adresa a dokázat, že je stále Int; potom označit okruh hotový.

Rizika:

- Compiler je sám velký dynamický LSL program; změna parametrického ABI snadno
  rozbije bootstrap. Každá fáze musí zachovat přechodový dual-mode runtime.
- `bytes.little`, encoder a magic division spoléhají na raw/wrapping Int fast
  path; nesmí být omylem boxovány uprostřed typed aritmetiky.
- Dictionary hash/equality, JSON a loops jsou citlivé na boxování.

### 2. Integer overflow politika

Současný Int je signed 64-bit a většina operací wrapuje. `INT64_MIN // -1` je
explicitně ošetřen bez CPU pádu. TODO ale stále žádá kontrolovaný overflow.

Je nutné rozhodnout a zdokumentovat jednu sémantiku:

A. Oficiální two's-complement wrapping Int (jednodušší, vhodné pro compiler),
nebo
B. User operace vyvolají `OverflowError`, interní compiler používá explicitní
`__lsl_wrap_add/sub/mul/pow` intrinsic.

Pokud B:

- přidat x86 overflow branch (`jo`) pro user +, -, *, power;
- předem převést compiler internals, které záměrně wrapují;
- doplnit literal range validation a conformance pro min/max hranice;
- teprve potom měnit běžný codegen, jinak se rozbije self-host determinismus.

### 3. In-process native/shared-object/tensor ABI

Hotové je pouze izolované JSON process plugin ABI. Není hotové zero-copy.

Minimální čistý v1 scope:

- pure-LSL loader pro omezený self-contained ET_DYN/LSL plugin formát;
- syscall `mmap`/`munmap`, validace ELF headerů a bounds;
- povolit jen jasně definované relocations (nejprve `R_X86_64_RELATIVE`);
- najít verzovaný descriptor/symbol bez libc/dlopen;
- intrinsic pro bezpečné volání function pointeru přes explicitní ABI;
- opaque Native/Tensor handle s owner/destructor tagem;
- dtype, rank, shape, strides, byte length, CPU pointer a explicitní lifetime;
- žádný plugin nesmí vidět interní LSL heap layout;
- negative testy: malformed ELF, wrong machine/version, bad relocation,
  ABI mismatch, use-after-close, double close;
- potom teprve async/device/GPU event rozšíření.

Nevydávat process JSON ABI za zero-copy řešení.

### 4. GC/allocator robustnost

- Object registry má pevnou kapacitu; při zaplnění hrozí nekonečný probe.
- String-template intern table je také pevná.
- `brk`/alokace nemají úplnou strukturovanou OOM cestu.
- Doplnit dynamický růst nebo alespoň detekci zaplnění a deterministický error.
- Přidat stress testy milionů objektů, cyklů, reuse a hlubokých grafů.
- Změřit a případně snížit virtuální rezervaci každého programu.

### 5. Process/I/O error parity

- `capture()` už roste, ale API vrací jen stdout String, ne exit status/stderr.
- Navrhnout `capture_result` Dictionary `{stdout, stderr, status}` nebo podobné.
- Ošetřit všechny syscall error/partial paths (`pipe`, `fork`, `dup2`, `wait4`,
  `close`, read errors), ne pouze hlavní happy path.
- Přidat čistý stdin-fed process helper; pak zapojit `input_conformance` přímo do
  pure `lsl-test` (nyní je 5000B input ověřen manuálním pipe testem).

### 6. AI/config produkční rozšíření

AI:

- streaming response, cancellation, strukturované transport errors/retry;
- zero-copy tensor/model API závisí na bodu 3;
- rozhodnout, zda externí `/usr/bin/curl` zůstává podporovaná boundary, nebo je
  požadován pure syscall TCP/TLS stack (TLS je samostatný velký projekt).

Config:

- lazy dependency/cycle diagnostics;
- bohatší option schemas/types a source provenance konfliktů;
- případná activation/service/package vrstva, pokud má LSL přímo spravovat OS.

Nejdřív zkontrolovat cílový scope v `docs/configuration.md`; nedoplňovat
spekulativní API bez testovatelné specifikace.

### 7. Validace, audit, cleanup

- Deterministický pure-LSL parser/JSON/config fuzz runner a negative corpus.
- GC/memory stress a benchmark regressions.
- Audit trust-root ELF a reprodukce v čistém Linux x86_64 prostředí.
- Linux x86_64 je definovaný první/aktuální target; další target není blocker
  0.7, dokud se explicitně nerozšíří scope.
- Sjednotit dokumentaci s implementací.
- Odstranit nepotřebné smoke zdroje a zkrátit historické transition poznámky až
  po dokončení blockerů; nemaž diagnostické/conformance důkazy předčasně.

## Přesný následující krok

Začít **fází 1 tagged ABI** bez změny chování:

Fáze 1 je hotová: heap type 9, `runtime_box_int`/`runtime_unbox_int`,
intrinsics, GC leaf chování a edge-value round trip.

Fáze 2 je hotová ve fixed pointu
`4af21a1d72cbe2d53338e7ba06bf41d82def309524f283fcab5b02a1eb910277`.
Generic truth/equal/compare/add/sub/mul/div/mod/pow/abs/neg, mixed Float
promotion, print/render/JSON/conversions, sequence indexing, `chr` a `rang`
přijímají raw i boxed Int. Samostatný conformance pokrývá tyto operace včetně
RealArray, sum/min/max a GC; typed raw Int fast path zůstává zachován.

Fáze 3 je hotová ve fixed pointu
`1b529bd1e2ac92b6399170969f0d8c81fdccea2cdea38b9837fa7a35a2311333`.
Staticky známé Int hodnoty se boxují v List/Tuple/RealArray, Dictionary values a
instance fields včetně append/insert/setdefault/indexed/member assignment.
Augmented assignment retaguje raw numerický výsledek. `type(Any)` používá
runtime classifier a config chápe type 9 jako Int. Compiler fixed point vyžadoval
explicitní Int konverzi interních register tabulek a writebytes unbox; nyní jsou
všechny stage opět bitově shodné. Conformance ověřuje 0/1, min/max, mutace,
JSON, Tuple, RealArray a Dictionary.

Fáze 4a je hotová ve fixed pointu
`b939f8c171dc086ff3794fdda5f2a163468097c23eed223c5f4414c6b42cbbd3`.
Staticky známé Int/Bool/None argumenty se boxují před direct, indirect, method a
initializer callem, v registrech i na stacku. Compiler self-hostuje i s tagged
parametry; `%`/`//` dispatch byl rozšířen na jeden Any operand. Conformance
ověřuje identity return, min/max Int, Bool/None a class initializer/method.

Následuje fáze 4b — dokončení Any function ABI:

1. Přidat tagged Function heap type 10 s box/unbox helperem; indirect call musí
   přijmout raw i type-10 callable. Generic truth/equality/type/render musí type
   10 znát a GC jej bere jako leaf.
2. Na Any argument hranici otagovat i výraz inferovaný `Any`. Již heap/tagged
   hodnotu zachovat; raw numerický výsledek boxovat jako Int. Díky type 10 nesmí
   být Function pointer zaměněn za Int.
3. Na `return` hranici tagovat staticky známé Int/Bool/None/Function a raw
   numerické Any výsledky. Call site se staticky typed očekáváním musí případně
   explicitně unboxnout; Any call výsledek zůstane tagged.
4. Přidat recursion/callback/select-callback tests a identity kolem raw výsledku
   `sum`, aritmetiky a 0; vložit všechny return hodnoty do collections.
5. Po fixed pointu odstranit raw scalar fallback z generic runtime classifieru
   a přidat důkaz proti raw-Int/live-pointer kolizi.

## Standardní ověřovací příkazy

Spouštět sériově:

```text
cd /home/antonin/lsl
ulimit -v 1048576
./compiler/pure/lslc-direct compiler/pure/lslc_direct.lsl /tmp/lslc-1
/tmp/lslc-1 compiler/pure/lslc_direct.lsl /tmp/lslc-2
/tmp/lslc-2 compiler/pure/lslc_direct.lsl /tmp/lslc-3
sha256sum /tmp/lslc-1 /tmp/lslc-2 /tmp/lslc-3
cmp /tmp/lslc-2 /tmp/lslc-3
```

Po ověřeném fixed pointu zkopírovat stage 3 do
`compiler/pure/lslc-direct` a `compiler/lslc`, pak každý nástroj generovat 2× a
porovnat před nahrazením:

```text
./compiler/pure/lslc-direct compiler/pure/cli.lsl /tmp/lsl-cli-a
./compiler/pure/lslc-direct compiler/pure/cli.lsl /tmp/lsl-cli-b
cmp /tmp/lsl-cli-a /tmp/lsl-cli-b

./compiler/pure/lslc-direct stdlib/configure.lsl /tmp/lsl-configure-a
./compiler/pure/lslc-direct stdlib/configure.lsl /tmp/lsl-configure-b
cmp /tmp/lsl-configure-a /tmp/lsl-configure-b

./compiler/pure/lslc-direct compiler/pure/test_runner.lsl /tmp/lsl-test-a
./compiler/pure/lslc-direct compiler/pure/test_runner.lsl /tmp/lsl-test-b
cmp /tmp/lsl-test-a /tmp/lsl-test-b

./compiler/pure/lslc-direct compiler/pure/install.lsl /tmp/lsl-install-a
./compiler/pure/lslc-direct compiler/pure/install.lsl /tmp/lsl-install-b
cmp /tmp/lsl-install-a /tmp/lsl-install-b
```

Nakonec:

```text
./compiler/pure/lsl-test
./lsl config examples/config/system.lsl > /tmp/config.out
cmp tests/config_expected.json /tmp/config.out
cmp compiler/pure/lslc-direct compiler/lslc
cmp compiler/pure/lsl-cli lsl
readelf -l compiler/pure/lslc-direct
find . -type f \( -name '*.c' -o -name '*.h' -o -name '*.py' -o -name '*.sh' \)
```

## Důležité gotchas

- Source změna runtime labelu často vyžaduje přechodovou stage: první nový
  compiler může mít starý vlastní runtime, ale už generuje nový runtime. Fixed
  point typicky nastane až stage 2/3.
- Při novém intrinsic může být nutný dvoufázový bootstrap: nejprve naučit
  codegen intrinsic rozpoznat, vytvořit fixed point, až potom jej použít v
  `dynamic_stdlib.lsl`.
- `Error` propagation musí uklidit stack argumenty před skokem do handleru.
- Float parser/formatter je self-host součást; změna očekávaného tisku mění více
  `.out` souborů záměrně.
- Pure test runner tiskne diagnostiku očekávaných negative compile testů; status
  0 a poslední `pure LSL tests passed` je rozhodující.
- Git generované ELF soubory jsou zde záměrné trust-root/release artefakty a
  musí být commitnuty spolu se zdrojem po deterministické regeneraci.
