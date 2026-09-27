# 4. Kolekce a datové struktury

Když program potřebuje pracovat s více hodnotami najednou (třeba se
seznamem studentů, tabulkou výsledků nebo slovníkem nastavení), nestačí
samostatné proměnné. K tomu slouží **kolekce** — datové struktury, které
dokážou pojmout mnoho hodnot a umožňují s nimi pracovat jako s celkem.

Tato kapitola vysvětluje každý typ kolekce v LSL: co to je, kdy ho použít,
jak ho vytvořit, jak do něj ukládat a číst hodnoty.

## Přehled: jakou kolekci vybrat?

| Když potřebujete... | Použijte | Protože... |
|---|---|---|
| Seznam položek (lze přidávat a mazat) | `List` | Univerzální, měnitelný |
| Pevnou skupinu hodnot (nemění se) | `Tuple` | Lehčí, bezpečnější |
| Tabulku klíč→hodnota (např. jméno→věk) | `Dictionary` | Rychlé vyhledávání podle klíče |
| Unikátní neměnné hodnoty | `Set` | Odstraní duplicity a nabízí množinové metody |
| Velké pole čísel pro výpočty | `IntArray` / `FloatArray` | Efektivní, neboxované |
| Binární data (obrázky, soubory) | `ByteArray` | Jeden byte na prvek |

## List/dict comprehensions (0.7.8)

Comprehension vytváří kolekci přímo z výrazu, smyčky a volitelných filtrů:

```lsl
squares = [x*x for x in rang(10) if x % 2 == 0]
mapping = {key:value*2 for key,value in [("a", 2), ("b", 3)]}
pairs = [(x,y) for x in rang(3) for y in rang(x) if y > 0]
matrix = [[x*y for y in rang(3)] for x in rang(2)]
fixed = Tuple([x for x in rang(3)])
```

Klauzule se vykonávají zleva doprava jako vnořené smyčky; filtr ovlivní
následující klauzule. Vnější iterable se vyhodnotí právě jednou v okolním
scope. Proměnné comprehensions zůstávají lokální a nepřepíší stejně
pojmenované okolní proměnné. U Dictionary se klíč vyhodnotí před hodnotou,
pozdější duplicitní klíč nahradí předchozí hodnotu.

Podporováno je vnoření, více for/if klauzulí a ploché rozbalení dvojic
nebo jiných pevných počtů prvků, např. `for (a,b) in rows`. Nesprávná
délka rozbalovaného prvku vyvolá chybu. Maximum je 64 klauzulí.
Výsledky jsou eager List/Dictionary; nejde o kompresi dat gzip/zlib.
Set vytvořte pomocí `set(iterable)`; set comprehension ani lazy generátory
nejsou podporované. Tuple vytvořte převodem
`Tuple([...])`; syntaxe `(x for x in data)` není podporována.


## List — seznam

List je nejpoužívanější kolekce. Je to **uspořádaný seznam**, do kterého
můžete přidávat, odebírat a měnit položky. Každá položka má své číslo
(index), počínaje nulou. Položky mohou být různých typů.

### Vytvoření seznamu

```lsl
prazdny = []                     # prázdný seznam
cisla = [1, 2, 3, 4, 5]         # celočíselný seznam
smiseny = [1, "text", True]     # různé typy v jednom seznamu
vnořeny = [[1, 2], [3, 4]]      # seznam seznamů
```

### Čtení položek — indexace

Každá položka v seznamu má číselnou adresu — **index**. První položka
má index 0, druhá 1, atd. Pomocí indexu v hranatých závorkách položku
přečtete:

```lsl
ovoce = ["jablko", "hruška", "švestka", "třešeň"]
print ovoce[0]     # "jablko" — první
print ovoce[1]     # "hruška" — druhá
print ovoce[3]     # "třešeň" — čtvrtá
```

**Záporné indexy** počítají od konce:

```lsl
print ovoce[-1]    # "třešeň" — poslední
print ovoce[-2]    # "švestka" — předposlední
```

Můžete použít i `ovoce(0)` — kulaté závorky fungují stejně jako hranaté.

### Zápis — změna položky

