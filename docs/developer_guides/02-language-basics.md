# 2. Základy jazyka

Tato kapitola vysvětluje základní stavební kameny jazyka LSL. Každý koncept
je popsán od začátku: co to je, k čemu to slouží, jak se to zapisuje a jak
to funguje. Pokud s programováním začínáte, čtěte tuto kapitolu postupně —
každá sekce staví na předchozích.

## Co je to proměnná

Proměnná je pojmenované místo v paměti, kam si program ukládá hodnotu,
aby ji mohl později použít. Představte si ji jako krabičku s nálepkou
(jméno proměnné), uvnitř které je nějaká věc (hodnota).

V LSL vytvoříte proměnnou jednoduše — napíšete její jméno, rovnítko a
hodnotu:

```lsl
vek = 30
jmeno = "Karel"
```

Tím se vytvoří proměnná `vek` s hodnotou `30` a proměnná `jmeno` s textem
`"Karel"`. Od této chvíle můžete jméno používat místo hodnoty:

```lsl
print vek                     # vypíše 30
print "Jmenuji se", jmeno     # vypíše Jmenuji se Karel
```

Proměnnou můžete kdykoliv změnit — nová hodnota přepíše starou:

```lsl
vek = 30
print vek      # 30
vek = 31
print vek      # 31
```

### Pravidla pro jména proměnných

Jméno proměnné může obsahovat písmena (malá i velká, včetně diakritiky),
čísla a podtržítko. Musí začínat písmenem nebo podtržítkem. Velikost
písmen se rozlišuje — `vek`, `Vek` a `VEK` jsou tři různé proměnné.

```lsl
spravne  = 1    # OK — jen písmena
jmeno2   = 2    # OK — písmena a číslice
_moje    = 3    # OK — začíná podtržítkem
pocetHodin = 4  # OK — camelCase
MAX_POCET = 5   # OK — UPPER_CASE s podtržítky

# Následující NEJSOU platná jména:
# 2jmeno  = 1    # CHYBA — začíná číslicí
# muj-vek = 2    # CHYBA — pomlčka není povolena
```

### Přiřazení a složené přiřazení

Základní přiřazení `x = hodnota` uloží hodnotu do proměnné. LSL má i
zkrácené zápisy pro časté operace:

```lsl
x = 10       # základní přiřazení

x += 5       # x = x + 5     (x bude 15)
x -= 3       # x = x - 3     (x bude 7)
x *= 2       # x = x * 2     (x bude 20)
x /= 4       # x = x / 4     (dělení, výsledek je Float)
x %= 3       # x = x % 3     (zbytek po dělení)

x &= 6       # x = x & 6     (bitový AND)
x |= 1       # x = x | 1     (bitový OR)
x ~= 3       # x = x ~ 3     (bitový XOR)
x <<= 2      # x = x << 2    (posun vlevo)
x >>= 1      # x = x >> 1    (posun vpravo)
```

### Mazání proměnné

Proměnnou lze zrušit pomocí `del`:

```lsl
x = 42
del(x)
# od této chvíle x neexistuje, print x by byla chyba
```

## Co je to typ hodnoty

Každá hodnota v LSL má svůj **typ** — druh informace, kterou představuje.
Typ určuje, co lze s hodnotou dělat. Například čísla lze sčítat, texty
spojovat, pravdivostní hodnoty negovat.

### Základní typy

| Co zapíšete | Typ | Co to je |
|---|---|---|
| `42`, `-7`, `0` | Int | Celé číslo |
| `3.14`, `-0.5`, `2.0` | Float | Desetinné číslo |
| `"ahoj"`, `"Karel"` | String | Text (řetězec znaků) |
| `True`, `False` | Bool | Pravda / nepravda |
| `None` | None | Prázdná hodnota, „nic" |

Typ hodnoty zjistíte pomocí funkce `type()`:

```lsl
print type(42)       # vypíše Int
print type(3.14)     # vypíše Float
print type("text")   # vypíše String
print type(True)     # vypíše Bool
print type(None)     # vypíše None
```

### Int — celé číslo

`Int` je celé číslo bez desetinné čárky. V LSL jde o 64bitové číslo,
takže rozsah je přibližně od −9 trilionů do +9 trilionů.

```lsl
pocet = 42
zaporne = -7
nula = 0
velke = 9223372036854775807   # maximální kladné
```

