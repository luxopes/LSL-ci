# LSL 0.10.6 — release evidence

- `build.json`: `build_release.py --seed` (self-hostovaný vývojový frontend
  0.10.6, pevný bod seed = seed²; výsledný `compiler/lslc` je bajtově shodný
  se seedem). Frontend i backend fixed point bajtově shodné. Backend je
  LuxIR 0.4.3 (commit ce6e30a): 0.4.2 opravilo hlavičky sekcí dynamického
  ELF jen v C referenci, `lsl/luxir.lsl` (LSL build luxir, který LSL dodává)
  byl ještě vygenerovaný ze zdrojů 0.4.1 – 0.4.3 ho přegenerovalo.
  `make check` a `make check-ld` LuxIR (C reference i LSL build) bez chyb,
  `tests/dyn_check.py` spouští každý dynamický program i po `strip`.
- `build-*.json`: `build_target_tools.py --layout` pro šest dalších
  hostitelů (Linux aarch64 a riscv64, Windows x64 a arm64, macOS arm64
  a x86_64), nástroje přeložené vydaným x86_64 překladačem.
- Runtime všech 12 cílů přestavěný vydaným překladačem (nové runtime funkce
  `text_search`, `text_char_count`, `write_stderr`, čtení souborů bez známé
  velikosti); `compiler/qbe/runtime.o` bajtově shodný s commitnutým.
- `verification.json`: úplný `verify_release.py` (s instalátorem 0.10.5
  jako předchozí verzí), všech 9 bran PASS (`native-image.json`
  a `original-runner.json` jsou podrobné reporty).
- Bundly vydaným překladačem: `linux-x86_64-gnu` 116 ze 116 (nové testy
  glib, gio s voláním z jiného procesu přes gdbus a sledováním souborů,
  gtk pod Xvfb, cairo/pango bez displeje), `wasm32-wasi`
  a `wasm32-wasi-threads` 90 z 90. Program cíle gnu po `strip` běží,
  `PT_INTERP` zachován; `readfile("/proc/self/cmdline")` vrací data.
- `performance-vs-0.10.5.json`: CPU čas (user+sys) dětských procesů,
  11 střídavých kol, vydané binárky 0.10.5 (klíč `090`) proti 0.10.6
  (`091`); stroj pod zátěží, jen orientačně. Překlad −7 až +0,4 % (minima),
  běh beze změny nebo rychlejší (pparse −16 %) kromě `allocation_gc`
  (+4–5 % i na jednom jádře). IR programu se liší jen v nepoužívané větvi
  Float v `__lsl_public_add` (sčítání Float je nově inline); stejné
  zpomalení dá i program 0.10.5 s přidanou nepoužitou funkcí (81–86 ms
  podle velikosti výplně proti 80 ms) a runtime 0.10.5 vs. 0.10.6 nemá vliv
  – jde o umístění kódu, ne o pomalejší cestu.
- Emulace (qemu-user, binfmt): `lslc` z balíku pro aarch64 i riscv64 se
  přeloží sám bajtově shodně a shodně s binárkou balíku; `lsl` spustí
  program. `target_tests.py native` na archivu riscv64: 0 selhání ze 109,
  fixed point stupeň 2 = 3, `lsl-install` a nainstalovaný překladač
  v pořádku.
- Wine: `lslc.exe` pro Windows x64 se přeloží sám (stupeň 2 = 3, shodný
  s balíkem), `lsl.exe` spustí program (překlad a z cache), `lsl version`
  hlásí 0.10.6.
- CI `targets` (běh 40004804576 na commitu f48089b): `native` a `run` pro
  všechny cíle včetně `linux-x86_64-gnu`. Přesné archivy vydání otestovala
  úloha `release-native` (běh 40004937689, draft release v LSL-ci, kontrola
  SHA256SUMS): nativní překlad a spuštění všech samostatných testů, fixed
  point stupeň 2 = 3, `lsl-install` a nainstalovaný překladač, 0 selhání na
  Ubuntu 24.04 x86_64 a ARM64, Windows Server 2025 x64, Windows 11 ARM64,
  macOS 15 Apple Silicon a Intel. Archiv pro riscv64 je ověřený jen
  v emulaci.
