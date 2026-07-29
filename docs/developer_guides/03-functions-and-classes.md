# 3. Funkce a třídy

Tato kapitola vysvětluje, jak strukturovat kód do znovupoužitelných celků:
funkce (bloky kódu, které něco dělají), třídy (šablony pro seskupení dat
a chování) a moduly (rozdělení kódu do samostatných souborů).

## Proč funkce?

Představte si, že na pěti místech programu potřebujete spočítat druhou
mocninu čísla. Můžete napsat `x * x` pokaždé znovu. Nebo můžete napsat
**funkci** — pojmenovaný blok kódu, který výpočet udělá, a pak už jen
voláte její jméno:

```lsl
function druha_mocnina(cislo):
    return cislo * cislo
end

print druha_mocnina(5)     # 25
print druha_mocnina(12)    # 144
```

Funkce přináší tři výhody:

1. **Znovupoužitelnost** — napišete jednou, použijete mnohokrát.
2. **Čitelnost** — jméno funkce říká, co kód dělá.
3. **Změny na jednom místě** — když je potřeba změnit výpočet, změníte
   jen funkci, ne pět různých míst.

## Jak napsat funkci

Funkce se definuje klíčovým slovem `function`, následuje jméno a závorky
se seznamem **parametrů** (vstupních hodnot). Za závorkou může být
dvojtečka (volitelná). Tělo funkce končí řádkem `end`.

```lsl
function secti(a, b):
    return a + b
end
```

Co znamenají jednotlivé části:

- **`function`** — říká „teď definuji novou funkci".
- **`secti`** — jméno funkce. Když ji chci zavolat, použiji toto jméno.
- **`(a, b)`** — **parametry** (vstupní hodnoty). Když funkci zavolám,
  musím jí předat dvě hodnoty — ty se uvnitř funkce jmenují `a` a `b`.
- **`return a + b`** — **návratová hodnota**. Funkce vrátí výsledek
  volajícímu. Zde vrací součet `a + b`.
- **`end`** — konec funkce.

### Parametry — vstupní hodnoty

Parametry jsou povinné a předávají se v pořadí, v jakém byly zapsány.
První hodnota v závorkách při volání jde do prvního parametru, druhá do
druhého atd.:

```lsl
function pozdrav(jmeno, vek):
    printl "Ahoj {jmeno}, je ti {vek} let."
end

call pozdrav("Karel", 30)   # Ahoj Karel, je ti 30 let.
call pozdrav("Eva", 25)     # Ahoj Eva, je ti 25 let.
```

- Při volání `pozdrav("Karel", 30)` se do `jmeno` dosadí `"Karel"` a
  do `vek` se dosadí `30`.

### Návratová hodnota — co funkce vrací

`return` ukončí funkci a vrátí hodnotu. Funkce bez `return` vrací `None`:

```lsl
function nic_nedelej():
    # žádný return — vrátí None
end

vysledek = nic_nedelej()
print vysledek          # None
print type(vysledek)    # None
```

`return` lze použít i bez hodnoty — pak vrátí `None`:

```lsl
function brzy_skonci(x):
    if x < 0:
        return      # vrátí None, zbytek funkce se neprovede
    end
    return x * 2
end
```

### call — když návratovou hodnotu nepotřebujete

Některé funkce provádějí akci a jejich návratová hodnota vás nezajímá
(např. `print`, které vrací `None`). Pak použijete `call`:

```lsl
call print("Ahoj")        # provede funkci, zahodí návratovou hodnotu
call pozdrav("Karel", 30) # totéž

vysledek = secti(3, 4)    # normální volání — výsledek si uložíme
```

`call` čistě říká „tahle funkce se volá pro svůj vedlejší efekt".

## Proměnné uvnitř funkce

### Lokální proměnné

Proměnné, které vytvoříte uvnitř funkce (přiřazením), jsou **lokální** —
existují jen uvnitř té funkce, venku nejsou vidět:

```lsl
function moje_funkce():
    lokalni = 42
    print lokalni      # 42 — tady existuje
end

call moje_funkce()
# print lokalni        # CHYBA — "lokalni" tady neexistuje
```

