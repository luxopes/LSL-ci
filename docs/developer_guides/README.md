# LSL — Vývojářské příručky

> **LSL 0.8.9 — automatické .env, requests a manuály knihoven.**
> [Historie verzí](/releases/) · [Manuál 0.5](/releases/0.5/) ·
> [Manuál 0.6](/releases/0.6/) · [Manuál 0.6.5](/releases/0.6.5/) ·
> [Changelog](CHANGELOG.md)
> [Stáhnout binárky nebo zdrojový kód](index.html#downloads).

Podrobné průvodce LSL (Lux Simple Lang) 0.8.9. Každá kapitola
vysvětluje jednu oblast od základů — text předpokládá, že s programováním
teprve začínáte. Všechny konstrukty jsou popsány srozumitelně: co dělají,
k čemu slouží, jak se zapisují a jak fungují.

## Obsah

Nově: [AI knihovna 1.1.0 s nástroji](ai.md) — nativní function calling,
živé streamování tool callů — a nová [knihovna shell](shell.md) pro běh
příkazů s potlačeným prostředím.

Nově: [env a automatické .env](env.md), [HTTP klient requests](requests.md)
a samostatné manuály všech veřejných standardních knihoven v `lsl man KNIHOVNA`.

Nově: [kontrola inicializace, typové deklarace, ++/-- a system()](reference.md).
`clock()` nyní vrací čitelný UTC String; pro intervaly použijte `monotonic()`
nebo `time.perf_counter()`. Před upgradem aktualizujte nainstalované X11
příkazem `lsl update x11`; nová knihovna podporuje i LSL 0.8.2.
Dále: rozšířené [zpracování chyb](05-error-handling.md) a volitelné
[grafické balíčky](09-gui-programming.md).
Dále: [CLI, knihovny a terminálový manuál](17-cli-and-packages.md).
Dále: [Random — náhodná čísla a výběry](16-random.md),
list/dict comprehensions v kapitole [Kolekce](04-collections.md) a
výchozí/pojmenované argumenty v kapitole [Funkce](03-functions-and-classes.md).

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

13. **[Server a původ knihoven](13-server-and-origin.md)**
    Nativní HTTP/HTTPS server, bezpečné publikování souborů, příkaz
    `lsl origin` a ověřování původu nainstalovaných balíčků.

14. **[Sandbox a bezpečnost](14-sandbox-and-safety.md)**
    Capability sandbox, omezení zdrojů, bezpečný výchozí režim compileru,
    explicitní `unsafe:` hranice a omezení ochrany paměti v LSL 0.7.

15. **[CUDA a GPU tenzory](15-cuda.md)**
    Persistentní sessions, Float64 buffery, DeviceTensor, CPU fallback,
    životnost prostředků, protokol a hardwarové testy.

16. **[Random](16-random.md)**
    Reprodukovatelné seedy, MT19937, SystemRandom, kolekce a rozdělení.

17. **[CLI, knihovny a terminálový manuál](17-cli-and-packages.md)**
    List/search/check, TUI instalátor, offline manuál, barvy a `help("téma")`.

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
- [Server a původ knihoven](13-server-and-origin.md) — HTTP/HTTPS a provenance balíčků
- [Sandbox a bezpečnost](14-sandbox-and-safety.md) — izolované spouštění a unsafe hranice
- [Bezpečnostní model](security.md) — safe/unsafe, capability sandbox a native ABI
