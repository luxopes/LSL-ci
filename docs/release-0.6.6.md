# LSL 0.6.6

LSL 0.6.6 je výkonnostní patch zaměřený na `for` a `rang` smyčky. Syntaxe,
veřejné API i runtime ABI zůstávají kompatibilní s 0.6.5, takže dál platí
[manuál 0.6.5](https://git.lux-ai.cz/LuxAI/LSL-Web/src/branch/main/public/releases/0.6.5/README.md).

Compiler nově zahrnuje skryté přístupy k čítači, indexu a explicitnímu kroku
do analýzy registrových lokálů. Složené přiřazení, například `total += value`,
se počítá jako čtení i zápis. Běžné `rang(stop)` a `rang(start, stop)` navíc
používá přímou větev s krokem `+1` bez stackového step slotu a opakovaného
testování jeho znaménka.

Na miliardě iterací se zachovaným checksumem klesl medián aritmetické `rang`
smyčky z 2,13 s na 0,83 s a jednoduchého součtu čítače z 1,67 s na 0,58 s.
Medián user CPU self-host kompilace klesl z 2,09 s na 1,97 s. Výsledky jsou
měření na stejném stroji se střídáním staré a nové binárky.

Regresní corpus nyní pokrývá registrový `rang` čítač i iteraci `IntArray`.
Installer navíc přibaluje chybějící `thread_runtime.lsl`, takže compiler v
binárním archivu může z dodané zdrojové sady znovu sestavit sám sebe.
Staticky známý `Int` se při přechodu do tagged ABI nově boxuje přímo: jeho
číselné bity se už chybně nezkoušejí jako adresa živého boxovaného `Int`.
Deterministická regrese hlídá právě tuto dříve na rozložení paměti závislou
kolizi, která mohla poškodit mimo jiné textový výstup čísel.
Vydání prošlo bitovým self-host fixed pointem, úplnou testovací sadou,
instalací do čistého prefixu, config kontrolou a auditem všech generovaných
statických ELF.

Finální compiler fixed point má SHA-256
`326db5b802778fefc6fd6e81f1741544c542446811ca9f32d5d2cf28d02f434b`; CLI má
SHA-256 `821c00d035cfd9941e95eafcc898a392c1cf2a3aa5831e0485413653a2f594aa`.