### Čtení globálních proměnných

Funkce může **číst** proměnné definované mimo ni (tzv. globální):

```lsl
nasobic = 10           # globální proměnná

function vynasob(x):
    return x * nasobic # čte globální nasobic
end

print vynasob(5)       # 50
```

### Zápis vytváří lokální proměnnou

Když uvnitř funkce přiřadíte do proměnné, která má stejné jméno jako
globální, **vytvoříte novou lokální proměnnou** — globální zůstane
nezměněná:

```lsl
hodnota = 100          # globální

function zmen():
    hodnota = 200      # toto vytvoří NOVOU LOKÁLNÍ "hodnota"!
end

call zmen()
print hodnota          # 100 — globální se nezměnila!
```

Toto je důležité pravidlo: **zápis uvnitř funkce je vždy lokální**,
pokud nepoužijete třídu nebo Dictionary (viz dále).

## Funkce jako hodnota (first-class funkce)

V LSL je funkce **hodnota** jako každá jiná. Můžete ji uložit do
proměnné, předat jako argument jiné funkci, nebo ji vrátit z funkce.
Typ takové hodnoty je `Function`.

### Uložení funkce do proměnné

```lsl
function zdvojnasob(x):
    return x * 2
end

f = zdvojnasob        # f je teď funkce (bez závorek!)
print f(10)           # 20 — voláme přes proměnnou
print type(f)         # Function
```

Rozdíl mezi `zdvojnasob` (samotná funkce) a `zdvojnasob(10)` (výsledek
volání) je zásadní:

- **Bez závorek** = reference na funkci, nevolá se.
- **Se závorkami** = funkce se zavolá a vrátí výsledek.

### Předání funkce jako argumentu (callback)

Funkci můžete předat jiné funkci — ta ji pak zavolá. Tomu se říká
**callback** (zpětné volání):

```lsl
function je_sude(cislo):
    return cislo % 2 == 0
end

function vyfiltruj(seznam, test):
    vysledek = []
    for prvek in seznam:
        if test(prvek):         # zavolá předanou funkci!
            vysledek.append(prvek)
        end
    end
    return vysledek
end

cisla = [1, 2, 3, 4, 5, 6]
suda = vyfiltruj(cisla, je_sude)
print suda   # [2, 4, 6]
```

`vyfiltruj` je obecná funkce — neví, podle jakého pravidla filtrovat.
To jí řekneme předáním funkce `je_sude`. Stejně bychom mohli předat
jiný test (např. `je_kladne`, `je_delitelne_tremi`).

## Proč třídy?

Když program pracuje s několika souvisejícími hodnotami (např. jméno,
věk a email uživatele), můžete je uložit do slovníku. Ale co když k
nim chcete přidat i chování — např. metodu `vypis_profil()`, která
hodnoty hezky zformátuje?

**Třída** (class) je šablona, která spojuje **data** (proměnné) a
**chování** (funkce/metody) do jednoho celku. Z třídy se pak vytváří
**instance** — konkrétní objekty s vlastními daty.

## Jak napsat třídu

```lsl
class Osoba(True):
    ctype Public

    function init(self, jmeno, vek):
        self.jmeno = jmeno
        self.vek = vek
    end

    function pozdrav(self):
        return "Ahoj, jmenuji se " + self.jmeno + " a je mi " + String(self.vek) + " let."
    end
end
```

Části definice třídy:

- **`class Osoba(True):`** — definuje třídu jménem `Osoba`. `(True)`
  znamená, že třída je aktivní. `(False)` by ji vypnulo.
- **`ctype Public`** — třída je viditelná i mimo svůj modul. `Private`
  by ji skryla.
- **`function init(self, jmeno, vek):`** — speciální metoda, která se
  zavolá při vytváření instance. Slouží k nastavení počátečních hodnot.
- **`self`** — odkaz na konkrétní instanci. `self.jmeno` znamená
  „proměnná `jmeno` patřící této konkrétní instanci".
- **`function pozdrav(self):`** — normální metoda. První parametr je
  vždy `self`.

### Vytvoření a použití instance