Existující položku přepíšete přiřazením do indexu:

```lsl
ovoce[0] = "pomeranč"      # přepíše první položku
print ovoce                 # ["pomeranč", "hruška", "švestka", "třešeň"]
```

### Výřez (slice) — více položek najednou

Pomocí dvojtečky získáte **část seznamu**. `seznam[od:do]` vrací nový
seznam s položkami od indexu `od` (včetně) do `do` (bez):

```lsl
cisla = [10, 20, 30, 40, 50]
print cisla[0:3]      # [10, 20, 30] — první tři
print cisla[2:]       # [30, 40, 50] — od třetího do konce
print cisla[:2]       # [10, 20] — od začátku po druhý (bez)
print cisla[1:4]      # [20, 30, 40]
```

### Metody seznamu — co se seznamem můžete dělat

Seznam má mnoho vestavěných funkcí, tzv. **metod**:

#### Přidávání položek

```lsl
ukoly = []
ukoly.append("nakoupit")     # přidá na konec: ["nakoupit"]
ukoly.append("uklidit")      # přidá další: ["nakoupit", "uklidit"]
ukoly.insert(0, "nasnídat")  # vloží na pozici 0: ["nasnídat", "nakoupit", "uklidit"]
```

- `append(hodnota)` vloží prvek na konec.
- `insert(pozice, hodnota)` vloží na konkrétní místo. Ostatní prvky se
  posunou.

#### Spojování seznamů

```lsl
a = [1, 2]
b = [3, 4, 5]
a.extend(b)        # a = [1, 2, 3, 4, 5] — b se připojí za a
```

#### Odebírání položek

```lsl
ukoly = ["a", "b", "c", "d"]
posledni = ukoly.pop()      # vrátí "d" a odstraní ho; seznam je ["a","b","c"]
prvni = ukoly.pop(0)        # vrátí "a" a odstraní ho; seznam je ["b","c"]
ukoly.remove("c")           # odstraní první výskyt "c"; seznam je ["b"]
ukoly.clear()               # vyprázdní celý seznam
```

- `find(hodnota)` — vrátí pozici prvního výskytu, nebo `-1`, když prvek chybí
  (stejně jako `find` u Stringu; `index` místo toho vyvolá chybu).
- `pop()` — vrátí a odstraní poslední prvek.
- `pop(index)` — vrátí a odstraní prvek na dané pozici.
- `remove(hodnota)` — odstraní první výskyt dané hodnoty.
- `clear()` — smaže všechny položky.

#### Hledání

```lsl
cisla = [10, 20, 30, 20, 10]
print cisla.index(20)     # 1 — první výskyt hodnoty 20
print cisla.count(20)     # 2 — kolikrát je v seznamu 20
```

#### Řazení

```lsl
data = [3, 1, 4, 1, 5]
data.sort()          # seřadí na místě: [1, 1, 3, 4, 5]
data.reverse()       # obrátí na místě: [5, 4, 3, 1, 1]
kopie = data.copy()   # vytvoří mělkou kopii
```

Od 0.8.1 lze získat seřazenou kopii přímo:

```lsl
data = [3, 1, 3, 2]
print sorted(data)    # [1, 2, 3, 3]
print dedup(data)     # [3, 1, 2]
print data            # [3, 1, 3, 2] — původní seznam se nemění
```

`sorted(iterable)` vrací nový List, řadí stabilně vzestupně čísla nebo řetězce
(podle Unicode code points) a přijímá jeden argument, bez `key`/`reverse`.
Vstupem může být sekvence, Set nebo Dictionary (řadí klíče). `.sort()` nadále
mění seznam na místě a nevrací seřazený seznam.

`dedup(list)` vrací mělkou kopii bez duplicit. Zachová první výskyt podle
LSL rovnosti, včetně vnořených List/Dictionary; původní objekty nekopíruje.
Používá lineární hledání, tedy nejhůře kvadratický počet porovnání.

### Mazání

```lsl
seznam = ["a", "b", "c"]
del(seznam[1])       # smaže prvek: ["a", "c"]
del(seznam)          # smaže celou proměnnou
```

### Délka seznamu