Co se stane, když překročíte maximální hodnotu? Hodnota se „přetočí":

```lsl
max = 9223372036854775807
print max + 1    # -9223372036854775808 (záporné minimum!)
```

Tomu se říká **wrap** — počítač nezahlásí chybu, jen pokračuje od
druhého konce rozsahu. Pro běžné počty to není problém; extrémní hodnoty
nastanou zřídka.

Pro čísla větší než Int64 použijte knihovní typ `BigInt`:

```lsl
load bigint

velke = bigint.BigInt("1000000000000000000000000000000")
print velke.power(2).text()
```

`BigInt` má libovolný počet číslic. Používá metody `add`, `subtract`,
`multiply`, `floor_divide`, `modulo` a `power`; běžný `Int` zůstává
rychlejší pro hodnoty, které se do 64 bitů vejdou.

### Float — desetinné číslo

`Float` ukládá desetinná čísla podle standardu IEEE-754 (stejný formát,
jaký používají všechny běžné procesory). Zapisuje se s desetinnou tečkou:

```lsl
pi = 3.14159
polovina = 0.5
teplota = -15.7
vedecky = 1.5e6     # 1.5 × 10⁶ = 1500000.0
odmocnina = sqrt(81) # 9.0
```

**Důležité**: LSL ukládá každou Float hodnotu jako samostatný objekt v
paměti (říká se tomu „boxing"). To znamená, že operace s Floaty jsou
pomalejší než s Int. Pro jednoduché výpočty to nevadí, ale pokud
potřebujete zpracovat milion čísel, použijte `FloatArray` a bulk kernely
(viz kapitola [11 — Výkon a optimalizace](11-performance-and-optimization.md)).

### Dělení: `/` versus `//`

LSL má dva druhy dělení:

```lsl
print 7 / 3          # 2.333333 (Float výsledek — desetinné číslo)
print 7 // 3         # 2 (Int výsledek — celočíselné dělení)
print 7 % 3          # 1 (zbytek po dělení)
```

- `/` vždy vrací Float.
- `//` vrací Int — kolikrát se dělitel vejde do dělence, zaokrouhleno
  **dolů** i pro záporná čísla.
- `%` vrací zbytek.

Záporná čísla — dělení zaokrouhluje dolů:

```lsl
print -7 // 3        # -3 (ne -2! — zaokrouhluje dolů k -3)
print -7 % 3         # 2 (zbytek je vždy nezáporný)
```

### String — textový řetězec

`String` je posloupnost znaků — text. V LSL se zapisuje do uvozovek. LSL
používá kódování UTF-8, takže můžete používat české znaky, emoji a znaky
z různých jazyků.

```lsl
pozdrav = "Ahoj"
jmeno = "Karel"
cela_veta = pozdrav + " " + jmeno + "!"   # "Ahoj Karel!"
```

**Spojování textů**: Operátor `+` spojuje texty dohromady:

```lsl
cast1 = "Dobrý "
cast2 = "den"
print cast1 + cast2    # Dobrý den
```

**Délka textu**: `len(text)` vrátí počet znaků:

```lsl
print len("Ahoj")      # 4
print len("Čeština")   # 7 (české znaky se počítají jako 1)
```

**Přístup ke znakům**: Pomocí hranatých závorek můžete získat jednotlivý
znak. První znak má index 0:

```lsl
text = "Ahoj"
print text[0]    # "A" — první znak
print text[1]    # "h" — druhý znak
print text[3]    # "j" — čtvrtý znak
```

**Záporné indexy** počítají od konce:

```lsl
text = "Ahoj"
print text[-1]   # "j" — poslední znak
print text[-2]   # "o" — předposlední znak
```

**Výřez (slice)**: Pomocí dvojtečky můžete získat část textu. Zápis
`text[od:do]` znamená „od indexu `od` (včetně) do indexu `do` (bez
tohoto indexu)":

```lsl
text = "Ahoj světe"
print text[0:4]    # "Ahoj" — znaky 0,1,2,3
print text[5:10]   # "světe" — znaky 5,6,7,8,9
print text[:4]     # "Ahoj" — od začátku do 4
print text[5:]     # "světe" — od 5 do konce
```

**Escape sekvence** — speciální znaky se zapisují pomocí zpětného lomítka:

```lsl
print "První řádek\nDruhý řádek"   # \n = nový řádek
print "Odsazení:\tAhoj"            # \t = tabulátor
print "Uvozovka: \"text\""         # \" = uvozovka uvnitř textu
print "Lomítko: \\"                # \\ = zpětné lomítko
```

### Bool — pravda a nepravda

`Bool` má jen dvě možné hodnoty: `True` (pravda) a `False` (nepravda).
Používá se pro rozhodování — když je něco pravda, udělej toto.

```lsl
je_zapnuto = True
je_plnolet = vek >= 18       # True, když věk >= 18
```

Co je považováno za „nepravdu" v podmínkách:

- `False`
- `None`
- `0` (nula)
- `0.0`
- `""` (prázdný text)
- Prázdný seznam/slovník

Všechno ostatní je „pravda".

### None — žádná hodnota

`None` znamená „žádná hodnota", „nic", „prázdno". Používá se, když
chcete vyjádřit, že hodnota zatím nebyla nastavena, nebo že funkce
nevrací žádný výsledek.

```lsl
vysledek = None     # zatím nevím
# ... později ...
vysledek = 42       # teď už vím
```

## Operátory — výpočty a porovnávání

Operátor je značka, která říká, co se má s hodnotami udělat. Například
`+` znamená sečti, `>` znamená porovnej.

### Aritmetické operátory — počítání

| Operátor | Co dělá | Příklad | Výsledek |
|---|---|---|---|
| `+` | Sčítání | `3 + 4` | `7` |
| `-` | Odčítání | `10 - 3` | `7` |
| `*` | Násobení | `3 * 4` | `12` |
| `/` | Dělení (Float) | `7 / 2` | `3.5` |
| `//` | Celočíselné dělení | `7 // 2` | `3` |
| `%` | Zbytek po dělení | `7 % 2` | `1` |
| `^` | Mocnina | `2 ^ 10` | `1024` |
| `-x` | Opačné číslo | `-5` | `-5` |

### Bitové operátory — práce s jednotlivými bity

Celé číslo je v paměti řada 64 bitů (nul a jedniček). Bitové operátory
pracují přímo s nimi. Hodí se na příznaky, masky, barvy a čtení binárních
formátů.

| Operátor | Co dělá | Příklad | Výsledek |
|---|---|---|---|
| `&` | AND — bit je 1, když je 1 v obou | `12 & 10` | `8` |
| `\|` | OR — bit je 1, když je 1 aspoň v jednom | `12 \| 10` | `14` |
| `~` | XOR — bit je 1, když se čísla liší | `12 ~ 10` | `6` |
| `~x` | NOT — obrátí všechny bity | `~12` | `-13` |
| `<<` | Posun vlevo (násobení dvěma) | `12 << 3` | `96` |
| `>>` | Posun vpravo (celočíselné dělení dvěma) | `12 >> 2` | `3` |

`~` je tedy dvakrát: mezi dvěma čísly je to XOR, před jedním číslem NOT.
Znak `^` se pro XOR použít nedá, protože v LSL už znamená mocninu.

Čísla se dají zapisovat i po bitech nebo šestnáctkově, což bývá čitelnější
než desítkově:

```lsl
print 0b1010     # dvojkově -> 10
print 0o755      # osmičkově -> 493
print 0xFF       # šestnáctkově -> 255
```

Typický příklad — sbalit čtyři bajty do jednoho čísla a zase je vytáhnout:

```lsl
packed = 0
for byte in [1, 2, 3, 4]:
    packed = (packed << 8) | byte
end
print packed                  # 16909060
print (packed >> 16) & 0xFF   # 2
```

A příznaky v jedné proměnné:

```lsl
CTENI = 1
ZAPIS = 2
SPUSTENI = 4

prava = CTENI | ZAPIS
print prava & ZAPIS != 0      # True  — zápis je povolený
print prava & SPUSTENI != 0   # False — spouštění není
```

Operandy musí být `Int` nebo `Bool` (`True` se počítá jako `1`), výsledek je
vždy `Int`. Posun o záporný počet bitů skončí chybou `ValueError`; posun
o 64 a více bitů je definovaný a vrací `0` (u `>>` pro záporné číslo `-1`).

### Porovnávací operátory — výsledkem je Bool (True/False)

| Operátor | Co znamená | Příklad | Výsledek |
|---|---|---|---|
| `==` | Rovná se | `5 == 5` | `True` |
| `!=` | Nerovná se | `5 != 3` | `True` |
| `<` | Menší než | `3 < 5` | `True` |
| `<=` | Menší nebo rovno | `5 <= 5` | `True` |
| `>` | Větší než | `7 > 4` | `True` |
| `>=` | Větší nebo rovno | `7 >= 7` | `True` |
| `in` | Je prvek v kolekci | `"a" in ["a","b"]` | `True` |
| `not in` | Není prvek v kolekci | `"x" not in ["a","b"]` | `True` |

**Důležité rozlišení**: `=` je přiřazení (ulož hodnotu), `==` je porovnání
(je to stejné?).

```lsl
x = 5         # přiřazení: do proměnné x ulož 5
if x == 5:    # porovnání: je x rovno 5?
    print "ano"
end
```

### Logické operátory — kombinování podmínek

| Operátor | Co znamená | Příklad |
|---|---|---|
| `and` | A zároveň (obě podmínky musí platit) | `x > 0 and x < 10` |
| `or` | Nebo (stačí, aby platila jedna) | `x < 0 or x > 100` |
| `not` | Negace (obrátí True na False a naopak) | `not ready` |

Logické operátory používají **zkratové vyhodnocení** (short-circuit):
jakmile je výsledek jasný z první části, druhá se už nevyhodnocuje.
Například `a and b` — když `a` je `False`, `b` se vůbec nevyhodnotí,
protože výsledek už musí být `False`.

### Priorita operátorů — co se vyhodnotí dřív

Když napíšete `2 + 3 * 4`, je to `2 + (3*4) = 14`, ne `(2+3) * 4 = 20`.
Násobení má vyšší prioritu než sčítání. Když si nejste jistí, použijte
závorky — ty mají vždy přednost a zpřehlední kód:

```lsl
vysledek = (a + b) * (c - d)   # závorky vyjasní, co se počítá s čím
```

Pořadí od nejvyšší priority k nejnižší: `^` → unární `-x`, `not x`, `~x` →
`* / // %` → `+ -` → `<< >>` → `&` → `~` (XOR) → `|` → porovnávací →
`and` → `or`.

Bitové operátory jsou tedy volnější než sčítání: `1 << 2 + 1` je `1 << 3`,
tedy `8`. Naopak vážou silněji než porovnání, takže `prava & ZAPIS != 0`
znamená `(prava & ZAPIS) != 0` — přesně jak to vypadá. (V jazycích jako C to
tak není a je to tam častý zdroj chyb; LSL to má jako Python.)

Mocnina je pravostranně asociativní: `2 ^ 3 ^ 2` znamená
`2 ^ (3 ^ 2)`, tedy `512`. Syntaxe `**` byla ve verzi 0.6 odstraněna.

## Jak funguje výpis: print a printl

### print — výpis hodnot

`print` vypíše hodnoty na obrazovku (přesněji na standardní výstup, ale
pro začátek si představte obrazovku). Můžete mu předat jeden nebo více
argumentů:

```lsl
print "Ahoj"                        # vypíše Ahoj a nový řádek
print "x je", x, "a y je", y       # argumenty se oddělí mezerou
```

Co `print` automaticky udělá:

1. Vypíše první argument.
2. Vypíše mezeru.
3. Vypíše druhý argument.
4. ... a tak dále pro všechny argumenty.
5. Na konci vždy přidá **nový řádek** (jako byste stiskli Enter).

### Lux String a printl — formátovaný text

Prefix `l` vytvoří normální String a nahradí v něm výrazy ve složených
závorkách `{...}`. Výsledek lze uložit, vrátit nebo předat dál:

```lsl
jmeno = "Karel"
vek = 30
text = l"Jmenuji se {jmeno} a je mi {vek} let."
print text
# Vypíše: Jmenuji se Karel a je mi 30 let.
```

Uvnitř `{...}` může být jakýkoli výraz:

```lsl
next = l"Za rok bude {vek + 1}"
detail = l"Délka jména: {len(jmeno)}"
literal = l"Doslovné závorky: {{jmeno}}"
```

Výraz v závorkách smí obsahovat i řetězce se stejnými uvozovkami, jaké
ohraničují celý Lux String — od 0.8.6 není potřeba je escapovat. Lexer
uvnitř `{...}` sleduje vnořené závorky i vnitřní řetězce:

```lsl
cara = l"{"-" * 20}"
slovnik = l"{ {"klic": 1}["klic"] }"
vnoreny = l"{l"uvnitř {vek}"}"
```

Starší zápis `l"{x + \"a\"}"` funguje dál. Neuzavřená interpolace je chyba
`E0001 unterminated String literal`.

Kompatibilní zkratka `printl "Ahoj {jmeno}"` interpoluje a rovnou vypíše
řádek. Pro nový kód, který potřebuje s textem dál pracovat, používejte
first-class tvar `l"..."`.

## Jak funguje vstup: input

`input` čte text z klávesnice. Může (ale nemusí) zobrazit výzvu — text,
který uživateli napoví, co má zadat.

```lsl
jmeno = input "Zadej jméno: "
print "Ahoj", jmeno
```

Jak to funguje krok za krokem:

1. Na obrazovku se vypíše text `Zadej jméno: ` (bez nového řádku —
   kurzor zůstane za dvojtečkou).
2. Program čeká, až uživatel něco napíše a stiskne Enter.
3. Vše, co uživatel napsal (bez koncového Enteru), se uloží jako text
   do proměnné `jmeno`.
4. Program pokračuje dalším řádkem.

`input` **vždy vrací text** (String), i když uživatel napíše číslo:

```lsl
vstup = input "Zadej číslo: "    # uživatel napíše 42
print vstup * 2                   # vypíše "4242"! (text se zopakuje)

cislo = Int(vstup)                # převede text "42" na číslo 42
print cislo * 2                   # vypíše 84 (správně)
```

Existují dvě rovnocenné syntaxe — `input "výzva"` i `input("výzva")`:

```lsl
jmeno = input "Jméno: "      # bez závorek
jmeno = input("Jméno: ")     # se závorkami — obojí funguje stejně
```

## Jak funguje větvení: if, elif, else

Program se často potřebuje rozhodnout: když platí podmínka A, proveď
tyto příkazy; jinak proveď jiné příkazy. K tomu slouží konstrukce
**if-elif-else**.

### if — když je podmínka splněna

```lsl
teplota = 25

if teplota > 30:
    print "Je vedro!"
end
```

Jak to funguje:

1. LSL vyhodnotí výraz za `if` — tady `teplota > 30`, což je `False`.
2. Pokud je podmínka `True`, provede se **tělo** — příkazy mezi
   dvojtečkou a `end`.
3. Pokud je podmínka `False`, tělo se přeskočí.
4. `end` ukončuje blok. V LSL musí každý blok (if, for, while, function,
   class, ...) končit slovem `end`.

### else — jinak

Co když chcete něco udělat, když podmínka **neplatí**? Přidáte `else`:

```lsl
teplota = 25

if teplota > 30:
    print "Je vedro!"
else:
    print "Není vedro"
end
```

- Když `teplota > 30` → vypíše `Je vedro!`
- Když ne → vypíše `Není vedro`

### elif — jinak když

Když máte víc možností, použijete `elif` (zkratka z „else if"):

```lsl
skore = 85

if skore >= 90:
    print "Výborně"
elif skore >= 80:
    print "Chvalitebně"
elif skore >= 70:
    print "Dobře"
else:
    print "Nedostatečně"
end
```

Jak LSL vyhodnocuje `if-elif-else`:

1. Zkontroluje první podmínku (`skore >= 90`). Když platí, provede její
   tělo a **zbytek přeskočí**.
2. Když neplatí, zkontroluje první `elif` (`skore >= 80`). Když platí,
   provede ho a zbytek přeskočí.
3. A tak dále pro všechny `elif`.
4. Pokud žádná podmínka neplatí, provede se `else` (pokud je uvedeno).
5. Z celé konstrukce se provede **nejvýše jedna větev**.

Dvojtečka za `if`, `elif` a `else` je **volitelná** — kód funguje i bez ní,
ale s ní je přehlednější.

### Vnořené podmínky

Podmínky lze vnořovat — uvnitř těla `if` může být další `if`:

```lsl
if prihlasen:
    if role == "admin":
        print "Vítej, administrátore"
    else:
        print "Vítej, uživateli"
    end
else:
    print "Nejste přihlášen"
end
```

## Jak fungují smyčky: opakování kódu

Smyčka umožňuje provést stejný kód vícekrát. LSL má tři typy smyček:
`for`, `while` a `loop`.

### for — pro každou hodnotu

Smyčka `for` prochází hodnoty jednu po druhé. Nejčastěji se používá
s funkcí `rang()`, která generuje posloupnost čísel:

```lsl
for i in rang(5):
    print i
end
# Vypíše: 0, 1, 2, 3, 4 (každé na novém řádku)
```

Jak to funguje:

1. `rang(5)` vytvoří posloupnost 0, 1, 2, 3, 4.
2. Do proměnné `i` se dosadí první hodnota (0).
3. Provede se tělo smyčky (`print i`).
4. Do `i` se dosadí další hodnota (1).
5. Tělo se provede znovu.
6. Takto se pokračuje pro všechny hodnoty.

Od 0.8.7 lze `rang(...)` použít i mimo smyčku jako hodnotu — vznikne
obyčejný List: `cisla = List(rang(2, 101))`, `print rang(4)` vypíše
`[0, 1, 2, 3]`. Ve smyčce `for` se žádný seznam nevytváří.
7. Po poslední hodnotě smyčka skončí a program pokračuje za `end`.

**`rang()` podrobně**:

```lsl
rang(5)            # 0, 1, 2, 3, 4 — od nuly do 5 (bez 5)
rang(2, 6)         # 2, 3, 4, 5 — od 2 do 6 (bez 6)
rang(0, 10, 2)     # 0, 2, 4, 6, 8 — od 0 do 10, krokem 2
rang(10, 0, -1)    # 10, 9, 8, ..., 1 — sestupně
```

Pravá mez (druhý argument) je vždy **exkluzivní** — hodnota meze se ve
výsledku neobjeví. To je záměrné: `rang(N)` dá přesně N hodnot.

Hodnoty, přes které se iteruje, se vyhodnotí **jednou na začátku**.
Když uvnitř smyčky změníte proměnnou použitou v mezi, smyčka se tím
neovlivní.

### for — procházení kolekcí

Smyčku `for` lze použít i pro procházení položek seznamu, slovníku
nebo textu:

```lsl
# Procházení seznamu
ovoce = ["jablko", "hruška", "švestka"]
for kus in ovoce:
    print kus
end

# Procházení klíčů slovníku
osoba = {"jmeno": "Karel", "vek": 30}
for klic in osoba.keys():
    print klic, "=", osoba[klic]
end

# Procházení znaků textu
for znak in "Ahoj":
    print znak
end
```

### while — dokud platí podmínka

Smyčka `while` opakuje tělo, dokud je podmínka pravdivá:

```lsl
odpocet = 5
while odpocet > 0:
    print odpocet
    odpocet -= 1
end
print "Start!"
```

Jak to funguje:

1. Před každým průchodem LSL vyhodnotí podmínku (`odpocet > 0`).
2. Pokud je `True`, provede tělo.
3. Pokud je `False`, smyčka končí.
4. Když je podmínka `False` už na začátku, tělo se neprovede **ani jednou**.

### loop — nekonečná smyčka

Smyčka `loop` běží donekonečna. Ukončí se jen přes `break` nebo
`exit(status)`:

```lsl
loop:
    prikaz = input "> "
    if prikaz == "konec":
        break
    end
    print "Zadal jsi:", prikaz
end
```

V tomto příkladu program čte příkazy od uživatele. Když uživatel napíše
`konec`, `break` ukončí smyčku a program skončí. Jinak vypíše zadaný
příkaz a pokračuje ve čtení.

### break a continue — řízení smyčky

- **`break`** — okamžitě ukončí nejvnitřnější smyčku. Program pokračuje
  prvním příkazem za `end`.
- **`continue`** — přeskočí zbytek aktuální iterace a hned začne další.

```lsl
for i in rang(10):
    if i == 3:
        continue     # přeskočí 3 — nevypíše se
    end
    if i == 7:
        break        # na 7 smyčka skončí
    end
    print i
end
# Výstup: 0, 1, 2, 4, 5, 6
```

`break` i `continue` smějí být **pouze uvnitř smyčky**. Mimo smyčku
způsobí chybu při překladu.

## Konverze mezi typy

Často potřebujete převést hodnotu z jednoho typu na druhý. Každý
základní typ lze použít jako funkci pro převod:

```lsl
Int("42")          # 42 — text na celé číslo
Int(3.14)          # 3 — Float na Int (usekne desetinnou část)
Float("3.14")      # 3.14 — text na desetinné číslo
Float(42)          # 42.0 — Int na Float
String(42)         # "42" — číslo na text
String(True)       # "True" — Bool na text
Bool(1)            # True — 1 se bere jako pravda
Bool(0)            # False — 0 se bere jako nepravda
Bool("ahoj")       # True — neprázdný text
Bool("")           # False — prázdný text
```

Převod může selhat — `Int("ahoj")` vyvolá chybu, protože text `"ahoj"`
není číslo. Pro bezpečný převod použijte `safe` blok (viz kapitola 5).

## Volání funkcí

Funkce je pojmenovaný blok kódu, který něco dělá a může vrátit výsledek.
Volání funkce znamená „proveď ten kód teď".

V LSL existují dva způsoby, jak funkci zavolat:

```lsl
vysledek = len("ahoj")     # normální volání — výsledek se použije
call print("ahoj")          # call — výsledek se zahodí
```

- **Normální volání** (`vysledek = funkce(...)`) — návratovou hodnotu lze
  použít ve výrazu, uložit do proměnné nebo předat jiné funkci.
- **`call funkce(...)`** — návratová hodnota se zahodí. Používá se pro
  funkce, jejichž výsledek nepotřebujete (např. `print`, který vrací
  `None`, nebo funkce provádějící akci).

## Syntaxe LSL — souhrn pravidel

Než postoupíme dál, shrňme si základní pravidla zápisu:

- **Jeden příkaz na řádek** — zpravidla platí, že každý řádek je jeden
  příkaz. LSL nepoužívá středníky.
- **Komentáře** — `#` začíná komentář, který platí do konce řádku.
  Compiler komentáře ignoruje, jsou jen pro lidi.
- **Bloky končí `end`** — každý blok otevřený `if`, `for`, `while`,
  `loop`, `function`, `class`, `safe` nebo `try` musí být ukončen
  samostatným řádkem se slovem `end`.
- **Odsazení** — nemá syntaktický význam. Compiler ho ignoruje.
  Doporučujeme odsazovat o 4 mezery pro přehlednost.
- **Velikost písmen** — záleží na ní. `promenna` a `Promenna` jsou
  různé proměnné.
- **UTF-8** — zdrojové soubory používají kódování UTF-8.

## Kompletní příklad

Na závěr kapitoly si ukažme program, který používá většinu probraných
konceptů — proměnné, podmínky, smyčky, vstup, výstup a převody typů:

```lsl
# Program: Hádání čísla
# Počítač si myslí číslo, uživatel ho hádá.

tajne_cislo = 73
pokus = 0

print "Myslím si číslo od 1 do 100. Hádej!"

loop:
    pokus += 1
    odpoved = Int(input "Tvůj tip: ")

    if odpoved < tajne_cislo:
        print "Větší!"
    elif odpoved > tajne_cislo:
        print "Menší!"
    else:
        printl "Správně! Uhodl jsi na {pokus}. pokus."
        break
    end
end
```

Vysvětlení:

- `tajne_cislo = 73` — pevně dané číslo (pro jednoduchost).
- `pokus = 0` — počítadlo pokusů.
- `loop:` — nekonečná smyčka. Ukončí se přes `break`, když uživatel
  uhodne.
- `pokus += 1` — zvýší počítadlo pokusů.
- `Int(input ...)` — přečte vstup a převede ho na číslo.
- `if-elif-else` — porovná tip s tajným číslem, vypíše nápovědu.
- `printl "Správně! ..."` — formátovaný výpis po uhodnutí.
- `break` — ukončí smyčku (a tím i program).

## Kam dál

- [03 — Funkce a třídy](03-functions-and-classes.md): jak psát vlastní
  funkce, používat callbacky, vytvářet třídy a organizovat kód do modulů.
- [04 — Kolekce a datové struktury](04-collections.md): seznamy, slovníky,
  pole — jak ukládat více hodnot najednou.
- [05 — Zpracování chyb](05-error-handling.md): jak reagovat na chyby a
  psát odolný kód.
