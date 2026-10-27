# LSL 0.10.7 — release evidence

- `build.json`: `build_release.py` (seed = vydaný frontend 0.10.6 z gitu,
  pak vlastní generace). Frontend i backend fixed point bajtově shodné.
  Backend je LuxIR 0.4.4 (verze importovaných symbolů dynamických programů;
  `lsl/luxir.lsl` přegenerovaný `tools/translate.py` s pycparser 3.0, který
  z nezměněných zdrojů 0.4.3 dává bajtově shodný `luxir.lsl`). Výstup C
  reference a LSL buildu LuxIR je pro dynamický program bajtově shodný;
  statické ELF (x86_64, arm64, riscv64), PE, Mach-O a WebAssembly bajtově
  shodné s LuxIR 0.4.3. `tests/dyn_check.py` LuxIR bez chyb pro obě
  implementace; `ld_check`, `pe_check` a `macho_check` nešly spustit (na
  stroji chybí clang a llvm-objdump).
- Runtime všech 12 cílů přestavěný vydaným překladačem; nové runtime funkce
  `rt_runtime_cwd`, `rt_runtime_chdir` a vstupy `lsl_arch_return_one`,
  `lsl_arch_alpn_select` (gnu). Společný pevný bod: `build_release.py`
  s novým `compiler/qbe/runtime.o` dá bajtově shodné nástroje a další
  přestavba runtime dá bajtově shodné objekty všech cílů.
- Plný runner `LUXIR_SOURCE=… tests/lsl-test qbe` (včetně fixed point
  backendu): `pure LSL tests passed`.
- Bundly vydaným překladačem: `wasm32-wasi` 91 z 91 (node);
  `linux-x86_64-gnu` pod Xvfb 122 testů, selže jen
  `gio_conformance` řádek „Features is a list“: vlastnost `Features`
  sběrnice D-Bus je na stroji vydání prázdné pole (`@as []`); stejně selže
  test přeložený vydaným 0.10.6, nejde o regresi.
- TLS proti jiným implementacím: `openssl s_client` (mTLS, ALPN,
  `TLS_AES_256_GCM_SHA384` předností serveru, ač klient preferoval
  AES-128) a Python `ssl` (TLS 1.3, ALPN `luxdrop/1`, otisk SPKI
  připnutého klíče sedí). `crypto`: certifikát přečte `openssl x509`
  (v3, ecdsa-with-SHA256, CA:FALSE kritické, platnost 100 let)
  a `openssl verify` ho přijme jako sebou podepsaný. `mdns`: služby
  oznámené čistým mDNS vidí `avahi-browse`; hledání najde běžící Python
  LuxDrop přes odpovědi Avahi.
- `build-*.json` (v `build/dist/staging/*/build.json` při sestavení):
  `build_target_tools.py --layout` pro Linux aarch64 a riscv64, Windows x64
  a arm64, macOS arm64 a x86_64, nástroje přeložené vydaným x86_64
  překladačem. Na stroji vydání není qemu ani wine: nativní běh těchto
  balíků ověřený není (CI `targets`/`release-native` neběželo).
- `performance-vs-0.10.6.json`: CPU čas (user+sys) dětských procesů,
  11 střídavých kol, vydané binárky 0.10.6 (klíč `090`) proti 0.10.7
  (`091`). Běh programů beze změny nebo rychlejší (pfmt −23 % díky
  lineárnímu strip/výřezu, dictionary_access −3 až −6 %). **Překlad malých
  programů je o 3–12 % pomalejší**: s dynamickou stdlib 0.10.6 je nový
  překladač stejně rychlý jako 0.10.6, zpomalení dělá větší
  `dynamic_stdlib.lsl` (+121 řádků: nové pomocné funkce instancí, args,
  remove_path, výřezu a nápovědy modulů), kterou překladač čte při každém
  překladu, zesílené skokovým rozpočtem GC (jedna sbírka navíc podle
  programu). Odstranění by chtělo líné parsování knihovny; v tomto vydání
  zůstává jako známá regrese.
- Neprovedeno: `verify_release.py` (migrace instalátoru), podpis
  aktualizačního kanálu `lsl update` (klíč na stroji vydání není; kanál
  zůstává na 0.10.6).
