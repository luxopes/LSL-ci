# LSL 0.10.3 — release evidence

- `build.json`: `build_release.py --seed` (self-hostovaný vývojový frontend
  0.10.3, pevný bod seed = seed²). Frontend i backend (LuxIR 0.4.0) fixed
  point bajtově shodné; `compiler/pure/luxir` je shodný s `build/luxir`
  LuxIR 0.4.0.
- `build-*.json`: `build_target_tools.py --layout` pro šest dalších
  hostitelů (Linux aarch64 a riscv64, Windows x64 a arm64, macOS arm64
  a x86_64), nástroje přeložené vydaným x86_64 překladačem; balíky pro
  Windows poprvé bez LLVM (ZIP 3,9 MB místo ~24 MB).
- Runtime všech cílů přestavěný vydaným překladačem je bajtově shodný
  s připravenými objekty (`tools/runtime/build.py`; Windows a macOS runtime
  sestavuje `luxir -a`, objekty shodné s GNU as, resp. LLVM).
- `verification.json`: úplný `verify_release.py` (s instalátorem 0.10.2
  jako předchozí verzí), všechny brány PASS (`native-image.json`
  a `original-runner.json` jsou podrobné reporty).
- Bez externích nástrojů: překlad pro každý z deseti cílů spouští jen
  `lslc` a jeden běh `luxir -a -l` (ověřeno `strace -e execve`). LuxIR
  `make check-as`: objekty COFF (x86-64 jako GNU as, arm64 jako LLVM)
  a Mach-O (jako LLVM) bajtově shodné na překladači, runtime, sondách
  instrukcí a relaxace; `make check-ld`: PE32+ x86-64 spuštěné ve wine,
  Mach-O proti nezávislé kontrole rozvržení (relokace, dyld info, stuby,
  podpis), bare metal proti GNU ld; `make check-wasm`: moduly shodné
  s `wat2wasm` (všech 180 modulů testů cílů).
- `performance-vs-0.10.2.json`: CPU čas (user+sys) dětských procesů,
  11 střídavých kol, vydané binárky 0.10.2 (klíč `090`) proti 0.10.3
  (`091`). Překlad je o 0,3–1,5 % rychlejší (hašované tabulky symbolů
  v assembleru a linkeru LuxIR), běh programů beze změny (mediány
  −3,5 % až +0,7 %; function_calls +15 % mediánu je šum 2ms programu,
  minima shodná).
- Emulace (qemu-user, binfmt): `lslc` z balíku pro aarch64 i riscv64 se
  přeloží sám bajtově shodně a shodně s binárkou balíku; `lsl` spustí
  program.
- Wine: `lslc.exe` pro Windows x64 (bez LLVM) se přeloží sám (stupeň 2 =
  3, shodný s balíkem), `lsl.exe` přeloží a spustí program, `lsl version`
  hlásí 0.10.3; sada testů cíle windows-x86_64 ve wine 96 z 96.
- Emulace (qemu-user): `target_tests.py native` na archivu riscv64: selže
  jen `native_portable_conformance.lsl` (izolované nativní volání
  v qemu-user, stejně jako u 0.10.0–0.10.2), fixed point stupeň 2 = 3,
  `lsl-install` a nainstalovaný překladač v pořádku.
- CI `targets` (běh 39838442665 na commitu eaff432 s LuxIR 0.4.0):
  `native` a `run` pro všechny cíle na balících, které CI sestaví ze
  zdroje bez binutils, LLVM, wabt a Xcode (instalace nástrojů z běhu
  zmizela). Přesné archivy vydání otestovala úloha `release-native`
  (běh 39839376326, draft release v LSL-ci, kontrola SHA256SUMS): nativní
  překlad a spuštění všech samostatných testů, fixed point stupeň 2 = 3,
  `lsl-install` a nainstalovaný překladač, 0 selhání na Ubuntu 24.04
  x86_64 a ARM64, Windows Server 2025 x64, Windows 11 ARM64, macOS 15
  Apple Silicon a Intel (balíky pro Windows bez LLVM, programy Mach-O
  z vestavěného linkeru poprvé na skutečném macOS). Archiv pro riscv64 je
  ověřený jen v emulaci.
- Zdrojový archiv se offline sestaví (`build_release.py`) na bajtově
  shodné `lslc`, `luxir` a `lsl`.
