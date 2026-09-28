# Lux Simple Lang (LSL)

**LSL 0.8.9** je vydání self-hostovaného jazyka pro běžné
programování, deklarativní konfiguraci, AI orchestrace a volitelné CUDA
výpočty. Compiler i host runtime
jsou pouze LSL: compiler přímo zapisuje statický Linux x86_64 ELF a runtime
používá přímé syscalls, bez libc, assembleru, linkeru, Pythonu nebo shell
launcheru. Skutečný NVIDIA backend je záměrně oddělený proces
`cuda/lsl-cuda-worker`, napsaný v CUDA C++; bez něj zůstává celé LSL jádro
pure-LSL a Tensor používá CPU fallback.

## Self-hosted vydání

LSL 0.8.9 přidává automatické načítání `.env` vedle skriptu,
HTTP knihovnu `requests` s JSON a streamováním a offline manuály všech
26 veřejných standardních knihoven (`lsl man env`, `lsl man requests`).
Proměnné prostředí mají před `.env` přednost; hodnoty ze souboru se čtou
za běhu a nevkládají se do zkompilovaných programů.

Binární balík pro Linux x86_64, zdrojový archiv a český manuál jsou na
[lsl.lux-ai.cz](https://lsl.lux-ai.cz/). Aktualizace: `lsl update`;
podrobnosti v [poznámkách k vydání](docs/release-0.8.9.md).
Starší manuály jsou v [historii vydání](https://lsl.lux-ai.cz/releases/):

- [LSL 0.8.9](https://lsl.lux-ai.cz/) — `.env`, `requests` a manuály knihoven;
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
compileru má ASLR, jediný RX LOAD, neproveditelný stack, žádný section header
ani dynamic interpreter. Bez argumentů `lsl` na terminálu zobrazí `>>>`, sbírá
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

## Čistý build a test

```text
./compiler/pure/lslc-direct compiler/pure/lslc_direct.lsl /tmp/lslc-next
cmp compiler/pure/lslc-direct /tmp/lslc-next
./tests/lsl-test              # plný suite (výchozí)
./tests/lsl-test fast         # pozitivní conformance bez auditních kroků
./tests/lsl-test fixed-point  # pouze bitová reprodukce compileru
```

`lsl-test` bez shellu linkuje pozitivní corpus do jednoho agregovaného ELF se
zachováním původních source spans; plný režim navíc spouští negative corpus,
config a fixed-point kontrolu. Aktuální SHA-256 je v `PURE_LSL_PROGRESS.md`.

## Instalace

Při přechodu z 0.7.8 použijte jednou `lsl-install` z nového archivu: starý
updater má chybu čtení tar hlavičky. Installer 0.8.3 zachová předchozí
generaci a atomicky přepne instalaci. [Postup](docs/developer_guides/17-cli-and-packages.md#jednorázový-přechod-z-078).

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
- [CLI, knihovny a terminálový manuál](docs/developer_guides/17-cli-and-packages.md)
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
- [Datovaný changelog všech vydání](docs/developer_guides/CHANGELOG.md)
- [Webová historie stabilních manuálů](docs/developer_guides/releases/index.html)
- [Linux target](docs/linux.md)

## Zdroj compileru

Vstupní bod je `compiler/pure/lslc_direct.lsl`. Lexer, parser, linker, x86_64 encoder, ELF writer a runtime jsou moduly v `compiler/pure/`. Standardní moduly jsou v `stdlib/`.

Známé zbývající mezery jsou vedené výhradně v `PURE_LSL_PROGRESS.md`; CUDA
LSL používá bundlovaný izolovaný NVIDIA CUDA Runtime worker s CPU fallbackem,
nikoli přímý in-process CUDA driver ABI. FloatArray kernely jsou ručně
vektorizované přes SSE2 a `thread_spawn`/`thread_join` poskytují sdílená
vlákna s atomickými builtiny. CUDA 0.7.7 přidává persistentní kontext,
device buffery a dense Float64 Tensor operace. Obecná autovektorizace,
uživatelské GPU kernely, další dtype a obecné foreign shared-object ABI
zůstávají mimo veřejný kontrakt.

Licence: MIT, viz `LICENSE`.
