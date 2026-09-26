# Release LSL 0.8.5

Vydání zaměřené na rychlost a paměťovou náročnost samotného compileru.
Jazyk, standardní knihovna, runtime ABI ani generovaný kód se nemění:
compiler 0.8.5 vytváří pro stejný zdroj bajt po bajtu stejnou binárku jako
compiler 0.8.4. Compiler i host runtime zůstávají pure LSL.

## Rychlejší compiler

Tři vrstvy compileru byly přepsány na konstrukce, které v jazyce v době
jejich vzniku ještě nebyly:

- **Emit vrstva** (`assembler`, `bytes`, `elf_image`) skládá strojový kód,
  datovou sekci i výsledný ELF obraz v `ByteArray` místo `List[Int]`.
  Každý emitovaný bajt byl dříve samostatný boxovaný Int, který musel
  každý úklid paměti projít; nyní je to jeden souvislý buffer, který
  garbage collector nevidí. Kodéry instrukcí v `x86_64` dál vracejí krátké
  seznamy, assembler je kopíruje typovanou smyčkou.
- **Lexer** čte zdroj po UTF-8 bajtech přes textové intrinsics místo
  materializace jednoho `String` na každý znak (`__lsl_string_chars`).
  Hodnoty tokenů vznikají z `ByteArray`; sloupce v diagnostice dál počítají
  znaky, ne bajty. Tokenový výstup je shodný s 0.8.4 na všech 353 zdrojích
  v repozitáři včetně negativních testů a na 1 500 náhodných vstupech.
- **Dávkový úklid v codegenu** se škáluje s velikostí programu: úklid po
  každých 32 dokončených funkcích, u větších programů po pětině počtu
  funkcí (self-host build ~130). Každý úklid značkuje celý živý AST bez
  ohledu na to, kolik funkcí od minula přibylo; u self-host buildu tak
  18 úklidů po ~150 ms kleslo na 4. Malé programy naopak těží z častého
  opětovného použití paměti, proto u nich dávka zůstává 32.

Profil self-host buildu ukázal, že dominantní cenou nebylo samotné
emitování bajtů, ale úklid paměti: ruční `gc()` v codegenu a automatický
úklid během parsování. Změna dávky proto přináší největší část zrychlení,
`ByteArray` buffery snižují objem živých objektů, které každý úklid
prochází, a lexer snižuje objem alokací v první fázi překladu.

## Měření

Mediány pěti sériových překladů na stejném Ryzen 5 5500U, Linux x86_64,
pod `ulimit -v 2 GiB`. Compiler 0.8.4 z vydání a compiler 0.8.5 (stage 3)
nad stejnými zdroji 0.8.5; RSS je špička rezidentní paměti compileru.

| Překlad | 0.8.4 | 0.8.5 | Zrychlení | RSS 0.8.4 | RSS 0.8.5 |
| --- | ---: | ---: | ---: | ---: | ---: |
| self-host `lslc_direct.lsl` | 8.235 s | 5.711 s | 1.44× | 787 MiB | 679 MiB |
| CLI `cli.lsl` | 10.870 s | 7.236 s | 1.50× | 872 MiB | 712 MiB |
| `examples/terminal_snake.lsl` | 1.161 s | 0.998 s | 1.16× | 153 MiB | 135 MiB |
| `print "hi"` | 0.450 s | 0.384 s | 1.17× | 85 MiB | 66 MiB |

Výstupní binárky obou compilerů jsou pro každý z těchto zdrojů shodné.
Compiler 0.8.5 přeložený compilerem 0.8.4 (stage 1) je bajt po bajtu
shodný se stage 2 a 3. Plná testovací sada prošla se stejným výstupem jako
u 0.8.4; nový lexer dává na 353 zdrojích repozitáře i 1 500 náhodných
vstupech (platné UTF-8) stejné tokeny a stejné diagnostiky jako starý.

## Neplatné UTF-8 ve zdroji

Zdrojové soubory mají být platné UTF-8. Dřívější lexer dekódoval přes
`__lsl_string_chars`, a tak přijal přeplněnou („overlong“) dvoubajtovou
sekvenci jako znak identifikátoru, pokud se dekódovala na ASCII písmeno.
Nový lexer takový bajt hlásí jako `E0006 unexpected character`. Platné
UTF-8 zpracovávají oba lexery identicky; rozdíl je pouze v tom, jak se
neplatné bajty zobrazí ve zdrojovém řádku diagnostiky.

## Přechod

Aktualizujte LSL příkazem `lsl update` (u systémové instalace
`sudo /usr/local/bin/lsl update --system`). Samostatné binárky vytvořené
příkazem `lsl compile` není nutné znovu překládat: 0.8.5 generuje stejný
kód i runtime jako 0.8.4. Grafické knihovny zůstávají volitelnými balíčky.
