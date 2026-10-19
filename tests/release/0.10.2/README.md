# LSL 0.10.2 — release evidence

- `build.json`: `build_release.py --seed` (self-hostovaný vývojový frontend
  0.10.2, pevný bod seed = seed²). Frontend i backend (LuxIR 0.3.1) fixed
  point bajtově shodné.
- `build-*.json`: `build_target_tools.py --layout` pro šest dalších
  hostitelů (Linux aarch64 a riscv64, Windows x64 a arm64 s LLVM 20.1.8
  `--llvm`, macOS arm64 a x86_64), nástroje přeložené vydaným x86_64
  překladačem.
- Runtime všech cílů přestavěný vydaným překladačem je bajtově shodný
  s připravenými objekty (`tools/runtime/build.py`, SHA-256 před a po).
- `verification.json`: úplný `verify_release.py`, všechny brány PASS
  (`native-image.json` a `original-runner.json` jsou podrobné reporty).
- Linux bez binutils: programy pro linux-x86_64, x86, arm, arm64 a riscv64
  sestavuje a linkuje LuxIR (`luxir -a -l`, jeden proces). Objekty jsou
  bajtově shodné s GNU as na překladači, runtime i pomocných funkcích
  (LuxIR `make check-as`); program slinkovaný jedním během je shodný
  s výstupem oddělených kroků `luxir -a` + `luxir -l`.
- `performance-vs-0.10.1.json`: CPU čas (user+sys) dětských procesů,
  11 střídavých kol, vydané binárky 0.10.1 (klíč `090`) proti 0.10.2
  (`091`). Překlad malých programů je rychlejší (jeden proces backendu
  místo tří: tiny −12 %, mediány ostatních −6 % až +6 %, allocation_gc
  +10 % mediánu při +2,5 % minima). Běh: odlehlé hodnoty
  dictionary_access (+11 %) a string_split_join (+15 %) přeměřené na jednom
  jádře 21 střídavými koly: program slinkovaný LuxIR proti témuž objektu
  slinkovanému GNU ld je stejně rychlý nebo rychlejší (string_split_join
  67,2 vs 69,8 ms, dictionary_access 58,6 vs 62,1 ms), proti 0.10.1
  string_split_join +3 % a dictionary_access −6 % mediánu; rozdíly jsou
  v šumu notebooku, nikoli v linkeru.
- Emulace (qemu-user, binfmt, bez binutils): `lslc` z balíku pro aarch64
  i riscv64 se přeloží sám bajtově shodně a shodně s binárkou balíku.
- Wine: `lslc.exe` pro Windows x64 se přeloží sám (stupeň 2 = 3), `lsl.exe`
  přeloží a spustí program, `lsl version` hlásí 0.10.2.
- CI `targets` (běh na commitu vydání): `native` a `run` pro všechny cíle na
  balících, které CI sestaví ze zdroje. Přesné archivy vydání testuje úloha
  `release-native` (draft release v LSL-ci, kontrola SHA256SUMS) — výsledek
  doplněn níže.
- Zdrojový archiv se offline sestaví (`build_release.py`) na bajtově
  shodné `lslc`, `luxir` a `lsl`.
