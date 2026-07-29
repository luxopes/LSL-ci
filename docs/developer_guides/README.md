# LSL — Vývojářské příručky

> **LSL 0.6 — self-hosted release s Lux Stringy, aliasy modulů a skutečným NVIDIA CUDA Runtime backendem.**
> [Stáhnout binárky, zdrojový kód nebo offline manuál](index.html#downloads).

Podrobné průvodce jazykem LSL (Lux Simple Lang) 0.6. Každá kapitola
vysvětluje jednu oblast od základů — text předpokládá, že s programováním
teprve začínáte. Všechny konstrukty jsou popsány srozumitelně: co dělají,
k čemu slouží, jak se zapisují a jak fungují.

## Obsah

1. **[Začínáme s LSL](01-getting-started.md)**
   Co je programování, první program, terminál, proměnné, vstup/výstup,
   podmínky, smyčky, argumenty — vše krok za krokem pro úplné začátečníky.

2. **[Základy jazyka](02-language-basics.md)**
   Podrobný výklad každého konceptu: co je proměnná, typ, operátor,
   jak funguje `print`, `input`, `if`, `for`, `while`, `break` a další.

3. **[Funkce a třídy](03-functions-and-classes.md)**
   Proč a jak psát funkce, co jsou parametry a návratové hodnoty,
   first-class callbacky, třídy a instance, moduly pro organizaci kódu.

4. **[Kolekce a datové struktury](04-collections.md)**
   Kdy použít List, Tuple, Dictionary, IntArray, FloatArray nebo
   ByteArray — srozumitelný výklad každé kolekce a jejich metod.

5. **[Zpracování chyb](05-error-handling.md)**
   Safe bloky, try/else, Error, check, last_error(), chybové vzory.

6. **[Moduly a standardní knihovny](06-modules-and-imports.md)**
   Modulový systém, přehled všech stdlib modulů, instalace uživatelských
   knihoven.

7. **[Soubory, I/O a procesy](07-files-io-and-processes.md)**
   Souborový systém, textový a binární I/O, spouštění programů (os,
   process), HTTP, proměnné prostředí.

8. **[Konfigurační systém](08-configuration-system.md)**
   Deklarativní konfigurace, merge, options, assertions, lazy hodnoty,
   reprodukovatelnost.

9. **[GUI programování](09-gui-programming.md)**
   Display, gfx, ui, css, input — kompletní tvorba grafických aplikací
   včetně liquid glass designu.

10. **[AI aplikace](10-ai-applications.md)**
    OpenAI-compatible API, streaming, HTTP, JSON, secrets management,
    function calling.

11. **[Výkon a optimalizace](11-performance-and-optimization.md)**
    Automatické optimalizace compileru, typovaná pole, bulk kernely,
    tenzory, plugin ABI, benchmarking.

12. **[Interní architektura compileru](12-compiler-internals.md)**
    Pipeline, mapa zdrojových souborů, self-host, fixed-point, ABI,
    garbage collector, jak přidat jazykovou vlastnost.

## Referenční příručka

- **[Kompletní reference všech funkcí](reference.md)** — abecedně řazený
  seznam každé built-in funkce, metody a exportu standardních modulů s
  popisem.

## Doporučené rozcestníky

- [Kompletní reference](reference.md) — funkce, typy, metody a moduly
- [Základy jazyka](02-language-basics.md) — syntaxe a řízení programu
- [Konfigurační systém](08-configuration-system.md) — deklarativní konfigurace
- [GUI programování](09-gui-programming.md) — okna, grafika a widgety
- [AI aplikace](10-ai-applications.md) — AI orchestrace
- [Výkon a optimalizace](11-performance-and-optimization.md) — měření a optimalizace
- [Interní architektura compileru](12-compiler-internals.md) — compiler, runtime a ABI
