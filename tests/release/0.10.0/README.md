# LSL 0.10.0 — release evidence

- `build.json`: `build_release.py --seed` (self-hosted vývojový frontend
  0.10.0). Frontend i backend fixed point bajtově shodné.
- `build-linux-aarch64.json`, `build-linux-riscv64.json`:
  `build_target_tools.py`, nástroje pro aarch64 a riscv64 přeložené
  vydaným x86_64 překladačem. Na emulovaném hostiteli (qemu-user, `/usr/bin/as`
  a `/usr/bin/ld` v uživatelském jmenném prostoru nahrazené binutils cílové
  architektury) se `lslc` i `luxir` přeloží samy bajtově shodně a
  samostatné testy přeložené nativním toolchainem prošly 100/100 na obou.
- Runtime všech 9 cílů (`tools/runtime/build.py`) přestavěný vydaným
  překladačem je bajtově shodný s připravenými objekty.
- `verification.json`: úplný `verify_release.py`, všechny brány PASS (korpus
  a oba fixed pointy, managed instalace, izolovaná migrace z 0.8.9 se dvěma
  reinstalacemi a rollbacky, hardening obrazu, veřejné CLI a registrované
  nativní regrese). `native-image.json` a `original-runner.json` jsou
  podrobné reporty. Po ověření se změnil jen připnutý commit manuálu
  (oprava čísel v changelogu webu), binárky ne.
- `performance-vs-0.9.2.json`: CPU čas (user+sys) dětských procesů,
  11 střídavých kol, vydané binárky 0.9.2 (klíč `090`) proti 0.10.0 (`091`;
  popisky skriptu zůstávají z měření 0.9.2). Mediány překladu −42 % až
  −44 %, velký zdroj (překladač 0.9.2) 5479 → 2791 ms. Běh: formátování
  −74 %, parsování −55 %, float_loop −60 %, list_access −65 %,
  dictionary_access −51 %, string_split_join −54 %, allocation_gc −55 %;
  integer_loop a intarray_access beze změny, function_calls při 200 M
  volání na jednom jádře 301 ms v obou verzích.
- Testy cílů: CI `targets` (Windows x86_64 a arm64, macOS x86_64 a arm64,
  Linux arm64 na skutečných strojích, WebAssembly v Node a wasmtime, bare
  metal v qemu); lokálně `tests/cross_targets.py` pro všechny cíle.

Stroj: notebook Ryzen 5 5500U, škálování frekvence; jednotlivé vzorky se
liší až o ±10 %, smysl mají jen mediány a rozložení.
