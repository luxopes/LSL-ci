# Release LSL 0.8.3

Vydání 21. 9. 2026 pro Linux x86_64.

## Bezpečnost a diagnostika

Compiler nyní odmítá čtení lokální proměnné před přiřazením chybou E2002.
Oprava odstraňuje únik neinicializovaného obsahu zásobníku i SIGSEGV při
práci s referenčními typy. Analýza zahrnuje větve, smyčky, návraty,
`safe`/`try` a `del`; nepřidává běhové příznaky ani nulování lokálů.
E2002 je bezpečnostní chyba překladu, nikoli výjimka zachytitelná v `safe`.
Globály čtené z funkcí mají kontrolu inicializace se zachytitelným NameError;
smazání globálu z callbacku je zohledněno i v následném čtení v modulu.

Opravená reprezentace opakovaných `for` vazeb různých typů a nekolidující
interní jména odstraňují další zdroje záměny skalárů a ukazatelů.
Chybějící knihovna nyní hlásí E3001 s názvem, zdrojovou pozicí a návodem
k instalaci; nečitelný existující zdroj hlásí E3002. Import nic nestahuje.

## Jazyk

```lsl
Int(i) = 0
i++
--i
print clock()
start = monotonic()
status = system(["/usr/bin/true"])
print monotonic() - start
```

Typová deklarace `Int(x) = 10` není konverze: omezuje všechny další zápisy
ve stejném lexikálním rozsahu, včetně `+=` a vazeb `for`. Chybný typ vyvolá
TypeError a nezmění původní hodnotu. Známé správné typy nevyžadují běhovou
kontrolu. Podporované typy a omezení jsou v [jazykové specifikaci](language.md).
Prefixové i postfixové `++`/`--` fungují pouze jako samostatné příkazy nad
proměnnou; nejsou hodnotové výrazy a nepodporují indexované či členské cíle.

Vestavěné `system()` má stejné chování jako `os.run()`: String nebo seznam
argumentů, vyhledání přes PATH a návratový exit status. Nespouští shell.

## Čas a přechod z 0.8.2

**`clock()` mění návratový typ z Float na String** ve formátu
`YYYY-MM-DD HH:MM:SS UTC`. Pro měření trvání a timeoutů přejděte na nový
`monotonic()` nebo nezměněné `time.monotonic()` / `time.perf_counter()`.
CUDA timeouty jsou aktualizované v dodané knihovně.

Máte-li nainstalované X11, nejprve spusťte:

```text
lsl update x11
lsl update
```

X11 0.8.3 používá `time.monotonic()` a funguje i s LSL 0.8.2. Pokud jste
LSL již aktualizovali, `lsl update x11` lze provést i dodatečně. Aktualizace
LSL sama nepřepisuje uživatelské knihovny. Starší předkompilované programy
si zachovávají svůj zabudovaný runtime; změna se projeví při novém překladu.

## Grafika a ověření

X11 transport zachovává offset při částečném zápisu, čeká na možnost zápisu
při EAGAIN, používá timeout a neposílá SIGPIPE při zavřeném socketu.
Přerušený protokol skončí zachytitelnou chybou; deskriptor dál vlastní volající.
Příklad `examples/snake.lsl` používá směrové klávesy a Escape.
Grafické knihovny zůstávají volitelné (`lsl install display`, `lsl install gfx`).

Ověření zahrnuje bitově shodný self-host fixed point, kompletní regresní
sadu s GTX 1650, statický PIE audit, čistou instalaci, podepsaný updater
a rollback. Cílené regrese kontrolují neinicializované reference, typové
zápisy, časové hranice, X11 backpressure a chyby importů. Typovaný Int hot
loop má shodný ELF s netypovaným `+=` zápisem. Snake byl ověřen v Xvfb
včetně klávesnice a odesílacího bufferu zmenšeného na 4 KiB.
