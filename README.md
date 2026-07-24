# Lux Simple Lang (LSL)

LSL 0.7 je self-hostovaný jazyk pro běžné programování, deklarativní konfiguraci a AI orchestrace. Produkční implementace je pouze LSL: compiler přímo zapisuje statický Linux x86_64 ELF a runtime používá přímé syscalls. Není zde C/C++, libc, assembler, linker, Python ani shell launcher.

## Použití

```text
./lsl                              # interaktivní zdroj ze stdin, konec řádkem exit
./lsl program.lsl arg1 arg2
./lsl compile program.lsl program
./lsl config examples/config/system.lsl
./lsl install textkit
./compiler/lslc program.lsl program
```

`lsl` i `compiler/lslc` jsou LSL-generované ELF soubory. Výstup compileru je statický syscall-only ELF bez section headeru a bez dynamic interpreteru. Bez argumentů `lsl` na terminálu zobrazí `>>>`, sbírá jednu společnou translation unit do řádku `exit` a pak ji přeloží/spustí. Pipe skončí prostým EOF a nepotřebuje `exit`:

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

```text
./compiler/pure/lsl-install /tmp/lsl-prefix
/tmp/lsl-prefix/bin/lsl program.lsl
```

Bez argumentu installer používá `/usr/local` (podle oprávnění procesu). Installer, build nástroje i test runner jsou LSL-generované ELF soubory. Instalovaný compiler hledá standardní moduly relativně k vlastnímu `/proc/self/exe`, takže funguje z libovolného pracovního adresáře.

## Zdrojové knihovny

```text
./lsl install textkit
./lsl update textkit
./lsl install --config libraries.conf
./lsl server
```

Knihovna se stáhne z dočasného HTTPS registru, ověří zveřejněným SHA-256,
zkušebně přeloží a atomicky uloží do `~/.local/lib/lsl/stdlib`. `update`
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
- List, Tuple, RealArray, Dictionary a neboxované `IntArray`/`FloatArray`/packed `ByteArray`;
- functions, recursion, first-class Function pointers a callbacks;
- classes/instances, static i bound metody, public/private module class lowering;
- recursive modules, `safe`, `try/else`, `Error`, `check`, `last_error`;
- conservative stack/global-root mark-sweep GC s reusable free-list;
- JSON, strict `config.lconf` dependency codec pro zdroje apt/lux/lsl, čistý config evaluator, LuxOS/Debian modul `system` pro balíčky, služby, uživatele, atomické soubory, mounty a generace/rollback, wall/monotonic time a sleep, filesystem, argv, environment, bezpečné `os.run("ls -al")`, process/capture, HTTP(S) přes bezpečné `curl` argv a verzované JSON process plugin ABI bez shellu;
- strukturované compile errors: kód, soubor, řádek, sloupec, výřez, caret a help.

`tests/selfhost_conformance.lsl` produkuje přesně `tests/selfhost_conformance.out`. Config příklad produkuje přesně `tests/config_expected.json`.

## Dokumentace

- [Praktické programování v LSL](docs/programming.md)
- [Jazyková specifikace](docs/language.md)
- [Vývoj compileru a release workflow](docs/compiler-development.md)
- [Deklarativní konfigurace](docs/configuration.md)
- [AI aplikace](docs/ai.md)
- [Čas a měření](docs/time.md)
- [Linux příkazy přes modul os](docs/os.md)
- [Instalace LSL knihoven](docs/packages.md)
- [Správa balíčků LuxOS](docs/system.md)
- [Dependency manifest config.lconf](docs/lconf.md)
- [Native/plugin ABI](docs/native-plugins.md)
- [Linux target](docs/linux.md)

## Zdroj compileru

Vstupní bod je `compiler/pure/lslc_direct.lsl`. Lexer, parser, linker, x86_64 encoder, ELF writer a runtime jsou moduly v `compiler/pure/`. Standardní moduly jsou v `stdlib/`.

Známé zbývající mezery jsou vedené výhradně v `PURE_LSL_PROGRESS.md`; zejména GPU/device backend, SIMD autovektorizace, širší Tensor operace a obecné foreign shared-object ABI nejsou vydávány za hotové.

Licence: MIT, viz `LICENSE`.