```lsl
karel = Osoba("Karel", 30)    # vytvoří instanci — zavolá init
eva = Osoba("Eva", 25)        # další instance

print karel.jmeno              # "Karel"
print karel.pozdrav()          # "Ahoj, jmenuji se Karel a je mi 30 let."
print eva.pozdrav()            # "Ahoj, jmenuji se Eva a je mi 25 let."
```

Jak to funguje:

1. `Osoba("Karel", 30)` vytvoří novou instanci třídy `Osoba`.
2. Automaticky se zavolá metoda `init` — `self` je nová instance,
   `jmeno` je `"Karel"`, `vek` je `30`.
3. Uvnitř `init` se nastaví `self.jmeno = "Karel"` a `self.vek = 30`.
4. Instance se uloží do proměnné `karel`.
5. `karel.jmeno` přistupuje k datům instance.
6. `karel.pozdrav()` volá metodu. LSL automaticky dosadí instanci
   jako `self` — nemusíte ho psát.

### Statické atributy třídy

Třída sama o sobě může mít proměnné — sdílí je všechny instance:

```lsl
class Pocitadlo(True):
    ctype Public
    celkem = 0                    # atribut třídy

    function init(self):
        Pocitadlo.celkem += 1     # zvýší při každé nové instanci
        self.cislo = Pocitadlo.celkem
    end
end

a = Pocitadlo()
b = Pocitadlo()
c = Pocitadlo()

print a.cislo    # 1
print b.cislo    # 2
print c.cislo    # 3
print Pocitadlo.celkem   # 3 — kolik instancí jsme vytvořili
```

### Třída jako Dictionary, Dictionary jako třída

Technicky je třída i její instance v LSL Dictionary. Pro jednoduchá data,
která nemají chování, je Dictionary často jednodušší:

```lsl
# Pomocí slovníku (jednodušší, když nemáte metody):
uzivatel = {"jmeno": "Karel", "vek": 30}
print uzivatel["jmeno"]

# Pomocí třídy (vhodné, když máte metody a chování):
class Uzivatel(True):
    ctype Public
    function init(self, jmeno, vek):
        self.jmeno = jmeno
        self.vek = vek
    end
    function plnolety(self):
        return self.vek >= 18
    end
end
u = Uzivatel("Karel", 30)
print u.jmeno
print u.plnolety()
```

**Doporučení**: Když máte jen data, použijte Dictionary. Když k datům
potřebujete metody (výpočty, formátování, validaci), použijte třídu.

## Moduly: rozdělení kódu do souborů

Motivace: když má váš program 500 řádků, je těžké se v něm vyznat.
Rozdělíte ho proto do více souborů, z nichž každý řeší jednu oblast.

### Jak moduly fungují

Každý soubor `.lsl` je automaticky **modul**. Co v něm definujete
(proměnné, funkce, třídy), je jeho **rozhraní** (export).

### Import celého modulu

```lsl
# soubor: moje_aplikace.lsl
load matematika         # načte matematika.lsl

print matematika.secti(3, 7)
print matematika.PI
```

```lsl
# soubor: matematika.lsl
PI = 3.14159

function secti(a, b):
    return a + b
end
```

- `load matematika` hledá soubor `matematika.lsl` ve stejném adresáři
  jako soubor, který ho importuje.
- Vše z `matematika.lsl` je dostupné pod prefixem `matematika.`.

### Selektivní import (from)

Když z modulu potřebujete jen jednu funkci:

```lsl
from matematika load secti
print secti(3, 7)              # už bez prefixu!

# Přejmenování:
from matematika load secti as scitani
print scitani(3, 7)

# Více funkcí:
from matematika load secti, PI
print secti(1, 2), PI
```

### Tečková notace pro podadresáře

Můžete organizovat moduly do podadresářů:

```text
moje-aplikace/
  main.lsl
  nastroje/
    text.lsl
    cisla.lsl
```

```lsl
# main.lsl
load nastroje.text      # načte nastroje/text.lsl
load nastroje.cisla     # načte nastroje/cisla.lsl

print nastroje.text.velke("ahoj")
print nastroje.cisla.prumer([1, 2, 3, 4])
```

