# 1. Začínáme s LSL

Tento průvodce vás krok za krokem provede od úplného začátku — instalací
LSL, napsáním prvního programu, jeho spuštěním a pochopením toho, co se
vlastně děje. Nepředpokládá žádné předchozí znalosti programování.

## Nejdřív: co to vlastně je programování

Počítač je stroj, který vykonává instrukce — jednotlivé kroky jako „sečti
dvě čísla", „vypiš text na obrazovku" nebo „přečti řádek z klávesnice".
Těmto instrukcím se říká **program** (nebo také kód, software, aplikace).

Programovací jazyk je způsob, jak tyto instrukce zapsat ve formě
srozumitelné člověku. LSL je jeden takový jazyk. Když napíšete soubor
s instrukcemi v LSL, spustíte **compiler**, který váš text přeloží do
strojového kódu — jedniček a nul, kterým procesor rozumí. Výsledkem je
spustitelný soubor (na Linuxu se mu říká ELF executable), který lze
spustit jako každý jiný program.

## Co je LSL

LSL (celým názvem Lux Simple Lang) je programovací jazyk, který:

- Má **jednoduchou syntaxi** podobnou Pythonu — kód se dobře čte a píše.
- **Překládá se do samostatného spustitelného souboru** — výsledný program
  nepotřebuje žádné knihovny, instalátory ani runtimy. Jeden soubor stačí.
- **Nepotřebuje nic externího** — compiler je napsaný v LSL samotném a ke
  svému běhu nepotřebuje C/C++, Python, linker ani jiné nástroje.
- **Běží na Linuxu** (x86\_64, 64bitový).

## Než začneme: práce s terminálem

LSL se ovládá z **terminálu** (také příkazová řádka, command line).
Terminál je okno, kam píšete příkazy a počítač je vykonává. Na Linuxu ho
najdete jako aplikaci „Terminal", „Konsole", „xterm" nebo podobně.

Když v tomto textu uvidíte:

```text
./lsl hello.lsl
```

znamená to: napište `./lsl hello.lsl` do terminálu a stiskněte Enter.
Znak `$` na začátku řádku značí výzvu terminálu (prompt) — ten nepíšete.

## Instalace LSL

### Co potřebujete

- Linux x86\_64 (64bitový). Většina moderních Linuxů (Ubuntu, Debian,
  Fedora, Arch) je x86\_64.
- `/usr/bin/curl` — program pro stahování z internetu. Na většině
  systémů už je nainstalovaný. Pokud ne: `sudo apt install curl`.

### Instalace do systému

Z adresáře se zdrojovými kódy LSL spusťte:

```text
sudo ./compiler/pure/lsl-install /usr/local
```

Tím se `lsl` nainstaluje do `/usr/local/bin/lsl`. `sudo` je potřeba,
protože zapisujete do systémového adresáře.

### Instalace do vlastního adresáře (bez sudo)

Když nemáte administrátorská práva, nainstalujte LSL do svého domovského
adresáře:

```text
./compiler/pure/lsl-install /home/vase_jmeno/lsl-prefix
/home/vase_jmeno/lsl-prefix/bin/lsl program.lsl
```

### Ověření, že to funguje

```text
lsl version
```

Mělo by vypsat číslo verze, tedy `0.6`.

## První program

Vytvořte soubor `hello.lsl`. Soubor můžete vytvořit v libovolném textovém
editoru (např. `gedit`, `kate`, `nano`, `vim`). Napište do něj:

```lsl
print "Ahoj světe!"
```

Co tento program dělá? Jediný řádek říká: vypiš text `Ahoj světe!` na
obrazovku. `print` je **instrukce** (říká se jí také funkce), která
vypisuje. Text v uvozovkách je **řetězec** (string) — posloupnost znaků,
která se má vypsat.

### Spuštění programu

```text
./lsl hello.lsl
```

V terminálu se objeví:

```text
Ahoj světe!
```

### Co se při spuštění stalo

1. `./lsl` spustilo LSL compiler.
2. Compiler přečetl soubor `hello.lsl` a přeložil ho do strojového kódu.
3. Tento strojový kód okamžitě spustil.
4. Program vypsal text a skončil.

### Vytvoření samostatného spustitelného souboru

