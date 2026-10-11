# Release LSL 0.9.1

11. října 2026. Stabilní vydání pro **Linux x86_64**; nahrazuje podepsaný
stabilní kanál 0.8.9. Překladová cesta je stejná jako v 0.9.0 BETA:
LSL frontend, mezivýstup LuxIR, nativní backend LuxIR v LSL a GNU `as`/`ld`.

## Výkon

Překlad i běh programů jsou stejně rychlé nebo rychlejší než 0.9.0. Měřeno
jako CPU čas se střídáním verzí na stejném stroji: malý program −3 %, osm
srovnávacích programů −0,5 až +0,2 %, velký zdroj kompilátoru −0,1 % (medián),
běh srovnávacích úloh beze zpomalení. Výpis nezachycených chyb je v nativním
runtime, explicitní `gc()` mezi fázemi frontendu odpadl a runtime je zarovnaný
na 64 B, takže jeho výkon nezávisí na velikosti programu.

## Jazyk

- Přiřazení více proměnným: `a, b = 1` přiřadí stejnou hodnotu všem cílům,
  `x, y = 1, 2` po dvojicích (hodnoty se vyhodnotí předem, takže
  `x, y = y, x` prohodí), `p, q = [3, 4]` rozbalí List nebo Tuple.
  Nesoulad počtu je `E1245` při překladu, případně
  `ValueError: expected N values, got M` za běhu.
- Rozbalení ve `for`: `for klic, hodnota in slovnik.items():`.
- Vnořené `for` se stejným jménem proměnné mají nezávislé čítače.
- `global x` uvnitř funkce; zápis do jména globálu bez deklarace hlásí
  varování `W2004` (program se přeloží).
- Blok `lock zamek[, slot]: ... end` uvolní spinlock nad `IntArray` i při
  chybě; `return`/`break`/`continue` ven z bloku jsou `E1247`.
- Raw řetězce `r"..."`, blokové komentáře `/* ... */`, `printr`.
- `split()` bez argumentu dělí podle jedné mezery.
- Kontrola přiřazení přijme čtení po smyčce přes literálně neprázdnou
  posloupnost, pokud ji tělo přiřadí na každé cestě.

## Diagnostika

- Nezachycená běhová chyba se vypíše jako `error[Druh]` s pozicí,
  zdrojovým řádkem (jen ze souborů `.lsl`) a nápovědou; barvy podle
  `NO_COLOR`/`FORCE_COLOR`/`TERM`.
- Chyby výrazů v interpolacích hlásí skutečný řádek a sloupec.
- Pracovní vlákno ukončené chybou vypíše `LSL worker error: ...`.
- `help("neznámé")` vrací zprávu, `lsl help neznámé` končí stavem 1.
- Binárky nástrojů neobsahují absolutní cesty build adresáře.

## Knihovny

- `math.round(x, digits)`, `math.trunc(x, digits)`.
- `time.utc`, `time.iso8601`, `time.strftime`, `time.parse_iso8601`.
- `httpserver`: slučování opakovaných hlaviček podle RFC 9110,
  streamované odpovědi a Server-Sent Events.
- `load ai` použije novější `aikit` z `lsl update ai`.
- Dynamická rovnost Float hodnot odpovídá statické (IEEE).

## Známá omezení

- Převod desetinného textu na Float není u části sedmnáctimístných čísel
  správně zaokrouhlený (odchylka 1–2 ulp). LSL zápis a čtení jsou vzájemně
  konzistentní; výměna s jinými jazyky může změnit poslední bit. Plánováno
  pro 0.9.2.
- Překlad velkého zdroje compileru je pomalejší než v 0.8.9 (viz
  [benchmark](../tools/qbe/LUXIR_BENCHMARK_20261011.md)).
- Accept loop `httpserver` je jednovláknový.

## Instalace

```sh
./bin/lsl version          # 0.9.1
./bin/lsl-install "$HOME/.local"
```

Stávající stabilní instalace dostane vydání přes `lsl update`. Samostatně
zkompilované programy přeložte znovu.