### Standardní moduly

LSL obsahuje řadu vestavěných modulů pro běžné úlohy:

```lsl
load json         # JSON enkódování/dekódování
load time         # čas a časovače
load os           # spouštění programů
load http         # HTTP(S) požadavky
load env          # proměnné prostředí
load system       # správa systému (balíčky, služby)
```

Standardní moduly se hledají automaticky — nemusíte je mít ve svém
adresáři. Jejich podrobný popis najdete v kapitole [06 — Moduly a
standardní knihovny](06-modules-and-imports.md).

### Cyklické importy — to nedělejte!

Když `a.lsl` importuje `b.lsl` a `b.lsl` importuje `a.lsl`, vznikne
cyklus. To LSL zakazuje — dostanete chybu při překladu. Řešení:
vytáhněte společnou část do třetího modulu, který oba importují.

## Praktický příklad: jednoduchá aplikace

Ukážeme si, jak strukturovat malý projekt pomocí funkcí, tříd a modulů:

```lsl
# soubor: spravce_ukolu.lsl (hlavní program)
load ukoly

function hlavni_smycka():
    seznam = ukoly.SeznamUkolu()
    seznam.pridej("Nakoupit")
    seznam.pridej("Vyvenčit psa")
    seznam.pridej("Napsat zprávu")
    seznam.spln(1)     # splní druhý úkol

    print "Všechny úkoly:"
    for u in seznam.vsechny():
        stav = "✓" if u[1] else " "
        printl "  [{stav}] {u[0]}"
    end

    printl "Splněno: {seznam.pocet_splneno()}/{seznam.pocet_vsech()}"
end

call hlavni_smycka()
```

```lsl
# soubor: ukoly.lsl (modul s logikou)
class SeznamUkolu(True):
    ctype Public

    function init(self):
        self.ukoly = []       # List dvojic [text, splneno]
    end

    function pridej(self, text):
        self.ukoly.append([text, False])
    end

    function spln(self, index):
        if index >= 1 and index <= len(self.ukoly):
            self.ukoly[index - 1][1] = True
        end
    end

    function vsechny(self):
        return self.ukoly
    end

    function pocet_vsech(self):
        return len(self.ukoly)
    end

    function pocet_splneno(self):
        pocet = 0
        for u in self.ukoly:
            if u[1]:
                pocet += 1
            end
        end
        return pocet
    end
end
```

## Shrnutí

| Koncept | Syntaxe | K čemu to je |
|---|---|---|
| Definice funkce | `function jmeno(param): ... end` | Pojmenování opakovaného kódu |
| Volání funkce | `vysledek = funkce(args)` | Provedení kódu a získání výsledku |
| Volání bez výsledku | `call funkce(args)` | Provedení kódu, výsledek se zahodí |
| Parametr | Uvnitř definice: `(a, b)` | Vstupní hodnoty pro funkci |
| Návratová hodnota | `return hodnota` | Co funkce vrací volajícímu |
| Funkce jako hodnota | `f = moje_funkce` | Uložení/předání funkce |
| Třída | `class Jmeno(True): ... end` | Šablona spojující data a chování |
| Konstruktor | `function init(self, ...):` | Inicializace nové instance |
| Metoda | `function metoda(self, ...):` | Funkce patřící třídě |
| Atribut instance | `self.jmeno` | Data patřící konkrétní instanci |
| Instance | `obj = Trida(args)` | Konkrétní objekt vytvořený z třídy |
| Import modulu | `load jmeno` | Načtení kódu z jiného souboru |
| Selektivní import | `from m load f as g` | Import jedné položky, případně s aliasem |
| Prefix modulu | `modul.funkce()` | Přístup k exportovaným položkám |
| Privátní třída | `ctype Private` | Třída není vidět mimo svůj modul |

## Kam dál

- [04 — Kolekce a datové struktury](04-collections.md): seznamy, slovníky,
  pole — jak ukládat a organizovat data.
- [05 — Zpracování chyb](05-error-handling.md): jak psát odolný kód, který
  se nevysype při prvním problému.
