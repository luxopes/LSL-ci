# LSL 0.7.4

LSL 0.7.4 je oprava `String.split`. Chybu odhalilo zátěžové testování HTTP
uploadů: `split` na velkém obsahu běžel kvadraticky a na jakémkoli
víceb bajtovém UTF-8 Stringu vracel chybné kousky.

## Hlavní změny

- `String.split` nyní pracuje čistě po bajtech: hranice odděluje bajtovým
  porovnáním a kousky staví byte-přesnou kopií rozsahu. Předchozí
  implementace probovala bajty, ale kousky řezala code-point slicingem,
  takže pro každý String s víceb bajtovým znakem vracela špatné hranice
  (`("žá" + LF + "bc").split(LF)` vracelo `["žá" + LF + "b", ""]`) a každý
  kousek platil code-point průchod od začátku Stringu — na velkých vstupech
  kvadratický čas (200 KB textu přes 20 s; 9 MB prakticky nikdy).
  Opravená verze je lineární: 200 KB za ~0,2 s, 1 MB za ~1 s, a výsledky
  jsou shodné s dokumentovanou sémantikou (`"xx".split("x")` je
  `['', '', '']`, víceb bajtový oddělovač funguje).
- Nová konformance `tests/string_split_conformance.lsl` pokrývá víceb bajtové
  kousky i oddělovače, prázdné kousky, chybějící oddělovač a lineární čas na
  2000řádkovém vstupu.
- Rozpočet velikosti optimalizovaného standalone ELF v test runneru se
  zvedl z 97 000 na 98 000 bajtů: byte-přesný split helper připojený ke
  každému programu stojí ~250 bajtů.

## Ověření vydání

Vydání prošlo bitově shodným self-host fixed pointem, plnou testovací
sadou včetně nové split konformance, porovnáním configu a kontrolou release
ELF. Compiler má SHA-256
`b96874ce0c3c729c4111297491ba418506d81639ca1fe710bb5adeafd0ff8296`, CLI
`b730d9d8a9d1e9032b67bf1f7481a4720838cdcc91494ba94d02404c9c66fb83` a test
runner `f184a95393d0e1786d3867f099dc2773032c31a3a7a99fc56ff4b4321a996770`.

## Kompatibilita

Programy, které obcházely chybné víceb bajtové chování vlastním kódem,
mohou nyní používat `split` přímo. Známé zbývající výkonnostní téma:
`find`, `replace` a jednotlivá code-point indexace velkých Stringů zůstávají
lineární na přístup (tedy potenciálně kvadratické ve smyčkách); oprava
patří do navazujícího vydání.
