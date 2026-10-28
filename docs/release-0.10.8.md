# Release LSL 0.10.8

Vydáno 28. 10. 2026. Backend LuxIR 0.4.4 (beze změny).

Rychlejší překlad: proti 0.10.7 o 22–33 %, proti 0.10.6 o 19–29 % CPU
času u malých a středních programů; velký program (LuxIR, 148 tisíc řádků)
o 5 %. Překladač generuje stejný kód jako 0.10.7 a běh programů se
nemění. Odstraňuje zpomalení překladu z 0.10.7.

## Co se zrychlilo

- **GC překladače:** krátce běžící nástroje (`lslc`, překlad v `lsl`) si
  zvýší nejmenší rozpočet GC mezi sbírkami z 2 na 64 MiB
  (`rt_runtime_gc_floor`, interní runtime). Malý překlad tak ušetří
  13–17 % CPU za 7–18 MiB paměti navíc. Běžné programy mají dál 2 MiB
  a stejně malou paměť.
- **Sémantická analýza:** průchod hledající mazání globálů vynechá funkce
  dynamické knihovny (mažou jen položky slovníků) a odvození návratových
  typů neprochází znovu funkce, jejichž výsledek už je v memo. Každý
  překlad ušetří asi 15 ms.
- **Parser:** operand bez následujícího binárního operátoru (většina)
  projde jedním voláním místo deseti úrovní priorit a přiřazení nebo výraz
  nezkouší postupně všechna klíčová slova příkazů. Parser je o 20 %
  rychlejší, strom je stejný.
- **Lexer:** dvou- a tříznakové operátory se poznají podle bajtů bez
  skládání kandidátních Stringů a jednoznakové ověří tabulka.

## Ověření

Všech 186 přeložitelných programů z `tests/` a `tests/gnu/` dává s novým
překladačem bajtově shodné binárky jako s překladačem 0.10.7 nad stejným
runtime (25 negativních testů selže shodně). Runtime 0.10.8 se od 0.10.7
liší jen tím, že GC čte nejmenší rozpočet z proměnné (výchozí 2 MiB). Podrobnosti a měření v `tests/release/0.10.8/README.md`.

## Známá omezení

- Většinu času malého překladu dál tvoří analýza celé dynamické knihovny
  (asi 150 funkcí) při každém překladu; načítat jen použité funkce by
  překlad malých programů zrychlilo ještě několikrát, chce to ale změnit
  ošetření chyb ve validaci (`unsupported` ukončí proces).
- Podepsaný kanál `lsl update` zůstává na 0.10.6.
