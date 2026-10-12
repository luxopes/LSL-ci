# Lux Simple Lang (LSL)

**LSL 0.9.2** je stabilní self-hostované vydání pro **Linux x86_64**. Frontend,
backend LuxIR i host runtime jsou napsané v LSL. Výchozí překlad vede přes
analyzovaný AST a LuxIR do assembleru; **GNU `as` a `ld` z balíku binutils**
vytvoří statický PIE ELF. Výsledné programy používají přímé syscalls a nepotřebují
libc ani dynamický loader. Binutils jsou potřeba také pro `lsl program.lsl`,
protože CLI zdroj nejprve přeloží. Už zkompilovaný program je nepotřebuje.

Volitelný NVIDIA worker `cuda/lsl-cuda-worker` je samostatný proces napsaný
v CUDA C++; bez něj Tensor používá CPU fallback. Podpora dalších architektur
nebo OS není součástí tohoto vydání.

## Self-hosted vydání

Od 0.9.0 nahrazuje přímý AST backend samostatný nativní
[LuxIR](https://git.lux-ai.cz/LuxAI/LuxIR). Běžné CLI i `compiler/lslc`
používají tuto cestu s bezpečným výchozím režimem. Privilegované operace
vyžadují `unsafe:` nebo explicitní `--unsafe`.

0.9.1 přidává přiřazení více proměnným (`a, b = 1`, `x, y = y, x`),
rozbalení ve `for`, `global`, blok `lock`, raw řetězce, blokové komentáře,
`printr`, `split()` bez argumentu, `math.round/trunc` s počtem míst, ISO-8601
v `time`, streamovaný `httpserver` a běhové chyby ve formátu diagnostiky.
Úplný seznam je v [changelogu](https://lsl.lux-ai.cz/#CHANGELOG).

0.9.2 opravuje všech 34 nálezů auditu 0.9.1: správně zaokrouhlený převod
textu na Float, numerické hranice v `math`, ochranu protokolu v `httpserver`
(a nový worker pool), čistotu a lexer konfigurace a lineární práci se Stringy.
Podrobnosti jsou v `docs/release-0.9.2.md`.

**Známé omezení:** překlad velkého společného zdroje compileru
v měření na stejném stroji trval **11,399 s proti 8,062 s u 0.8.9**, tedy
**o 41,4 % déle**. Rychlejší výsledné programy v osmi měřených úlohách tuto
regresi času překladu neodstraňují. Podrobnosti a reprodukovatelná data jsou
v [benchmarku LuxIR proti 0.8.9](tools/qbe/LUXIR_BENCHMARK_20261011.md).

Vydání si ponechává `.env` vedle skriptu, `requests` a offline manuály
standardních knihoven. Proměnné prostředí mají před `.env` přednost;
hodnoty ze souboru se čtou za běhu a nevkládají se do binárky.

Strojový výstup `lsl version` je `0.9.2`. Příkaz `lsl update` sleduje
podepsaný stabilní kanál.
Web a manuály mají samostatný projekt
[LSL-Web](https://git.lux-ai.cz/LuxAI/LSL-Web); veřejná dokumentace je na
[lsl.lux-ai.cz](https://lsl.lux-ai.cz/).
Starší manuály jsou v [historii vydání](https://lsl.lux-ai.cz/releases/):

- LSL 0.9.2 — opravy všech nálezů auditu 0.9.1, přesný převod Float, worker pool pro httpserver;
- [LSL 0.9.1](https://git.lux-ai.cz/LuxAI/LSL/releases/tag/v0.9.1) — stabilní vydání LuxIR pipeline, nové jazykové konstrukce, streamovaný HTTP server a čitelné běhové chyby;
- [LSL 0.9.0 BETA](https://git.lux-ai.cz/LuxAI/LSL/releases/tag/v0.9.0-beta.1) — nový nativní backend LuxIR v LSL, oddělený frontend a ověřený self-host; Linux x86_64;
- LSL 0.8.9 — `.env`, `requests` a manuály knihoven;
- LSL 0.8.8 — bufferovaný stdin/stdout, rezerva haldy, nativní `split` a `Int`, oprava typů proměnných a diagnostika comprehension;
- LSL 0.8.7 — `rang` jako hodnota a `List.find`;
- LSL 0.8.6 — hromadné importy, editor `lsl --tui`, formátovaný manuál a `lsl about`;
- LSL 0.8.5 — rychlejší compiler se stejným generovaným kódem;
- LSL 0.8.4 — automatický GC, stabilní paměť a rychlejší dlouhoběžící programy;
- LSL 0.8.3 — paměťová bezpečnost, typové deklarace, čas a X11;
- LSL 0.8.2 — opravy `safe`, barevné chyby a grafická rozšíření;
- LSL 0.8.1 — `sorted`, Set a `dedup`;
- LSL 0.8.0 — správa knihoven, TUI, offline manuál,
  barevné výpisy a tematická nápověda;
- LSL 0.7.8 — `random` v pure LSL, comprehensions,
  výchozí a pojmenované argumenty, `lsl update`;
- LSL 0.7.7 — persistentní CUDA, Float64 device buffery,
  elementwise operace, transpozice, DeviceTensor a opravy dispatchingu;
- LSL 0.7.6 — segregované volné seznamy:
  alokace O(1), oprava kolapsu alokátoru hlášeného v 0.7.5 jako
  gc+thread deadlock;
- LSL 0.7.5 — per-request `gc()` v HTTP
  serveru: dlouhoběžící listener už nevyčerpá alokátor;
- LSL 0.7.4 — oprava `String.split`: byte-přesné
  kousky pro víceb bajtové UTF-8 a lineární čas na velkých vstupech;
- LSL 0.7.3 — konfigurovatelný body limit
  dynamického serveru (`set_body_limit`, výchozí bez limitu) a růst bufferu
  podle skutečně přijatých dat;
- LSL 0.7.2 — HTTP request body pro dynamický
  server: `body`/`body_text` v handleru a `Expect: 100-continue`;
- LSL 0.7.1 — stabilizace HTTP serveru, provenance,
  linkeru, veřejného ABI a úklidu dočasných artefaktů;
- [LSL 0.7.0](https://lsl.lux-ai.cz/releases/0.7/) — HTTP/HTTPS server,
  capability sandbox a explicitní safe/unsafe hranice;
- LSL 0.6.9 — opravy veřejného Any ABI,
  dynamických kolekcí, numeriky, konverzí a diagnostiky compileru;
- LSL 0.6.8 — bezpečnostní hardening runtime,
  procesů, native izolace, I/O, parseru a standardní knihovny;
- LSL 0.6.7 — statické PIE s ASLR, bezpečnější HTTP
  a process plugin transport, zpevněný native loader a paralelně izolované
  testy;
- LSL 0.6.6 — výkonnostní patch s rychlejšími `for`/`rang` smyčkami;
- [LSL 0.6.5](https://lsl.lux-ai.cz/releases/0.6.5/) — stabilní manuál;
  bitové operace, rychlé typované `IntArray` hot pathy, sdílená vlákna,
  SSE2 FloatArray kernely, registrový Int codegen a paměťově omezené
  round-trip převody Float;
- [LSL 0.6](https://lsl.lux-ai.cz/releases/0.6/) — původní stabilní
  snapshot s Lux Stringy, aliasy modulů a skutečnými CUDA Runtime kernely;
- [LSL 0.5](https://lsl.lux-ai.cz/releases/0.5/) — první veřejné
  self-hosted vydání.

Datovaný přehled změn je v
[changelogu](https://lsl.lux-ai.cz/#CHANGELOG).

## Použití

```text
./lsl --help
./lsl version
./lsl                              # interaktivní zdroj ze stdin, konec řádkem exit
./lsl program.lsl arg1 arg2
./lsl compile program.lsl program     # bezpečný výchozí režim
./lsl compile --unsafe raw.lsl raw    # výslovně privilegovaný překlad
./lsl config examples/config/system.lsl
./lsl install textkit
./lsl list
./lsl check textkit
./lsl search text
./lsl install --tui
./lsl man
./lsl help install
./lsl origin textkit
./lsl server --dir public --port 8080
./lsl sandbox --read input.txt program.lsl
./compiler/lslc program.lsl program
```

`lsl` i `compiler/lslc` jsou LSL-generované statické PIE ELF soubory. Výstup
compileru má ASLR, oddělené segmenty bez současného zápisu a spouštění,
neproveditelný stack a žádný dynamický interpreter ani závislost na libc. Bez argumentů `lsl` na terminálu zobrazí `>>>`, sbírá
jednu společnou translation unit do řádku `exit` a pak ji přeloží/spustí. Pipe
skončí prostým EOF a nepotřebuje `exit`:

```text
printf 'print 6 * 7\n' | ./lsl
```

Víceřádkový heredoc má pouze shellový delimiter, ne ještě LSL `exit`:

```text
./lsl <<'EOF'
load time
print time.time()
EOF
```

Slovo `EOF` je libovolný marker shellu, nikoli součást LSL. Interaktivní TTY používá místo shellového markeru samostatný řádek `exit` nebo Ctrl-D.

## Příprava zdrojů a test

Pro překlad jsou potřeba GNU binutils (`as`, `ld`). Vývojová příprava
používá navíc Git a Python 3; spuštění hotových LSL programů je nevyžaduje.
`release.json` připíná konkrétní commity LuxIR a LSL-Web. **V Git checkoutu**
spusťte přípravu, která potřebuje Git a síť, nebo lokální Git checkouty přes
`--luxir-checkout` a `--web-checkout`:

```text
python3 tools/release/prepare_sources.py
python3 tools/release/build_release.py
./compiler/lslc compiler/pure/lslc_qbe.lsl /tmp/lslc-next ./build/luxir/luxir
cmp compiler/lslc /tmp/lslc-next
LUXIR_SOURCE="$PWD/build/dependencies/LuxIR/lsl/luxir.lsl" ./tests/lsl-test qbe ./compiler/lslc
./tests/lsl-test qbe-fast ./compiler/lslc
LUXIR_SOURCE="$PWD/build/dependencies/LuxIR/lsl/luxir.lsl" ./tests/lsl-test qbe-fixed-point ./compiler/lslc
```

`prepare_sources.py` exportuje připnuté offline Markdown manuály do
`build/manual-source` a zpřístupní je přes `docs/developer_guides`. Soubor
`SOURCE.json` obsahuje původ, commit a hashe kapitol. Web se nevyvíjí v tomto
repozitáři. Backend se připravuje v `build/dependencies/LuxIR` a používá se
jako `build/luxir/luxir`; produkční překlad nemá automatický fallback na C QBE.

**Vydaný zdrojový archiv** už obsahuje připnuté zdroje LuxIR v
`build/dependencies/LuxIR`, skutečný adresář offline manuálů
`docs/developer_guides` včetně `SOURCE.json`, runtime `build/qbe/runtime.o`
a backend `build/luxir/luxir` jako kopie kanonických artefaktů, bez symlinků.
Neobsahuje Git metadata závislostí. `prepare_sources.py` zde nespouštějte;
reprodukce se provede offline přímo:

```text
python3 tools/release/build_release.py
```

Plný runner agreguje pozitivní corpus se zachováním source spans a dále
ověřuje diagnostiku, konfiguraci, runtime, instalované zdroje a fixed point.
`LUXIR_SOURCE` zapíná také fixed point samostatného backendu. Kompletní
release preflight přidává izolovanou migraci instalace, reinstalace,
rollbacky a cílené nativní kontroly. Pro migrační gate navíc potřebuje
funkční starší balík 0.8.9 s instalátorem a jeho sousedními nástroji;
výchozí cesta je `~/.local/bin/lsl-install`, jinou lze předat výslovně:

```text
python3 tools/release/verify_release.py --luxir-source build/dependencies/LuxIR/lsl/luxir.lsl --old-installer /cesta/k/lsl-0.8.9/bin/lsl-install
```

Běžný self-host přes `build_release.py` ani původní runner starší
nainstalované LSL nepotřebují. Pro offline preflight musí být starší balík
předem dostupný; skript jej nestahuje.

Podrobný vývojový postup je v [docs/compiler-development.md](docs/compiler-development.md).

## Instalace

Při přechodu z 0.7.8 použijte jednou `lsl-install` z nového archivu: starý
updater má chybu čtení tar hlavičky. Installer 0.8.3 zachová předchozí
generaci a atomicky přepne instalaci. [Postup](https://git.lux-ai.cz/LuxAI/LSL-Web/src/branch/main/public/17-cli-and-packages.md#jednorázový-přechod-z-078).

```text
./compiler/pure/lsl-install /tmp/lsl-prefix
/tmp/lsl-prefix/bin/lsl program.lsl
```

Bez argumentu installer používá `/usr/local` (podle oprávnění procesu). Installer, build nástroje i test runner jsou LSL-generované ELF soubory. Instalovaný compiler hledá standardní moduly relativně k vlastnímu `/proc/self/exe`, takže funguje z libovolného pracovního adresáře.

## Zdrojové knihovny

Grafické moduly `gfx`, `x11`, `wayland`, `display`, `input`, `ui` a `css`
nejsou od 0.8.2 součástí základní instalace. Použijte například `lsl install ui`
a `lsl install display`; závislosti se stáhnou automaticky. Zdrojové kopie
pro vývoj jsou v `extensions/`, publikované balíčky v repozitáři LSL-Packages.

Máte-li nainstalované `x11`, před přechodem na 0.8.3 spusťte `lsl update x11`.
Nové X11 používá monotónní čas a podporuje LSL 0.8.2 i 0.8.3; stará knihovna
předpokládala číselný návrat `clock()`. Příklad hry je v `examples/snake.lsl`.

`lsl update` bez názvu knihovny aktualizuje samotné LSL. `lsl update --check`
pouze ověří dostupnou verzi, `lsl update --rollback` obnoví předchozí instalaci.
Podepsaný updater podporuje `~/.local` bez sudo a `/usr/local` s explicitním
`sudo /usr/local/bin/lsl update --system`. Checkout se nepřepisuje.
Podrobnosti: [aktualizace LSL](docs/updates.md).

```text
./lsl install textkit
./lsl update textkit
./lsl install --config libraries.conf
./lsl origin textkit
```

Knihovna se stáhne z produkčního registru `https://lsl.lux-ai.cz/packages`, ověří zveřejněným SHA-256,
zkušebně přeloží, zapíše ověřitelný `.origin` provenance sidecar a atomicky
uloží do `~/.local/lib/lsl/stdlib`. `update NAME`
vyžaduje existující knihovnu a používá stejnou ověřenou atomickou cestu. Config
obsahuje jeden název na řádek; prázdné řádky a řádky začínající `#` se ignorují.
Built-in moduly
mají vždy přednost. `LSL_REGISTRY` může změnit základní URL; vzdálená URL musí
používat HTTPS. Registr je zatím nepodepsaný, takže hash ze stejného serveru
nenahrazuje budoucí podpisový trust model. Podrobnosti jsou v
[docs/packages.md](docs/packages.md).

## Implementované jádro

- Int, Bool, None a boxed IEEE-754 Float;
- UTF-8 String s code-point `len`, indexací, slicingem, `chr` a `ord`;
- List, Tuple, Set, RealArray, Dictionary a neboxované `IntArray`/`FloatArray`/packed `ByteArray`;
- functions, recursion, first-class Function pointers a callbacks;
- classes/instances, jednoduchá dědičnost `class Child(Parent)`, přepisování
  metod, `origin.method()` a public/private module class lowering;
- recursive modules, `safe`, `try/else`, explicitní paměťově privilegované
  `unsafe:`, `Error`, `check`, `last_error`;
- statické aliasy modulů (`load tensor as t`), first-class interpolované Lux
  Stringy, knihovní `BigInt`, rozšířený modul `math` a vestavěné `sqrt`;
- conservative stack/global-root mark-sweep GC s reusable free-list;
- JSON, strict `config.lconf` dependency codec pro zdroje apt/lux/lsl, čistý config evaluator, LuxOS/Debian modul `system` pro balíčky, služby, uživatele, atomické soubory, mounty a generace/rollback, wall/monotonic time a sleep, filesystem, argv, environment, přímé `os.run("ls -al")` bez shellu, process/capture, HTTP(S) přes validovaný curl config na stdin, verzované JSON-stdin process plugin ABI bez shellu a skutečný NVIDIA CUDA worker se sum/dot/AXPY/matmul kernely a binárním Float64 transportem;
- syscall-only statický HTTP server, HTTPS přes systémový nginx/OpenSSL a
  capability sandbox s namespaces, cgroup/prlimit limity a čistým prostředím;
- strukturované compile errors: kód, soubor, řádek, sloupec, výřez, caret a help.

`tests/selfhost_conformance.lsl` produkuje přesně `tests/selfhost_conformance.out`. Config příklad produkuje přesně `tests/config_expected.json`.

## Dokumentace

- [Praktické programování v LSL](docs/programming.md)
- [GUI, okna a widgety](docs/gui.md)
- [Jazyková specifikace](docs/language.md)
- [Vývoj compileru a release workflow](docs/compiler-development.md)
- [Deklarativní konfigurace](docs/configuration.md)
- [AI aplikace](docs/ai.md)
- [Matematika a BigInt](docs/math.md)
- [Čas a měření](docs/time.md)
- [Linux příkazy přes modul os](docs/os.md)
- [Instalace LSL knihoven](docs/packages.md)
- [HTTP/HTTPS server](docs/server.md)
- [Capability sandbox a unsafe hranice](docs/sandbox.md)
- [Správa balíčků LuxOS](docs/system.md)
- [Dependency manifest config.lconf](docs/lconf.md)
- [Bezpečnostní model a hranice důvěry](docs/security.md)
- [Native/plugin ABI](docs/native-plugins.md)
- [CUDA backend a worker protokol](docs/cuda.md)
- [Random — náhodná čísla a výběry](docs/random.md)
- [Podepsané aktualizace LSL](docs/updates.md)
- [Poznámky k vydání 0.7.8](docs/release-0.7.8.md)
- [Poznámky k vydání 0.8.0](docs/release-0.8.0.md)
- [Poznámky k vydání 0.8.1](docs/release-0.8.1.md)
- [Poznámky k vydání 0.8.2](docs/release-0.8.2.md)
- [Poznámky k vydání 0.8.3](docs/release-0.8.3.md)
- [Poznámky k vydání 0.8.4](docs/release-0.8.4.md)
- [Poznámky k vydání 0.8.5](docs/release-0.8.5.md)
- [Poznámky k vydání 0.8.6](docs/release-0.8.6.md)
- [Poznámky k vydání 0.8.7](docs/release-0.8.7.md)
- [Poznámky k vydání 0.8.8](docs/release-0.8.8.md)
- [CLI, knihovny a terminálový manuál](https://git.lux-ai.cz/LuxAI/LSL-Web/src/branch/main/public/17-cli-and-packages.md)
- [Poznámky k vydání 0.7.7](docs/release-0.7.7.md)
- [Poznámky k vydání 0.7.6](docs/release-0.7.6.md)
- [Poznámky k vydání 0.7.5](docs/release-0.7.5.md)
- [Poznámky k vydání 0.7.4](docs/release-0.7.4.md)
- [Poznámky k vydání 0.7.3](docs/release-0.7.3.md)
- [Poznámky k vydání 0.7.2](docs/release-0.7.2.md)
- [Poznámky k vydání 0.7.1](docs/release-0.7.1.md)
- [Poznámky k vydání 0.7.0](docs/release-0.7.md)
- [Poznámky k lokálnímu vydání 0.6.9](docs/release-0.6.9.md)
- [Poznámky k lokálnímu vydání 0.6.8](docs/release-0.6.8.md)
- [Poznámky k lokálnímu vydání 0.6.7](docs/release-0.6.7.md)
- [Poznámky k lokálnímu vydání 0.6.6](docs/release-0.6.6.md)
- [Poznámky k lokálnímu vydání 0.6.5](docs/release-0.6.5.md)
- [Poznámky k lokálnímu vydání 0.6.4](docs/release-0.6.4.md)
- [Poznámky k lokálnímu vydání 0.6.3](docs/release-0.6.3.md)
- [Poznámky k lokálnímu vydání 0.6.2](docs/release-0.6.2.md)
- [Poznámky k lokálnímu vydání 0.6.1](docs/release-0.6.1.md)
- [Poznámky k lokálnímu vydání 0.6](docs/release-0.6.md)
- [Datovaný changelog všech vydání](https://git.lux-ai.cz/LuxAI/LSL-Web/src/branch/main/public/CHANGELOG.md)
- [Webová historie stabilních manuálů](https://git.lux-ai.cz/LuxAI/LSL-Web/src/branch/main/public/releases/index.html)
- [Linux target](docs/linux.md)

## Zdroj compileru

Výchozí vstup je `compiler/pure/lslc_qbe.lsl`, veřejná binárka `compiler/lslc`.
Lexer, parser, modulový linker, sémantická analýza, LuxIR emitter a runtime jsou
v `compiler/pure/`; standardní moduly v `stdlib/`. Samostatný LuxIR backend
se připravuje z připnutého projektu. `lslc_direct.lsl` a původní strojový backend
zůstávají pro kompatibilitu interních API a regresní testy.

Známá omezení vydání a plán další práce jsou v `TODO.md` a výše uvedeném benchmarku;
starší vývojové záznamy jsou v `PURE_LSL_PROGRESS.md`. CUDA
LSL používá bundlovaný izolovaný NVIDIA CUDA Runtime worker s CPU fallbackem,
nikoli přímý in-process CUDA driver ABI. FloatArray kernely jsou ručně
vektorizované přes SSE2 a `thread_spawn`/`thread_join` poskytují sdílená
vlákna s atomickými builtiny. CUDA 0.7.7 přidává persistentní kontext,
device buffery a dense Float64 Tensor operace. Obecná autovektorizace,
uživatelské GPU kernely, další dtype a obecné foreign shared-object ABI
zůstávají mimo veřejný kontrakt.

Licence: MIT, viz `LICENSE`.
