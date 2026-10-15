# LSL 0.10.1 — release evidence

- `build.json`: `build_release.py --seed` (self-hosted vývojový frontend
  0.10.1). Frontend i backend fixed point bajtově shodné.
- `build-*.json`: `build_target_tools.py --layout` pro šest dalších
  hostitelů (Linux aarch64 a riscv64, Windows x64 a arm64 s LLVM 20.1.8
  `--llvm`, macOS arm64 a x86_64), nástroje přeložené vydaným x86_64
  překladačem.
- Runtime všech 9 cílů přestavěný vydaným překladačem je bajtově shodný
  s připravenými objekty.
- `verification.json`: úplný `verify_release.py`, všechny brány PASS.
  `native-image.json` a `original-runner.json` jsou podrobné reporty.
- `performance-vs-0.10.0.json`: CPU čas (user+sys) dětských procesů,
  11 střídavých kol, vydané binárky 0.10.0 (klíč `090`) proti 0.10.1
  (`091`). Rozdíly mediánů pod 3 %; odlehlé hodnoty (překlad list_access
  a dictionary_access) změřené znovu na jednom jádře 21 střídavými koly:
  −0,1 % a −0,3 %. Velký zdroj (překladač, 5 běhů) 3076 → 3098 ms.
  string_split_join po úpravě rychlé cesty sčítání −0,2 % (15 kol).
- Emulace (qemu-user, `/usr/bin/as` a `/usr/bin/ld` v uživatelském jmenném
  prostoru nahrazené binutils cílové architektury): `lslc` pro aarch64
  i riscv64 se přeloží sám bajtově shodně; `target_tests.py native`
  102/103 na obou, fixed point stupeň 2 = 3, `lsl-install` a nainstalovaný
  překladač v pořádku. Selže jen `native_portable_conformance.lsl`
  (izolované nativní volání), stejně jako s balíkem 0.10.0 v téže
  emulaci; na skutečném ARM64 v CI prochází.
- Wine: `lslc.exe` pro Windows x64 se přeloží sám (stupeň 2 = 3),
  `lsl-install.exe` zkopíruje nástroje LLVM bajtově shodně.
- CI `targets`: `native` a `run` pro všechny cíle na balících, které CI
  sestaví ze zdroje (binutils a llvm-dlltool z Ubuntu, proto se v bajtech
  liší od archivů vydání). Přesné archivy vydání otestovala úloha
  `release-native` (běh 38747104262, archivy z draft release v LSL-ci,
  kontrola SHA256SUMS): nativní překlad a spuštění všech samostatných
  testů, fixed point stupeň 2 = 3, `lsl-install` a nainstalovaný překladač:
  - Windows Server 2025 x64 (`windows-x86_64.zip`): 0 selhání z 92,
  - Windows 11 ARM64 (`windows-arm64.zip`): 0 z 92,
  - macOS 15 Apple Silicon (`macos-arm64.tar.gz`): 0 z 98,
  - macOS 15 Intel (`macos-x86_64.tar.gz`): 0 z 98,
  - Ubuntu 24.04 ARM64 (`linux-aarch64.tar.gz`): 0 z 103,
  - Ubuntu 24.04 x86_64 (`linux-x86_64.tar.gz`): 0 z 103.
  Archiv pro riscv64 je ověřený jen v emulaci (viz výše).
- Zdrojový archiv se offline sestaví (`build_release.py`) na bajtově
  shodné `lslc`, `luxir` a `lsl`.
