# LSL 0.9.2 — Linux x86_64 release evidence

- `build.json`: `build_release.py --seed build/dev/lslc2` (self-hosted
  frontend 0.9.2). Frontend i backend fixed point bajtově shodné.
- `performance-vs-0.9.1.json`: CPU čas (user+sys) každého dětského procesu,
  11 střídavých kol, vydané binárky 0.9.1 proti 0.9.2 (klíče `090` = 0.9.1,
  `091` = 0.9.2, popisky skriptu). Mediány překladu: −2 % až −23 % u všech
  11 vstupů. Velký zdroj (překladač 0.9.1, 7 střídavých běhů): 6921 ms →
  6638 ms (−4,1 %). Běh: převod textu na Float −72 %, formátování −29 %,
  intarray_access −16 % (podmínka smyčky rang), dictionary_access −6 %.
  Hlučné úlohy přeměřeny 41 střídavými běhy připnutými na jedno jádro
  (`taskset`): allocation_gc −2,6 %, integer_loop a list_access ±0,1 %;
  string_split_join má v krátkém běhu dvouvrcholové rozložení (medián
  +12,7 %, minimum 102,5 → 102,0 ms, 0.9.2 rychlejší v 19/41) a v delším
  běhu (500000) −3,2 % (rychlejší v 8/11). function_calls je omezen
  latencí výpočtu v `mix` (~6 taktů/iteraci), strojový kód smyčky je
  shodný; 31 běhů po 200 M volání: +0,3 % (rychlejší v 18/31).
- Líná analýza knihovny a memo inference návratových typů: výstupy 405
  zdrojů repozitáře (testy, příklady, stdlib, překladač) jsou bajtově
  shodné s úplnou analýzou; ověřovací build porovnával výsledek inference
  s memem a bez něj na stejném korpusu bez rozdílu.
- `verification.json`: úplný `verify_release.py` preflight, všechny brány
  PASS (korpus a oba fixed pointy, managed instalace, izolovaná migrace z
  0.8.9 se dvěma reinstalacemi a rollbacky, hardening obrazu, veřejné CLI a
  registrované nativní regrese). `native-image.json` a `original-runner.json`
  jsou podrobné reporty bran obrazu a původního korpusu.

Stroj: notebook Ryzen 5 5500U, škálování frekvence; jednotlivé vzorky se
liší až o ±10 %, smysl mají jen mediány a rozložení.