```lsl
ovoce = ["a", "b", "c"]
print len(ovoce)     # 3
```

### Procházení seznamu

```lsl
for polozka in ovoce:
    print polozka
end

# S indexem:
for i in rang(len(ovoce)):
    printl "{i}: {ovoce[i]}"
end
```

## Set — množina (od 0.8.1)

```lsl
unikatni = set([3, 1, 3, 2])
unikatni.add(4)
unikatni.discard(1)
print sorted(unikatni)       # [2, 3, 4]
print 3 in unikatni          # True
print len(unikatni)          # 3
print sorted(unikatni.intersection([2, 9]))  # [2]
prazdna = set()
```

Set přijímá skaláry (`Int`, `Float`, `Bool`, `None`, `String`, `Function`)
a Tuple obsahující pouze takové neměnné hodnoty. Měnitelné kolekce odmítne
s `TypeError`; pro deduplikaci vnořených seznamů použijte `dedup`.
Rovnost Set nezávisí na pořadí prvků. Iterace deterministicky zachovává pořadí
vložených prvků. Podporovány jsou `for`, `in`, `len`, `Bool`, převod `List(s)`
a množinové metody popsané v [referenci](reference.md). Indexování ani literál
`{1, 2}` nejsou podporované. Vyhledávání je zatím lineární, ne hashované.

## Tuple — neměnitelná skupina

Tuple je jako seznam, ale **neměnitelný** — jakmile ho vytvoříte, nelze
měnit jeho položky, přidávat ani odebírat.

```lsl
bod = (10, 20)           # dvojice souřadnic
osoba = ("Karel", 30)    # jméno a věk
prazdny = ()             # prázdný tuple
```

**Jednoprvkový tuple** musí mít čárku:

```lsl
jeden_prvek = (42,)      # toto JE tuple
jen_cislo = (42)         # toto NENÍ tuple — je to Int 42!
```

Tuple se používá, když chcete vyjádřit, že skupina hodnot patří k sobě a
nebude se měnit — souřadnice, konstanty, návratové hodnoty.

```lsl
# Funkce vrací tuple:
function rozloz_jmeno(cele):
    pozice_mezery = 0
    for i in rang(len(cele)):
        if cele[i] == " ":
            pozice_mezery = i
            break
        end
    end
    return (cele[:pozice_mezery], cele[pozice_mezery + 1:])
end

jmeno, prijmeni = rozloz_jmeno("Karel Novák")   # Tuple unpacking
print jmeno      # "Karel"
print prijmeni   # "Novák"
```

Tuple má jen metody `index()` a `count()` — nemůže se měnit.

## Dictionary — slovník (klíč→hodnota)

Dictionary je kolekce, která místo číselných indexů používá **klíče**.
Je to stejné jako slovník v reálném světě — podíváte se pod heslo
(klíč) a najdete vysvětlení (hodnotu).

### Vytvoření a použití

```lsl
# Prázdný slovník
prazdny = {}

# Slovník s daty
osoba = {
    "jmeno": "Karel"
    "vek": 30
    "mesto": "Praha"
}
```

Víceřádkový slovník nepotřebuje čárky mezi řádky (ale můžete je použít).

```lsl
# Čtení podle klíče
print osoba["jmeno"]      # "Karel"
print osoba("vek")        # 30 — alternativní syntaxe

# Zápis a přidání
osoba["email"] = "karel@example.com"   # přidá nový klíč
osoba["vek"] = 31                      # změní existující
```

### Co může být klíčem

Klíčem může být cokoli neměnitelného: `String`, `Int`, `Bool`, `None`,
`Float`, `Function`. **Ne** seznam, slovník, třída nebo instance —
ty jsou měnitelné a jejich hash by se mohl změnit.

```lsl
mapa = {}
mapa["string"] = 1      # OK
mapa[42] = 2            # OK
mapa[True] = 3          # OK
# mapa[[1,2]] = 3       # CHYBA — seznam nelze jako klíč
```

### Metody slovníku

