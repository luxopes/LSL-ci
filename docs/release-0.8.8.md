# Release LSL 0.8.8

Opravné vydání, aktualizované 28. 9. 2026 o rychlejší I/O a alokátor. Compiler i host runtime zůstávají pure LSL.

## Oprava překladu: typy proměnných do fixpointu

Compiler odvozuje statické typy lokálních proměnných jedním průchodem
v pořadí zdroje. Když proměnná dostala dynamickou hodnotu až později
v kódu, dřívější výrazy s ní zůstaly přeložené jako celočíselné:

```lsl
while zbytek > 1:
    p = tabulka[zbytek]        # Int z IntArray
    delitele.append(p)
    while zbytek % p == 0:
        zbytek = zbytek // p   # přeloženo jako Int // Int ...
    end
end
for p in delitele:             # ... ale tady se p stane dynamickým
    obsazeno[p] = 1
end
```

Při emisi se `zbytek // p` vyhodnotilo dynamicky (boxovaný výsledek), ale
uložilo do surového celočíselného slotu `zbytek` — proměnná pak obsahovala
ukazatel: nesmyslné hodnoty, `IndexError` nebo zacyklení. Od 0.8.8 se
odvození typů opakuje, dokud se žádný typ nemění; rozšíření jde vždy jen
směrem k dynamické hodnotě, takže se ustálí během několika průchodů.
Programy, které chybu nespouštěly, se překládají stejně jako dosud.

Regrese: `tests/type_widening_conformance.lsl` (modulová i funkční varianta;
compiler 0.8.7 na ní visí).

## Diagnostika comprehension

`[0, for x in rang(3)]` dřív hlásilo `E1104: expected comma in List literal`,
tedy přesně opak skutečné příčiny. Nově `E1119: unexpected comma before for
in a List comprehension` s nápovědou `write [value for item in iterable]`.

## Manuál

Kapitola 11 nově začíná volbou kolekce: `IntArray` místo `List` pro velké
číselné tabulky (síto do 1 000 000: 2,5 s → 0,03 s).

## Bufferovaný stdin

`input()` četl standardní vstup po jednom bajtu jedním `read(2)` na bajt.
Je-li stdin obyčejný soubor (`./prog < data.txt`), runtime čte po 64 KiB.
Nepřečtený zbytek bufferu vrací před `run`/`capture` (dítě dědí stdin) a
před ukončením programu zpět do souboru přes `lseek`, takže potomek i další
čtenář pokračují přesně tam, kde `input()` skončil. Roura a terminál
zůstávají u čtení po bajtech (nikdy nepřečtou víc, než program spotřeboval).


Při kombinaci `input()` s přímými `fd.read`/`fd.write`/`fd.seek`/`fd.close`
runtime nejprve vrátí nepřečtená data. Po přímém syscallu, nativním volání,
spuštění dalšího vlákna nebo zavření standardního deskriptoru přejde
standardní I/O na přímý režim, aby fungovalo i přesměrování deskriptorů.

## Bufferovaný stdout

`print` posílal každou hodnotu i oddělovač samostatným `write(2)`. Jde-li
stdout do souboru, roury nebo znakového zařízení, které není terminál
(`/dev/null`), sbírá se výstup do 64 KiB bufferu. Buffer se vyprázdní před
každým místem, kde na pořadí záleží: `input()` (výzva je vidět před čekáním
na vstup), `fd.read`/`fd.write`, surové syscally, `sleep`, `run`/`capture`
(fork), `thread_spawn` (od té chvíle jde výstup přímo), nativní volání,
každý zápis na stderr včetně hlášení runtime chyb, `exit` a konec programu.
Terminál se nebufferuje, interaktivní programy se chovají stejně jako dosud.

## Alokátor a GC

- Nový blok haldy si alokátor bral dvojicí `brk(0)`/`brk(new)`; nyní
  rezervuje po 1 MiB (nedotčená rezerva nestojí paměť) a na hranici
  adresního prostoru zkusí přesnou velikost jako dřív.
- Rozpočet automatického GC počítal do „živé haldy“ i surová data typovaných
  polí, která se netrasují. Program s velkým `IntArray` tak mezi sběry
  protáčel desítky MB studené paměti. Rozpočet nyní vychází jen z
  trasovaných objektů (dolní mez 4 MiB zůstává).

## split a Int(String)

- `split` s jednoznakovým oddělovačem je jedno nativní volání
  (`__lsl_text_split_byte`); kousky vznikají nativní kopií
  (`__lsl_text_piece`) místo bajt po bajtu přes `ByteArray`.
- `Int("...")` ověří číslice a spočítá hodnotu dvěma nativními voláními
  místo alokace jednoznakového Stringu na každou číslici. Chybové hlášky,
  hranice (`+`, `-`, prázdný String, ne-ASCII) i přetečení (wrap) jsou
  stejné jako v původním sestavení 0.8.8.

## Interní

- Stav runtime: sloty 1280–1343 (režim a buffer stdin, ukazatel a konec
  brk rezervy, režim a buffer stdout); globální proměnné začínají na 1344.
- `input()` i buffer stdin se emitují jen do programů, které `input` volají
  (`stdin_release` je jinak jen `flush` + `ret`).
- Nové nativní builtiny `__lsl_text_piece`, `__lsl_text_scan_digits`,
  `__lsl_text_digits`, `__lsl_text_split_byte`. Bootstrap ze staršího
  compileru je proto dvoufázový: stage0 = nový codegen se stdlib z původního sestavení 0.8.8,
  teprve stage1 překládá novou stdlib.
- Regrese: `tests/stdio_buffer_conformance.lsl` (soubor vs. roura, předání
  zbytku vstupu potomkovi, pořadí stdout/stderr, výzva před čtením, výstup
  přes 64 KiB, `/dev/null`, hrany `split`/`Int`, alokace přes hranici rezervy).
  Fixture velikosti optimalizované binárky: limit 110 400 B (bufferovaný
  stdout, rezerva brk a nativní helpery přidaly asi 400 B).

## Přechod

Z dřívější verze použijte `lsl update` (u systémové instalace
`sudo /usr/local/bin/lsl update --system`).

Pokud už máte původní **0.8.8**, updater stejnou verzi přeskočí. Stáhněte
aktuální `lsl-0.8.8-linux-x86_64.tar.gz`, rozbalte jej a spusťte jeho
`bin/lsl-install "$HOME/.local"` (uživatelská instalace), případně
`sudo bin/lsl-install /usr/local` (systémová instalace). Instalátor zachová
předchozí generaci pro `lsl update --rollback`.

Programy spusťte znovu; samostatné binárky z `lsl compile` znovu přeložte,
protože zrychlení je součástí jejich runtime.
