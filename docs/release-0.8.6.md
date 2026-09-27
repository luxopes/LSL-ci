# Release LSL 0.8.6

Vydání zaměřené na pohodlí při psaní a spouštění programů: hromadné
importy, uvozovky uvnitř Lux Stringů, barevný interaktivní režim, editor
`lsl --tui`, formátovaný offline manuál, `lsl about` a průběh instalace
v procentech. Compiler i host runtime zůstávají pure LSL.

## Jazyk

- **Více modulů v jednom `load`:** `load os, time` načte oba moduly pod
  jejich vlastními jmény. Na jednom řádku smí být nejvýše 32 modulů.
- **Společný alias:** `load time, os as a` zpřístupní oba moduly pod `a`.
  Člen `a.monotonic()` se hledá v uvedených modulech v pořadí; první modul,
  který jméno exportuje, vyhrává. `from X load y as z` zůstává beze změny.
- **Uvozovky uvnitř interpolace Lux Stringu:** `l"{"a" * x}"` je jeden
  literál. Lexer uvnitř `{...}` sleduje vnořené závorky a vnitřní řetězcové
  literály (oběma druhy uvozovek), takže funguje i `l"{ {"k": 1}["k"] }"`,
  vnořený `l"{l"in {x}"}"` nebo `l"{"}" + "{"}"`. Dosavadní zápis
  `l"{x + \"a\"}"` i `{{`/`}}` pro doslovné závorky fungují dál. Neuzavřená
  interpolace končí `E0001 unterminated String literal`.

## CLI

- **Interaktivní režim** (`lsl` bez argumentů na terminálu) má vlastní
  řádkový editor: zvýrazňování syntaxe během psaní, historii (šipky
  nahoru/dolů), pohyb kurzoru, Home/End, Tab jako čtyři mezery a barevné
  prompty. Uvnitř bloku (`if`, `function`, `while`, `for`, `loop`, `try`,
  `safe`, `unsafe`, `class`) se zobrazí `...` a řádek se předodsadí; `end`
  blok uzavře. `exit` nebo Ctrl-D program přeloží a spustí, Ctrl-C smaže
  rozepsaný řádek. Pipe, heredoc a `TERM=dumb` používají původní prostý
  vstup; bez `stty` se také použije prostý vstup.
- **`lsl --tui [SOUBOR]`:** terminálový editor ve stylu Vimu. Normální mód:
  `h j k l` a šipky, `w b 0 $ gg G`, PgUp/PgDn, `x`, `dd`, `yy`, `p P`,
  `o O i a A I`, `u` (zpět), `/text` a `n`, `:w [SOUBOR]`, `:q`, `:q!`,
  `:wq`. Vkládací mód: text, Enter s automatickým odsazením, Backspace
  spojuje řádky, Tab vloží čtyři mezery, Esc vrací do normálního módu.
  Řádky jsou zvýrazněné stejným způsobem jako v interaktivním režimu.
  Soubory do 4 MiB; editor nic nespouští ani nevolá shell.
- **`lsl man` formátuje Markdown:** nadpisy, odrážky, číslované seznamy,
  kódové bloky, tabulky se zarovnanými sloupci, inline kód, tučné písmo
  a odkazy se zobrazí jako terminálové formátování místo surového textu,
  v prohlížeči i v `lsl man --plain`. Bez terminálu (pipe, `NO_COLOR`)
  zůstává struktura, jen bez barev.
- **`lsl about [KNIHOVNA]`:** bez argumentu vypíše, co LSL je, verzi, web
  a licenci. S názvem vypíše krátký popis knihovny: vestavěné knihovny
  mají popisy zabudované, knihovny z registru (`lsl install NAME`) se
  popisují úvodním komentářem svého zdroje. Stejný popis začíná výstup
  `help("knihovna")` v programu; `help()` tak nově funguje i pro
  nainstalované uživatelské knihovny.
- **Průběh v procentech:** `lsl-install` zobrazuje průběh kopírování
  souborů, `lsl update` průběh stahování archivu i následné instalace.
  Na terminálu se procenta přepisují na místě; v pipe se nic nevypisuje
  (installer hlásí prosté řádky `progress NN`, které updater převádí).

## Kompatibilita

Generovaný kód, runtime ani ABI se nemění; programy přeložené 0.8.5 není
nutné překládat znovu. Zdrojové programy, které používaly `load a as x`
vícekrát se stejným aliasem, dostanou nově sloučený alias místo tichého
přepsání posledním modulem.

## Ověření

Regrese: `tests/module_group_conformance.lsl` (hromadné importy, sdílený
alias, uvozovky v interpolaci), rozšířené negativní případy v
`tests/compiler/language_extensions_negative.lsl` a CLI kontroly
(`about`, `--tui` bez terminálu, formátovaný manuál, `help()` knihoven)
v `tests/compiler/cli_080_conformance.lsl`. Interaktivní režim, editor,
stahování i instalace byly ověřeny pod pseudoterminálem.

## Přechod

Aktualizujte LSL příkazem `lsl update` (u systémové instalace
`sudo /usr/local/bin/lsl update --system`).
