# Release LSL 0.9.2

Opravné vydání pro **Linux x86_64**: všech 34 nálezů auditu 0.9.1
(AUD-091-01 až AUD-091-34) a kontrakt C01, plus otevřené body 0.9.2 z TODO.

## Jazyk a převody

- Rozbalení `a[1], a[0] = a` nejdřív přečte všechny prvky (dříve se mohla
  přepsat ještě nepřečtená hodnota).
- Převod desetinného textu na Float (`Float(text)`, literály, `json.decode`)
  je správně zaokrouhlený: nativní Clinger + Eisel-Lemire s tabulkou
  128bitových mocnin pěti; vstupy nad 19 číslic rozhoduje nativní přesné
  porovnání bez alokace (nejvýš 800 platných číslic, zbytek jako lepivá
  číslice). `Float("0.49999999999999994")` už není 0.5, dlouhé zápisy čísla
  1 nejsou NaN ani nekonečno. Parser čte bajty, takže je lineární i u
  zápisů o 4096 znacích.
- `String(Float)` dává stejné číslice jako `repr` v Pythonu: nejkratší zápis,
  který se převede zpět na stejný double, a z platných kandidátů ten
  nejbližší skutečné hodnotě (při shodě sudý), včetně přenosu přes řád
  (`1e-300` místo `9.9999999999999999e-301`). Celočíselné hodnoty se dál
  vypisují celé (`1e16` → `10000000000000000.0`).
- Běhové i překladové chyby indexu uvádějí skutečný typ:
  `sequence index must be Int, got String`.

## Knihovny

- `math`: `round`/`trunc` bez přetečení pro libovolné `digits`, přesné
  zaokrouhlení velkých Int; `floor`/`ceil` hlásí NaN, nekonečno a hodnoty
  mimo Int; `exp` do 1 ulp i u hranic a subnormálů; `hypot`, `mean`,
  `median` bez mezipřetečení; `sin`/`cos` s přesnou redukcí velkých
  argumentů; `is_close` ošetřuje NaN a nekonečna; `gcd`/`lcm` hlásí
  přetečení.
- `time`: rozsah UTC [rok 1, rok 10000), stejný pro `iso8601` i
  `parse_iso8601`.
- `httpserver`: názvy hlaviček podle tchar, odmítnutí CR/LF/NUL v hodnotách,
  validace metody a targetu, odpovědi 1xx/204/304 bez těla; nový worker
  pool `serve_workers` / `serve_listener_workers`.
- `configure`: úplná kontrola čistoty (printr, monotonic, cpu_count …),
  blokové komentáře, escaped a raw řetězce, exporty z tokenů, Float options,
  bezpečný sentinel, `mkIf` v Listu, zachování priority při merge,
  kontrola defaultu.
- `bigint` odmítá nekánonický stav, `json` přesně dodržuje limit 4 MiB.
- Průchod `for c in text` a `find`, `count`, `startswith`, `endswith`,
  `replace` jsou lineární (1 MiB za ~90 ms místo kvadratického času).

## Nástroje a testy

- `tools/qbe/verify.py` a `verify_image.py` fungují i z čistého release
  checkoutu (`--runtime`, výchozí `compiler/qbe/runtime.o`).
- Nové regrese: `tests/audit_092_conformance.lsl`, HTTP a pool v
  `httpserver_conformance`, konfigurační případy `tests/config/092/`,
  fault injection větve fork `tests/process_fork_fault_conformance.lsl`.

## Překladač

- Funkce dynamické knihovny se při překladu přes LuxIR sémanticky analyzují
  a validují až při prvním použití generátorem kódu (dosud všech ~140 při
  každém překladu). Výstup je bajtově shodný s úplnou analýzou (ověřeno na
  405 zdrojích repozitáře včetně překladače).
- Opakovaná inference návratových typů přebírá výsledky funkcí, jejichž
  vstupy (typy parametrů, čtené globály, závislosti) se nezměnily; shoda s
  úplným výpočtem ověřena na stejném korpusu.
- Smyčka `for x in rang(...)` s krokem zapsaným literálem (výchozí 1, např.
  `-2`) testuje konec jediným porovnáním místo výběru podle směru kroku:
  `intarray_access` −16 %, `allocation_gc` −12 %, `dictionary_access` a
  `string_split_join` −7 %. Chování (včetně nulového kroku a hodnoty po
  smyčce) je beze změny, regrese `tests/rang_constant_step_conformance.lsl`.
- Záložní LSL implementace nových intrinsiců nejsou součástí knihovny;
  bootstrap vychází z dodaného `compiler/lslc` verze 0.9.2.

## Výkon

Překlad i běh nejsou pomalejší než 0.9.1 (CPU čas, střídavá měření, viz
`tests/release/0.9.2/`). Malý program se přeloží o ~20 % rychleji, běžné
benchmarky o ~5 %. Převod textu na Float je 3–4× rychlejší (dlouhé zápisy až
24×), formátování Floatu 1,4–2,6× rychlejší. Každá nativní binárka je o
~12 KB větší (tabulka mocnin pro přesný převod je v runtime).

## Známá omezení

- Fault injection větví wait a read zůstává otevřený (vyžaduje obsluhu
  signálů nebo syscallový hook v runtime).