Když chcete program spouštět opakovaně bez překládání:

```text
./lsl compile hello.lsl hello
```

Tím se vytvoří soubor `hello`, který je plnohodnotným linuxovým programem.
Spustíte ho prostě:

```text
./hello
```

Výsledek je stejný, ale soubor `hello` už není závislý na LSL — můžete ho
zkopírovat na jiný počítač s Linuxem a bude tam fungovat.

## Interaktivní režim: zkoušení za běhu

LSL umí pracovat i interaktivně — píšete příkaz, LSL ho hned vykoná,
vypíše výsledek, a čeká na další. To je ideální pro učení a experimentování.

Spusťte LSL bez argumentů:

```text
./lsl
```

Objeví se:

```text
Lux Simple Lang 0.6.9 interactive source mode
Enter code; type exit on its own line to compile and run.
>>>
```

Tři zobáčky `>>>` jsou **výzva** (prompt) — LSL čeká, až něco napíšete.
Funguje to takto:

- Každý řádek, který napíšete, se uloží (ale ještě neprovede).
- Až napíšete řádek se slovem `exit`, LSL vše najednou přeloží a spustí.
- Výsledek se vypíše a program skončí.

Příklad:

```text
>>> jmeno = "Karel"
>>> print "Ahoj", jmeno
>>> exit
Ahoj Karel
```

V interaktivním režimu platí důležité pravidlo: všechny řádky tvoří jeden
společný program. Když na prvním řádku vytvoříte proměnnou `jmeno`, na
druhém řádku ji můžete použít — LSL si ji pamatuje.

### Pipe a heredoc: neinteraktivní vstup

Když LSL dostane vstup z roury (pipe), chová se podobně — přečte vše až
do konce a pak to najednou spustí. Nepotřebujete psát `exit`:

```text
printf 'print 6 * 7\n' | ./lsl
```

Vypíše `42`. Podobně heredoc:

```text
./lsl <<'KONEC'
print "Výsledek:", 100 + 200
KONEC
```

`KONEC` je libovolný ukončovací text — může to být cokoli, třeba `EOF`
nebo `KONEC`. Není to součást LSL, ale instrukce pro shell (terminál).

## Druhý program: vstup od uživatele

Programy často potřebují, aby jim uživatel něco zadal. K tomu slouží
**input** (vstup).

```lsl
jmeno = input "Zadej své jméno: "
print "Ahoj", jmeno
```

Pojďme si tento kód vysvětlit řádek po řádku:

1. **`jmeno = input "Zadej své jméno: "`**
   - `input` je funkce, která čte text z klávesnice.
   - Text v uvozovkách `"Zadej své jméno: "` je **výzva** (prompt) —
     vypíše se uživateli, aby věděl, co má zadat.
   - Cokoli uživatel napíše, se uloží do **proměnné** `jmeno`.
   - Proměnná je pojmenované místo v paměti, kam si program ukládá
     hodnoty. Tady ukládáme text, který zadal uživatel.

2. **`print "Ahoj", jmeno`**
   - `print` vypíše své argumenty na obrazovku.
   - Argumenty se oddělují čárkou. První argument je text `"Ahoj"`, druhý
     je proměnná `jmeno` (tam je uložený text od uživatele).
   - `print` automaticky vloží mezeru mezi argumenty a na konci přidá
     nový řádek.

Když program spustíte a napíšete `Karel`, výstup bude:

```text
Zadej své jméno: Karel
Ahoj Karel
```

### Důležité: `input` vrací text, ne číslo

Když uživatel napíše `42`, `input` to vrátí jako text `"42"`, ne jako
číslo `42`. Pokud chcete s hodnotou počítat, musíte ji převést:

```lsl
text = input "Zadej číslo: "
cislo = Int(text)         # převede text "42" na číslo 42
print "Dvojnásobek je", cislo * 2
```

- `Int(...)` je funkce, která převádí text na celé číslo.
- Když uživatel zadá `42`, výstup bude `Dvojnásobek je 84`.

Kdybychom `Int()` nepoužili, `"42" * 2` by text zopakovalo dvakrát:
`"4242"`. Protože `*` pro text znamená opakování, ne násobení.

