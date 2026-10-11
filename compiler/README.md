# Compiler LSL 0.9.0 BETA

Výchozí compiler je `pure/lslc_qbe.lsl`, veřejná binárka `compiler/lslc`.
Frontend, samostatný backend **LuxIR** i host runtime jsou napsané v LSL.
Aktuální vydání podporuje **Linux x86_64**. Překlad vyžaduje GNU `as` a `ld`
z balíku binutils; výsledné statické PIE programy používají syscalls bez libc
nebo dynamického interpreteru. Produkční cesta automaticky nepřepíná na C QBE.

## Mapa implementace

- `frontend.lsl`, `lexer.lsl`, `parser.lsl`, `linker.lsl` — frontend a moduly;
- `semantic.lsl`, `validation.lsl`, `flow.lsl`, `declarations.lsl` — společná analýza programu;
- `pipeline.lsl`, `target.lsl` — společný vstup a výběr cíle;
- `qbe_emit.lsl` — lowering analyzovaného programu do LuxIR;
- `qbe_toolchain.lsl` — spuštění LuxIR, assembleru a linkeru, statický PIE a úklid;
- `qbe_runtime_dump.lsl` — materializace nativního runtime;
- `runtime.lsl`, `runtime_linux_x86_64.lsl`, `*_runtime_linux_x86_64.lsl` — cílový syscall-only runtime;
- `runtime_abi_linux_x86_64.lsl`, `value_abi.lsl` — runtime state a reprezentace hodnot;
- `host.lsl`, `host_linux_x86_64.lsl` — důvěryhodné cesty, nástroje a spuštění CLI;
- `stdlib/_platform_linux_x86_64.lsl`, `stdlib/_*_linux_x86_64.lsl` — cílové knihovny;
- `lslc_direct.lsl`, `compiler_backend.lsl`, `backend_x86_64.lsl`, `x86_64.lsl`,
  `assembler_x86_64.lsl`, `relocations_x86_64.lsl`, `object_code.lsl`,
  `image_writer.lsl`, `image_elf64_linux.lsl`, `elf_image.lsl`, `codegen.lsl` —
  původní přímý backend a kompatibilní interní API, nadále pokryté regresními testy.

Frontend vrací analyzovaný AST, typy, tabulky funkcí/tříd a stabilní pořadová ID
proměnných. LuxIR zajišťuje další optimalizace, výběr instrukcí a přidělení
registrů. GNU assembler a linker vytvoří finální obraz. CLI a nízkoúrovňový
driver sdílejí veřejnou pipeline; `--target NAME` odmítne neimplementovaný cíl.
Popis plánovaných portů není příslibem podpory Windows, macOS nebo jiné
architektury v této BETA. Rozhraní jsou v [porting.md](porting.md).

## Připnuté zdroje a reprodukce

`release.json` určuje commit samostatného LuxIR a manuálů projektu LSL-Web.
Příprava vyžaduje Git a Python 3; hotové LSL programy je nepotřebují:

```text
python3 tools/release/prepare_sources.py
python3 tools/release/build_release.py
```

První nástroj připraví `build/dependencies/LuxIR`, `build/luxir/luxir` a offline
kapitoly v `build/manual-source`. `docs/developer_guides` na export odkazuje;
`SOURCE.json` eviduje původ a hashe. Lokální checkout lze dodat pomocí
`--luxir-checkout` a `--web-checkout`. Druhý nástroj používá dodané nativní
LSL bootstrap binárky, ověří fixed point frontendu i backendu a přegeneruje
release nástroje. Výsledek zaznamená do `build/release-build/build.json`.
Nejde o bootstrap překladačem C.

```text
./compiler/lslc source.lsl output
./compiler/lslc compiler/pure/lslc_qbe.lsl /tmp/next ./build/luxir/luxir
cmp ./compiler/lslc /tmp/next
LUXIR_SOURCE="$PWD/build/dependencies/LuxIR/lsl/luxir.lsl" ./tests/lsl-test qbe ./compiler/lslc
./tests/lsl-test qbe-fast ./compiler/lslc
LUXIR_SOURCE="$PWD/build/dependencies/LuxIR/lsl/luxir.lsl" ./tests/lsl-test qbe-fixed-point ./compiler/lslc
python3 tools/release/verify_release.py --luxir-source build/dependencies/LuxIR/lsl/luxir.lsl
```

Kanonický frontend `pure/lslc-qbe` je shodný s `compiler/lslc`; backend je
`pure/luxir` a při vývoji `build/luxir/luxir`. Instalace umístí tyto nástroje
jako `bin/lslc` a `bin/luxir`, runtime do `lib/lsl/compiler/qbe/runtime.o`.
Název některých modulů s prefixem `qbe` zůstává kompatibilní, aktuální backend
je LuxIR. Instalovaný compiler hledá vlastní zdroje a sousední backend před
pracovním adresářem. `LSL_BACKEND` může výslovně určit absolutní cestu
kompatibilního backendu; chybějící backend je chyba.

Běžný driver používá bezpečný režim. Self-host vstupy nesou explicitní první
řádek `# lsl: internal-abi`; veřejné CLI tento řádek nepoužívá jako oprávnění
pro libovolný skript. `--unsafe` je vědomý privilegovaný opt-in,
`--safe` může interní trust odmítnout a `--sandbox` zakazuje unsafe bloky.

Další nástroje:

- `pure/lsl-cli` — veřejné run/compile/config/install CLI;
- `pure/lsl-configure` — generátor config wrapperu;
- `pure/lsl-install` — instalátor toolchainu;
- `pure/package.lsl` — ověřená per-user instalace zdrojových knihoven;
- `tests/lsl-test` — agregovaný conformance runner; pro LuxIR používejte režimy
  `qbe`, `qbe-fast` a `qbe-fixed-point`. `LUXIR_SOURCE` je nutný také pro
  kontrolu fixed pointu samostatného backendu.

## Známé omezení

Překlad společného velkého zdroje compileru v zaznamenaném měření trval
11,399 s oproti 8,062 s u 0.8.9 (**+41,4 %**). Optimalizace času překladu je
otevřená práce pro **0.9.1**; nelze ji zaměnit za zrychlení výsledných programů.
Viz [měření a důkazy](../tools/qbe/LUXIR_BENCHMARK_20261011.md).

Architekturu, bezpečnostní pravidla a release postup popisuje
[docs/compiler-development.md](../docs/compiler-development.md).
