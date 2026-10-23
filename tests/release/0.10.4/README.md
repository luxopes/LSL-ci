# LSL 0.10.4 — release evidence

- `build.json`: `build_release.py --seed` (self-hostovaný vývojový frontend
  0.10.4, pevný bod seed = seed²). Frontend i backend (LuxIR 0.4.1,
  commit 732c899) fixed point bajtově shodné; `compiler/pure/luxir` je
  shodný s `build/luxir` LuxIR 0.4.1.
- `build-*.json`: `build_target_tools.py --layout` pro šest dalších
  hostitelů (Linux aarch64 a riscv64, Windows x64 a arm64, macOS arm64
  a x86_64), nástroje přeložené vydaným x86_64 překladačem.
- Runtime všech cílů (včetně nového `linux-x86_64-gnu`) přestavěný vydaným
  překladačem je bajtově shodný s připravenými objekty
  (`tools/runtime/build.py`).
- `verification.json`: úplný `verify_release.py` (s instalátorem 0.10.3
  jako předchozí verzí), všech 9 bran PASS (`native-image.json`
  a `original-runner.json` jsou podrobné reporty).
- Cíl `linux-x86_64-gnu`: bundle `tools/ci/target_tests.py build/run`
  s vydaným překladačem 110 z 110 (včetně `tests/gnu/glib_conformance`,
  `gio_conformance` pod `dbus-run-session` a `gtk_conformance` pod
  `xvfb-run`); statický bundle `linux-x86_64` 107 z 107 je součástí
  `verify_release`. LuxIR `make check` (s referenčním QBE), `check-as`,
  `check-ld` (včetně `dyn_check.py`: `tests/run` proti glibc hostitele)
  a `check-wasm` bez selhání.
- `performance-vs-0.10.3.json`: CPU čas (user+sys) dětských procesů,
  11 střídavých kol, vydané binárky 0.10.3 (klíč `090`) proti 0.10.4
  (`091`). Překlad beze změny (minima −1,0 % až +1,1 %), běh programů
  beze změny: LuxIR text programů je u obou překladačů shodný
  (ověřeno diffem `.lir` pro `float_loop` a `list_access`), liší se
  jen runtime o 224 B kódu (vrstva vláken) a 8 B dat. Rozdíly mediánů
  `float_loop` a `list_access` (+5 až +11 %) jsou umístění kódu a šum:
  tentýž program s jinak umístěnou smyčkou (přidaná funkce) má minima
  21,6–22,5 ms proti 22,8 ms u 0.10.3 (připnuto `taskset -c 3`,
  15 kol).
- Emulace (qemu-user, binfmt): `lslc` z balíku pro aarch64 i riscv64 se
  přeloží sám bajtově shodně a shodně s binárkou balíku; `lsl` spustí
  program. `target_tests.py native` na archivu riscv64: selže jen
  `native_portable_conformance.lsl` (izolované nativní volání v qemu-user,
  stejně jako u 0.10.0–0.10.3), fixed point stupeň 2 = 3, `lsl-install`
  a nainstalovaný překladač v pořádku.
- Wine: `lslc.exe` pro Windows x64 se přeloží sám (stupeň 2 = 3, shodný
  s balíkem), `lsl.exe` spustí program, `lsl version` hlásí 0.10.4.
- CI `targets` (běhy 39919947944 a 39923514044 na commitech f2f0ff2
  a aeabe5b s LuxIR 0.4.1): `native` a `run` pro všechny cíle na balících,
  které CI sestaví ze zdroje; bundle `linux-x86_64-gnu` běží na Ubuntu
  24.04 pod Xvfb a `dbus-run-session`. Přesné archivy vydání otestovala
  úloha `release-native` (běh 39919974316, draft release v LSL-ci,
  kontrola SHA256SUMS): nativní překlad a spuštění všech samostatných
  testů, fixed point stupeň 2 = 3, `lsl-install` a nainstalovaný
  překladač, 0 selhání na Ubuntu 24.04 x86_64 a ARM64, Windows Server
  2025 x64, Windows 11 ARM64, macOS 15 Apple Silicon a Intel. Archiv pro
  riscv64 je ověřený jen v emulaci. První běh odhalil dvě chyby jen
  v testech a CI (varování AT-SPI v GTK testu bez sběrnice přístupnosti,
  chybějící gtk.md v manuálu CI balíků z archivu 0.10.0), opravené
  v aeabe5b před vydáním.
- Zdrojový archiv se offline sestaví (`build_release.py`) na bajtově
  shodné `lslc`, `luxir` a `lsl`.