## Třetí program: rozhodování

Programy se často potřebují rozhodovat — když je něco pravda, udělej A,
jinak udělej B. K tomu slouží konstrukce **if-else** (česky „když–jinak").

```lsl
cislo = Int(input "Zadej číslo: ")

if cislo > 0:
    print "Číslo je kladné"
elif cislo == 0:
    print "Číslo je nula"
else:
    print "Číslo je záporné"
end
```

Pojďme si to rozebrat:

- **`if cislo > 0:`** — Když je `cislo` větší než nula.
  - `>` je operátor porovnání (větší než).
  - Pokud je podmínka pravdivá, provede se to, co je za dvojtečkou.
- **`print "Číslo je kladné"`** — Vypíše se, jen když `cislo > 0`.
- **`elif cislo == 0:`** — Jinak, když je `cislo` přesně nula.
  - `elif` je zkratka „else if" — „jinak když". Zkouší se jen když
    předchozí podmínka nebyla pravdivá.
  - `==` je operátor rovnosti (dvě rovnítka!). Jedno `=` je přiřazení.
- **`else:`** — Jinak (když nic z výše uvedeného neplatí).
- **`end`** — Ukončuje celý blok `if-elif-else`. V LSL musí být každý blok
  ukončený slovem `end`.

Program vyhodnotí podmínky seshora dolů a provede **nejvýše jednu** větev
— tu první, která je pravdivá.

## Čtvrtý program: opakování (smyčka)

Když chcete něco udělat vícekrát, použijete **smyčku** (loop). Ta opakuje
blok kódu, dokud platí nějaká podmínka, nebo pro každou hodnotu z rozsahu.

```lsl
for i in rang(1, 6):
    print "Opakování číslo", i
end
```

Výstup:

```text
Opakování číslo 1
Opakování číslo 2
Opakování číslo 3
Opakování číslo 4
Opakování číslo 5
```

Jak to funguje:

- **`for i in rang(1, 6):`** — Pro každé číslo od 1 do 5 (6 je horní mez,
  která se už neprovede) udělej následující blok.
- `i` je proměnná, do které se postupně dosazuje 1, 2, 3, 4, 5.
- V každém průchodu (iteraci) se provede `print "Opakování číslo", i`.
- Když `i` dosáhne 6, smyčka skončí.

`rang(start, stop)` vrací čísla od `start` (včetně) do `stop` (bez
`stop`). `rang(5)` je zkratka pro `rang(0, 5)` — hodnoty 0, 1, 2, 3, 4.
Můžete přidat i třetí argument — krok: `rang(0, 10, 2)` dává 0, 2, 4, 6, 8.

### Smyčka while

Druhý typ smyčky opakuje blok, dokud platí podmínka:

```lsl
pocitadlo = 5
while pocitadlo > 0:
    print pocitadlo
    pocitadlo -= 1         # zmenší pocitadlo o 1
end
print "Start!"
```

Výstup:

```text
5
4
3
2
1
Start!
```

- Než začne každá iterace, LSL zkontroluje, jestli `pocitadlo > 0`.
- Pokud ano, provede tělo smyčky. Pokud ne, smyčka skončí.
- `pocitadlo -= 1` je zkratka pro `pocitadlo = pocitadlo - 1`.

## Pátý program: práce s argumenty

Když spouštíte program, můžete mu předat argumenty — další slova za jeho
jménem:

```text
./lsl program.lsl prvni_argument druhy_argument
```

Uvnitř programu k nim přistoupíte pomocí:

- `arg_count()` — vrátí počet argumentů
- `arg(0)` — jméno programu
- `arg(1)` — první argument
- `arg(2)` — druhý argument
- `args` — seznam všech argumentů

```lsl
print "Program:", arg(0)
print "Počet argumentů:", arg_count()
if arg_count() >= 2:
    print "První argument:", arg(1)
    print "Druhý argument:", arg(2)
end
```

## Správa chybových stavů

Když se programu něco nepovede (např. čtení neexistujícího souboru), LSL
vyvolá **chybu** (error, výjimku). Chyba přeruší normální běh programu.
LSL nabízí dva způsoby, jak chyby zachytit a zareagovat na ně:

### safe — bezpečný blok

Vše uvnitř bloku `safe` se provede. Pokud někde uvnitř dojde k chybě,
zbytek bloku se přeskočí, ale program **pokračuje** dál za blokem:

```lsl
safe:
    text = readfile("neexistujici.txt")   # tady vznikne chyba
    print "Toto se nikdy nevypíše"
end
print "Program pokračuje dál"
```

### try/else — fallback při chybě

Blok `try` se pokusí provést. Pokud selže, provede se blok `else` jako
záložní plán:

```lsl
try:
    text = readfile("config.json")
else:
    print "Konfigurace nebyla nalezena, použiji výchozí"
    text = "{}"
end
```

### last_error()

Po zachycení chyby lze zjistit, co se stalo:

```lsl
safe:
    value = Int("toto není číslo")
end
if last_error() != None:
    print "Nastala chyba:", last_error()
end
```

Více o chybách najdete v kapitole [05 — Zpracování chyb](05-error-handling.md).

## Užitečné vestavěné funkce

LSL obsahuje řadu funkcí dostupných okamžitě, bez importování:

| Funkce | Co dělá | Příklad |
|---|---|---|
| `print(...)` | Vypíše argumenty na obrazovku | `print "Ahoj", jmeno` |
| `printl(text)` | Vypíše formátovaný text | `printl "Hodnota: {x}"` |
| `input(prompt)` | Přečte řádek od uživatele | `jmeno = input "Jméno: "` |
| `Int(x)` | Převede na celé číslo | `Int("42")` → `42` |
| `Float(x)` | Převede na desetinné číslo | `Float("3.14")` |
| `String(x)` | Převede na text | `String(42)` → `"42"` |
| `Bool(x)` | Převede na pravdivostní hodnotu | `Bool(1)` → `True` |
| `len(x)` | Délka textu/kolekce | `len("abc")` → `3` |
| `type(x)` | Zjistí typ hodnoty | `type(42)` → `Int` |
| `min(a,b,...)` | Nejmenší hodnota | `min(3, 7, 1)` → `1` |
| `max(a,b,...)` | Největší hodnota | `max(3, 7, 1)` → `7` |
| `abs(x)` | Absolutní hodnota | `abs(-42)` → `42` |
| `chr(n)` | Číslo na znak | `chr(65)` → `"A"` |
| `ord(ch)` | Znak na číslo | `ord("A")` → `65` |
| `readfile(cesta)` | Přečte textový soubor | `readfile("data.txt")` |
| `writefile(cesta, text)` | Zapíše textový soubor | `writefile("out.txt", "ahoj")` |
| `exists(cesta)` | Existuje soubor? | `exists("/etc/passwd")` |
| `clock()` | Monotónní čas (sekundy) | `clock()` |
| `arg(n)` | Argument programu | `arg(1)` |
| `arg_count()` | Počet argumentů | `arg_count()` |
| `exit(kod)` | Ukončí program | `exit(0)` |

## Struktura většího projektu

Když program přesáhne ~100 řádků, je rozumné ho rozdělit do více souborů.
Každý soubor se stará o jednu oblast (uživatelské rozhraní, výpočty,
databáze). LSL používá **moduly**:

```text
moje-aplikace/
  main.lsl         ← hlavní soubor, spouští se
  vypocty.lsl      ← matematické funkce
  formatovani.lsl  ← formátování textu
```

V `main.lsl` načtete ostatní soubory:

```lsl
load vypocty
load formatovani

vysledek = vypocty.spocitej(10, 20)
print formatovani.hezky(vysledek)
```

- `load vypocty` načte soubor `vypocty.lsl` a zpřístupní jeho funkce
  pod prefixem `vypocty.`
- Když chcete importovat jen jednu funkci: `from vypocty load spocitej`

Více o modulech a organizaci kódu najdete v [03 — Funkce, třídy a moduly](03-functions-and-classes.md).

## Kam dál

Teď když rozumíte základům — co je proměnná, jak program čte vstup a
vypisuje výstup, jak se větví a opakuje — pokračujte další kapitolou:

- [02 — Základy jazyka](02-language-basics.md): podrobný výklad všech
  typů, operátorů, podmínek a smyček s vysvětlením, co která věc dělá.
