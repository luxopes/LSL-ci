# LSL 0.10.8 — release evidence

- `build.json`: `build_release.py`, frontend i backend fixed point bajtově
  shodné; LuxIR 0.4.4 beze změny. Společný pevný bod s runtime: po změně
  `runtime/gc.lsl` druhé kolo (build → přestavba runtime 12 cílů) dalo
  bajtově shodné objekty.
- Plný runner `LUXIR_SOURCE=… tests/lsl-test qbe`: `pure LSL tests passed`.
- Bundly: `wasm32-wasi` 91 z 91; `linux-x86_64-gnu` 122 ze 123 (jediné
  selhání `gio_conformance` „Features is a list“ je prostředí stroje: D-Bus
  `Features` je prázdné pole, stejně jako u 0.10.6 a 0.10.7).
- Shoda výstupu: 186 programů z `tests/*.lsl` a `tests/gnu/*.lsl`
  přeložených překladačem 0.10.7 a novým překladačem (oba linkují stejný
  runtime) je bajtově shodných, 25 negativních
  testů selže shodně (stejný text chyby).
- `performance-vs-0.10.7.json`, `performance-vs-0.10.6.json`: CPU čas
  (user+sys) dětských procesů, 11 střídavých kol, vydané binárky (`090`)
  proti 0.10.8 (`091`). Překlad: proti 0.10.7 −22 až −33 % (tiny −33 %),
  proti 0.10.6 −19 až −29 %. Běh programů beze změny (kód je shodný;
  rozdíly mediánů v jednotkách procent jsou šum, minima shodná).
- Velký program `build/dependencies/LuxIR/lsl/luxir.lsl` (148 tisíc řádků):
  0.10.7 36,1 s a 2099 MiB, 0.10.8 34,4 s a 2128 MiB.
- Rozpad malého překladu po změnách (wall, dictionary_access): lexer +
  parser knihovny ~32 ms, sémantika ~21 ms, emit ~31 ms, backend LuxIR
  ~46 ms. Další krok: líné načítání funkcí knihovny.
- Neprovedeno: nativní běh balíků pro arm64, Windows a macOS (bez qemu
  a wine), `verify_release.py`, podpis kanálu `lsl update`.
