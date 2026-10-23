# LSL 0.10.5 — release evidence

- `build.json`: `build_release.py --seed` (self-hostovaný vývojový frontend
  0.10.5, pevný bod seed = seed²). Frontend i backend (LuxIR 0.4.1,
  commit 732c899, beze změny od 0.10.4) fixed point bajtově shodné;
  `compiler/pure/luxir` je shodný s `build/luxir` LuxIR 0.4.1.
- `build-*.json`: `build_target_tools.py --layout` pro šest dalších
  hostitelů (Linux aarch64 a riscv64, Windows x64 a arm64, macOS arm64
  a x86_64), nástroje přeložené vydaným x86_64 překladačem.
- Runtime všech cílů je přestavěný novým překladačem (inicializace
  literálů volá `rt_runtime_string_literal`; starý bootstrap runtime
  symbol nemá, proto `tools/runtime/build.py --bootstrap-runtime` s runtime
  sestaveným z aktuálních zdrojů) a po vydání znovu vydaným překladačem
  bajtově shodný (ověřeno linux-x86_64, linux-x86_64-gnu, macos-arm64).
- `verification.json`: úplný `verify_release.py` (s instalátorem 0.10.4
  jako předchozí verzí), všech 9 bran PASS (`native-image.json`
  a `original-runner.json` jsou podrobné reporty). První běh odhalil dvě
  zastaralé kontroly růstu internovací tabulky
  (`tests/table_growth_conformance.lsl`, `tests/qbe/startup_tables.lsl`):
  literály se od 0.10.5 při startu neinternují; kontroly upraveny.
- Paměť a rychlost (měřeno před vydáním v klidu): minimální program
  136 kB RSS (0.10.4: 2,2 MB, THP „always“ na bitmapě objektů), program
  s malou živou množinou 2,6 MB místo 4,9 MB (rozpočet GC 2 MiB), po
  `gc()` se stránky velkých volných bloků vracejí jádru (50 MB → 1,5 MB),
  démon GTK/D-Bus 12,7 MB anonymní paměti jako v C (Python 27,4 MB),
  `lsl skript.lsl` z cache 1,2 ms místo 110 ms, 3500 literálů při startu
  0,27 ms místo 0,47 ms.
- `performance-vs-0.10.4.json`: CPU čas (user+sys) dětských procesů,
  11 střídavých kol, vydané binárky 0.10.4 (klíč `090`) proti 0.10.5
  (`091`). Měřeno na zatíženém stroji, jen orientačně: překlad −1 až −5 %
  (minima), běh −3 až −14 % (allocation_gc −14 %, list_access −11 %,
  float_loop −10 %, pfmt −5 %); žádný případ pomalejší.
- Bundly: `linux-x86_64-gnu` 110 z 110 (GLib, D-Bus přes GIO, GTK pod Xvfb),
  `wasm32-wasi` a `wasm32-wasi-threads` 90 z 90, hello pro všech 11 cílů.
  Nové testy `memory_footprint_conformance`, `memory_release_conformance`
  (Linux, mimo emulaci) a `tests/compiler/cli_cache_conformance.lsl`.
- Emulace (qemu-user, binfmt): `lslc` z balíku pro aarch64 i riscv64 se
  přeloží sám bajtově shodně a shodně s binárkou balíku; `lsl` spustí
  program. `target_tests.py native` na archivu riscv64: 0 selhání ze 109
  (testy bez smyslu pod qemu-user – izolované nativní volání, RSS – se nově
  přeskakují i v režimu native), fixed point stupeň 2 = 3, `lsl-install`
  a nainstalovaný překladač v pořádku.
- Wine: `lslc.exe` pro Windows x64 se přeloží sám (stupeň 2 = 3, shodný
  s balíkem), `lsl.exe` spustí program (dvakrát: překlad a z cache),
  `lsl version` hlásí 0.10.5.
- CI `targets` (běh 39947423671 na commitu 8b59eda): `native` a `run` pro
  všechny cíle na balících, které CI sestaví ze zdroje; test cache skriptů
  běží nativně i na Windows a macOS (otisky obsahu). Přesné archivy vydání
  otestovala úloha `release-native` (běh 39947443055, draft release
  v LSL-ci, kontrola SHA256SUMS): nativní překlad a spuštění všech
  samostatných testů, fixed point stupeň 2 = 3, `lsl-install`
  a nainstalovaný překladač, 0 selhání na Ubuntu 24.04 x86_64 a ARM64,
  Windows Server 2025 x64, Windows 11 ARM64, macOS 15 Apple Silicon
  a Intel. Archiv pro riscv64 je ověřený jen v emulaci.
- Zdrojový archiv se offline sestaví (`build_release.py`) na bajtově
  shodné `lslc`, `luxir` a `lsl`.