```lsl
d = {"a": 1, "b": 2, "c": 3}

# Bezpečné čtení (když klíč nemusí existovat)
print d.get("a")             # 1
print d.get("x", 0)          # 0 — výchozí hodnota, když klíč neexistuje
print d.get("x")             # None — implicitní výchozí hodnota

# Získání klíčů, hodnot, párů
print d.keys()               # ["a", "b", "c"]
print d.values()             # [1, 2, 3]
print d.items()              # [("a",1), ("b",2), ("c",3)]

# Kopírování
kopie = d.copy()

# Sloučení
d.update({"d": 4, "e": 5})   # přidá/aktualizuje klíče

# Odebrání
d.pop("c")                   # vrátí 3 a odstraní klíč
d.pop("x", "nenalezeno")     # vrátí "nenalezeno" — klíč neexistuje
d.clear()                    # vyprázdní slovník

# Nastavení výchozí hodnoty
d.setdefault("f", 6)         # vrátí 6 a nastaví, pokud klíč není
```

### Procházení slovníku

```lsl
for klic in d.keys():
    print klic, "=", d[klic]
end

# Nebo přes dvojice:
for klic, hodnota in d.items():
    print klic, "=", hodnota
end
```

### Kdy použít Dictionary vs List

- **List** — když záleží na pořadí, nebo chcete položky procházet popořadě.
- **Dictionary** — když potřebujete rychle najít hodnotu podle jména/klíče,
  nezáleží na pořadí.

## IntArray — výkonné pole čísel

`IntArray` je speciální pole, které ukládá celá čísla úsporně — každé
jako surové 64bitové číslo, bez zbytečné režie. Je určené pro situace,
kdy máte velké množství čísel a potřebujete výkon.

```lsl
arr = IntArray()        # prázdné pole
arr.append(10)          # přidá číslo
arr.append(20)
arr.append(30)

print arr[0]            # 10
print len(arr)          # 3

arr[1] = 25             # změní hodnotu
print arr[1]            # 25

# arr.append(3.14)      # CHYBA — jen Int!
# arr.append("text")    # CHYBA — jen Int!
```

Podporované operace: `append`, `clear`, indexace, změna prvků, `len`,
iterace (`for`), slicing. Omezené API oproti List — úmyslně, aby pole
zůstalo jednoduché a rychlé.

## FloatArray — výkonné pole desetinných čísel

Obdoba IntArray, ale pro desetinná čísla (Float64):

```lsl
samples = FloatArray()
samples.append(1.5)
samples.append(2.5)
samples.append(3.0)
```

Hlavní výhoda FloatArray oproti List[Float] spočívá v **nativních kernelech**
— operacích, které pracují přímo nad surovými daty a jsou extrémně rychlé:

```lsl
# Součet všech prvků (nativní kernel)
soucet = float_sum(samples)

# Skalární součin dvou vektorů
skalarni_soucin = float_dot(a, b)

# AXPY: y = alpha * x + y (přímá modifikace pole)
call float_axpy(2.0, x, y)

# Maticové násobení
vysledek = float_matmul(matice_a, matice_b, radky_a, sloupce_a, sloupce_b)

# Vytvoření pole nul
nuly = float_zeros(1000)       # 1000 nul, bez smyčky

# Vyplnění pole hodnotou
call float_fill(data, 3.14)    # všechny prvky na 3.14
```

Proč jsou kernely důležité: `float_sum` nad 1M prvků může být **400×
rychlejší** než LSL smyčka s boxovanými Floaty. Více v kapitole
[11 — Výkon a optimalizace](11-performance-and-optimization.md).

## ByteArray — pole bytů

ByteArray ukládá jednotlivé byty (čísla 0–255). Používá se pro binární
data — obrázky, síťové pakety, šifrování.

```lsl
buf = ByteArray()
buf.append(65)         # byte s hodnotou 65 (ASCII 'A')
buf.append(66)         # 66 (ASCII 'B')
buf.append(10)         # 10 (newline)

# buf.append(256)      # CHYBA — mimo rozsah 0–255
# buf.append(-1)       # CHYBA — záporné

print buf[0]           # 65 (vrací Int, ne znak!)
print len(buf)         # 3
```

Binární soubory se čtou a zapisují pomocí built-in funkcí `readbytes`
a `writebytes`:

