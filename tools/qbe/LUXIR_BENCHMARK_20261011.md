# LuxIR proti LSL 0.8.9 — měření 11. 10. 2026

Nová větev funguje a ve všech osmi těchto úlohách vytváří rychlejší programy než 0.8.9. Překlad velkého společného zdroje ale zůstává pomalejší: **11.399 s proti 8.062 s**, tedy **+41.4 % času**. Toto měření proto nepotvrzuje vyřešení výkonu kompilace velkých projektů.

## Měřená sestava

- Frontend `luxir/frontend`: `5318b1a89d0b87bae10fc8b274360b34d91bfc25`.
- Backend [LuxAI/LuxIR](https://git.lux-ai.cz/LuxAI/LuxIR): `7480a0fe0a70ec9525cbae7363cf9da457194fce`.
- Linux x86_64, Intel(R) Core(TM) i5 CPU         760  @ 2.80GHz, 4 CPU.
- Původní nainstalované `~/.local/bin/lslc` 0.8.9 zůstalo beze změny; SHA-256 `f235b42d4998474c1bfee7eb02f17625bbc824f647f9ba33bdef8c20b0ff8696`.
- Nový frontend SHA-256 `ca3e171e5523e3ba51906f9b4224040d3c036cf05fbe1f842c4979eb2b8cf566`; native LSL LuxIR `33723db8368e75bbd3609ded54753e0a2cd0595ea981020731785ae38558850e`.
- Každý měřený překlad používá nativní LuxIR napsaný v LSL. C reference byla použita pouze při prvním bootstrapu backendu. V měření není fallback na C backend.

## Čas překladu

Tři opakování, střídání pořadí, medián celého překladu ze zdroje až do ELF, včetně backendu, assembleru, linkeru a spuštění procesů. Obě verze dostávají stejný zdroj. Každý proces v benchmarku má limit adresního prostoru 4 GiB.

| Vstup | LSL 0.8.9 | LSL + LuxIR |
|---|---:|---:|
| Společný zdroj kompilátoru 0.8.9 včetně importů | 8.062 s | 11.399 s |
| Osm malých benchmarků, rozsah mediánů | 0.547–0.554 s | 0.526–0.552 s |

Společný velký vstup: `~/.local/lib/lsl/compiler/pure/lslc_direct.lsl`, SHA-256 `ca5306deaf8612930f7648df9f5540faba69de2c78a9fa604b29fdded1452418`. Vlastní zdroje obou verzí mají rozdílnou strukturu; jejich oddělené self-host časy by nebyly srovnáním stejného vstupu.

## Běh výsledných programů

Pět opakování, střídání pořadí, stejný počet iterací pro obě verze. Uveden je medián v **milisekundách**, včetně spuštění procesu. Pilotní kalibrace nastavuje společné iterace přibližně podle pomalejší verze; nezávisle spočítané kontrolní výsledky prošly u všech běhů.

| Úloha | Iterace | 0.8.9 [ms] | LuxIR [ms] | Poměr časů 0.8.9/LuxIR |
|---|---:|---:|---:|---:|
| Celočíselná smyčka | 95,868,967 | 382.504 | 288.909 | 1.32× |
| Volání funkcí | 1,056,219 | 334.673 | 5.845 | 57.25× |
| Float aritmetika | 548,383 | 114.020 | 42.797 | 2.66× |
| IntArray | 5,000,000 | 74.620 | 48.000 | 1.55× |
| List | 864,861 | 234.594 | 144.271 | 1.63× |
| Dictionary | 486,687 | 211.170 | 160.961 | 1.31× |
| String split/join | 48,933 | 398.875 | 182.508 | 2.19× |
| Alokace a GC | 410,817 | 337.833 | 319.660 | 1.06× |

Výsledky zahrnují rozdíly celých verzí: frontendu, stdlib i runtime. Uvedené poměry platí pro konkrétní měřené úlohy. Nejrychlejší výsledek trvá jen několik milisekund a zahrnuje start procesu. Uživatelský Firefox/X11 běžel dál; jiné kompilace a benchmarky se s tímto měřením nepřekrývaly.

## Ověření

- 8/8 benchmarků: správné výsledky, všechna opakování překladu i spuštění dokončena.
- 43/43 existujících jazykových regresí novým frontendem a nativním LuxIR.
- 6/6 spustitelných programů LuxIR a 36/36 očekávaných chybových vstupů.
- Frontend generace 1/2/3 bajtově shodný; měřené vlastní překlady dalších generací 6.290 s a 6.314 s.
- Backend generace 1/2/3 bajtově shodný; další generace přes nativní LuxIR 40.312 s a 40.322 s. To jsou jednotlivé časy frontendu a backendu, nikoli nově měřený jeden souvislý generační interval.
- Runtime znovu vygenerován novým frontendem a nativním LuxIR; objekt je bajtově shodný s runtime použitým v benchmarku (`23a85294…`).

Záznamy obsahují všechny vzorky, příkazy, návratové kódy, hashe a výstupy kontrol: [benchmark](../../tests/qbe_port/comparison-v089-luxir-linux-x86_64.json), [sestavení a fixed points](../../tests/qbe_port/luxir-selfhost-linux-x86_64.json), [regrese a čerstvé ověření runtime](../../tests/qbe_port/luxir-benchmark-checks-linux-x86_64.json).

Opakování benchmarku po sestavení podle [CLI.md](CLI.md):

```sh
python3 tools/qbe_port/compare_v089.py \
  --old "$HOME/.local/bin/lslc" \
  --new build/luxir-benchmark/frontend3 \
  --backend build/luxir/luxir3 \
  --new-label luxir_lsl \
  --build-directory build/luxir-benchmark/comparison \
  --compile-repeats 3 --run-repeats 5 \
  --large-source "$HOME/.local/lib/lsl/compiler/pure/lslc_direct.lsl" \
  --report tests/qbe_port/comparison-v089-luxir-linux-x86_64.json
```