```lsl
# Čtení celého souboru jako ByteArray
data = readbytes("obrazek.png")
print "Velikost:", len(data), "bytů"
print "První byte:", data[0]

# Zápis ByteArray do souboru
call writebytes("kopie.bin", data)
```

## RealArray — pole s pevnou délkou

RealArray má pevně daný počet prvků (délku), ale jednotlivé prvky lze
měnit:

```lsl
fixed = ![1, 2, 3, 4, 5]    # 5 prvků, víc nepřidáte
print fixed[0]               # 1
fixed[2] = 99                # změna existujícího prvku — OK
# fixed.append(6)            # CHYBA — délka je pevná
# fixed.pop()                # CHYBA — nelze odebírat
```

RealArray má metody `index()`, `count()` a `copy()`. `append`, `extend`,
`pop` a `del(fixed[i])` nefungují.

## Pravidla pro volbu kolekce

### Když máte homogenní číselná data (mnoho čísel)

Použijte **IntArray** nebo **FloatArray** s bulk kernely:

```lsl
# NASBÍRÁNÍ DAT
data = FloatArray()
for i in rang(100000):
    data.append(mereni[i])
end

# VÝPOČET — jeden kernel místo smyčky
prumer = float_sum(data) / Float(len(data))
```

### Když máte heterogenní data (různé typy)

Použijte **List**:

```lsl
zaznam = [123, "Karel", True, 3.14, ["a", "b"]]
```

### Když potřebujete vyhledávat podle jména

Použijte **Dictionary**:

```lsl
uzivatele = {
    "karel": {"vek": 30, "email": "karel@example.com"}
    "eva": {"vek": 25, "email": "eva@example.com"}
}
print uzivatele["eva"]["email"]
```

### Když se data nemění

Použijte **Tuple** — je bezpečnější (nemůže se omylem změnit):

```lsl
ROZMERY = (1920, 1080)
BARVY = ((255, 0, 0), (0, 255, 0), (0, 0, 255))
```

### Když pracujete s binárními soubory

Použijte **ByteArray**:

```lsl
raw = readbytes("data.bin")
if raw[0] == 0x89:
    print "Toto je PNG soubor"
end
```

## Shrnutí metod

### List

| Metoda | Co dělá |
|---|---|
| `append(x)` | Přidá na konec |
| `extend(list)` | Připojí jiný seznam |
| `insert(i, x)` | Vloží na pozici |
| `pop()` / `pop(i)` | Vrátí a odstraní |
| `remove(x)` | Odstraní první výskyt |
| `clear()` | Vyprázdní |
| `index(x)` | Index prvního výskytu |
| `count(x)` | Počet výskytů |
| `sort()` | Seřadí |
| `reverse()` | Obrátí |
| `copy()` | Mělká kopie |

### Dictionary

| Metoda | Co dělá |
|---|---|
| `get(k, default)` | Bezpečné čtení |
| `keys()` | Seznam klíčů |
| `values()` | Seznam hodnot |
| `items()` | Seznam dvojic |
| `update(d)` | Sloučení se slovníkem |
| `pop(k)` | Vrátí a smaže |
| `clear()` | Vyprázdní |
| `setdefault(k, v)` | Nastaví, pokud není |
| `copy()` | Mělká kopie |

### String (vybrané metody)

| Metoda | Co dělá |
|---|---|
| `lower()` | Malá písmena |
| `upper()` | Velká písmena |
| `strip()` | Odstraní bílé znaky |
| `split(d)` | Rozdělí podle oddělovače |
| `replace(s, n)` | Nahradí podřetězce |
| `join(seznam)` | Spojí seznam do textu |
| `startswith(s)` | Začíná na? |
| `endswith(s)` | Končí na? |
| `find(s)` | Pozice podřetězce |
| `count(s)` | Počet výskytů |
| `title()` | První písmena velká |
| `capitalize()` | První písmeno velké |

## Kam dál

- [05 — Zpracování chyb](05-error-handling.md): safe, try/else, Error
- [06 — Moduly a standardní knihovny](06-modules-and-imports.md): json,
  time, os, http a další
