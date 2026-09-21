# Specifikace Lux Simple Lang 0.6

Tento dokument je jazyková specifikace. Produkční implementace je pure-LSL self-hostovaný native compiler. Soubory používají UTF-8 a příponu `.lsl`.

## Základní pravidla

- Jeden příkaz je zpravidla na jednom řádku.
- `#` začíná komentář mimo řetězec.
- Blok začíná hlavičkou a končí samostatným `end`.
- Odsazení nemá význam, ale doporučují se čtyři mezery.
- Názvy rozlišují malá a velká písmena a mají tvar `[A-Za-z_][A-Za-z0-9_]*`.
- Literály a operátory používají čitelnou syntaxi: `+ - * / // % ^`, porovnání, `and`, `or`, `not`, `in` a závorky. `^` je pravostranně asociativní mocnina; staré `**` není od 0.6 platná syntaxe.
- Čárka odděluje argumenty. Víceřádkové `[]`, `()`, `{}` je jeden logický příkaz.

## Proměnné a typy

```lsl
enabled = True
count = 42
ratio = 1.5
name = "Lux"
nothing = None
```

Lokální proměnná musí být přiřazená na každé dosažitelné cestě před čtením.
Čtení před pozdějším přiřazením (také přes `+=`, `++`, větve, smyčky nebo
`safe`) je chyba překladu E2002; obsah neinicializovaného slotu není hodnota.
`del(x)` znovu zneplatní inicializaci. Parametry jsou inicializované při volání.

Volitelně lze proměnnou omezit na konkrétní vestavěný typ:

```lsl
Int(i) = 10
String(name) = "Lux"
List(items) = [1, 2]
i++
--i
```

`Int(i) = ...` je deklarace, nikoli převod hodnoty. Omezení platí v celé
lexikální oblasti i pro pozdější přiřazení, `+=` a vazbu ve `for`.
Nesprávný typ vyvolá zachytitelný `TypeError` před změnou proměnné; pro
konverzi napište například `Int(i) = Int("10")`. Známý správný typ nepřidává
běhovou kontrolu. Podporované deklarace: `Int`, `Float`, `Bool`, `String`,
`List`, `Tuple`, `Dictionary`, `Set`, `RealArray`, `IntArray`, `FloatArray`,
`ByteArray`, `Function` a neomezující `Any`. Dvě různá omezení stejného jména
jsou E2003. Parametr funkce takto znovu deklarovat nelze; použijte nový lokál.

`i++`, `i--`, `++i`, `--i` jsou samostatné příkazy nad inicializovanou
číselnou proměnnou, ekvivalentní `+= 1` / `-= 1`. Nemají hodnotu výrazu;
`x = i++`, změna indexovaného prvku ani řetězení inkrementů nejsou podporované.

Vestavěné typy a návratové hodnoty `type(value)`:

| Hodnota | Typ |
|---|---|
| `True`, `False` | `Bool` |
| celé číslo | `Int` |
| desetinné číslo | `Float` |
| text | `String` |
| `[...]` | `List` |
| `(...)` | `Tuple` |
| `{key: value}` | `Dictionary` |
| `![...]` | `RealArray` |
| `IntArray()` | `IntArray` |
| `FloatArray()` | `FloatArray` |
| `ByteArray()` | `ByteArray` |
| `None` | `None` |

`Bool(value)`, `Int(value)`, `Float(value)`, `String(value)`, `List(value)`, `Tuple(value)` a `Dictionary(value)` převádějí hodnoty. `IntArray()`, `FloatArray()` a `ByteArray()` vytvářejí prázdná měnitelná typed pole; volání s jedním argumentem je checked cast existujícího pole stejného typu. Přiřazení podporuje také `+=`, `-=`, `*=`, `/=`, `%=`, `&=`, `|=`, `~=`, `<<=` a `>>=`.

`Int` je signed 64-bit two's-complement hodnota. Aritmetika, mocnina, negace a převod z desetinného Stringu se definovaně redukují modulo `2^64`; nepoužívají `OverflowError`. `INT64_MIN // -1` proto vrací `INT64_MIN` a zbytek `0` bez CPU trapu.

Celočíselný literál lze zapsat i s prefixem `0x` (šestnáctkově), `0o` (osmičkově)
nebo `0b` (dvojkově); velikost písmen v prefixu i v číslicích nerozhoduje.
Literál se redukuje modulo `2^64` stejně jako desítkový, takže
`0xFFFFFFFFFFFFFFFF` je `-1` a `0x8000000000000000` je `INT64_MIN`.

### Bitové operátory

| Operátor | Význam |
|---|---|
| `a & b` | bitový AND |
| `a \| b` | bitový OR |
| `a ~ b` | bitový XOR |
| `~a` | bitový NOT (jedničkový doplněk) |
| `a << b` | posun vlevo |
| `a >> b` | aritmetický posun vpravo |

`~` je binárně XOR a unárně NOT, protože `^` je v LSL mocnina. Stejnou dvojroli
má `~` v Lua, odkud LSL přebírá i `^` a `//`.

Priorita zdola nahoru je `or`, `and`, porovnání, `|`, `~`, `&`, `<<` a `>>`,
`+` a `-`, `*` `/` `//` `%`, unární operátory, `^`. Platí tedy
`1 << 2 + 1 == 8` a `5 & 3 | 8 == 9`.

Operandy musí být `Int` nebo `Bool`; `Bool` se počítá jako `0`/`1` a výsledek je
vždy `Int`. Statický `Float` nebo kolekce jsou chyba překladu, dynamická hodnota
jiného typu skončí za běhu `TypeError` — nikdy se nečtou bity živého pointeru.

Posun je definovaný i mimo rozsah slova: záporný počet je `ValueError`,
`a << b` pro `b >= 64` je `0` a `a >> b` pro `b >= 64` je `0` pro nezáporné `a`
a `-1` pro záporné. `a >> b` je tedy přesně `a // 2^b` a `a << b` je
`a * 2^b` v Int64 wrapu.

```lsl
packed = 0
for byte in [1, 2, 3, 4]:
    packed = (packed << 8) | byte
end
print packed                  # 16909060
print (packed >> 16) & 0xFF   # 2
```

Pozor: `not` je unární operátor, takže váže silněji než porovnání i než bitové
operátory. `not 0 & 1` je `(not 0) & 1`, ne `not (0 & 1)`.

Pro celá čísla libovolné velikosti slouží standardní modul `bigint`:

```lsl
load bigint

huge = bigint.BigInt("1000000000000000000000000000000")
print huge.multiply(huge).text()
```

`BigInt` podporuje `add`, `subtract`, `multiply`, `floor_divide`, `modulo`,
`power`, `compare`, `equals`, `negate`, `absolute`, `text` a kontrolovaný
`to_int`. `SuperInt` je kompatibilní alias. BigInt je oddělený typ úmyslně,
aby běžný `Int64` neztratil nativní výkon.

Dictionary klíče mohou být immutable scalar hodnoty `String`, `Int`, `Bool`, `None`, `Float` nebo `Function`. Collection, Dictionary, Class a Instance klíče compiler odmítá; tím hash index nezávisí na pozdější mutable změně klíče.

## Výstup a vstup

```lsl
name = input "Jméno: "
print "ahoj", name, "je ti", 1 + 10
printl "ahoj {name}, je ti {1 + 10}"
text = l"ahoj {name}, je ti {1 + 10}"
print text
```

`print` odděluje hodnoty mezerou a přidá nový řádek. Prefix `l` vytváří first-class Lux String: výrazy v `{...}` vyhodnotí hned na místě a výsledek lze přiřadit, vrátit z funkce nebo předat jako argument. `{{` a `}}` zapisují doslovné složené závorky. `printl "..."` zůstává kompatibilní zkratka. Původní zkrácená syntaxe `input "prompt"` i obecná call syntaxe `input("prompt")` vypíšou prompt bez newline, přečtou jeden celý stdin řádek do dynamicky rostoucího bufferu, odstraní koncové LF/CRLF a vrátí UTF-8 `String`.

Veřejné CLI bez argumentů čte jednu translation unit ze stdin. Na TTY zobrazuje banner a `>>>`; samostatný řádek `exit` nebo Ctrl-D vstup ukončí. Pipe končí pouze EOF a heredoc pouze svým shellovým delimiterem — nepřidává se do něj ještě `exit`. Poté se celek jednou přeloží a spustí. V pipe/heredoc režimu se prompty nevypisují. Interaktivní terminátor `exit` není součást jazyka a nesmí se zaměňovat s voláním `exit(status)`.

## Podmínky

```lsl
if score > 90:
    print "A"
elif score > 70:
    print "B"
else:
    print "C"
end
```

Dvojtečka za hlavičkou je volitelná. Spustí se nejvýše jedna větev.

## Smyčky

```lsl
for i in rang(1, 10):
    if i == 5:
        continue
    elif i > 7:
        break
    end
end

while ready == False:
    call poll()
end

loop:
    print "navždy, pokud nepřijde break"
    break
end
```

`rang(stop)`, `rang(start, stop)` a `rang(start, stop, step)` mají pravou mez exkluzivní. `range` je stejné aliasové jméno. `break` a `continue` smějí být jen uvnitř smyčky.

## Chyby

```lsl
safe:
    Error(ValueError: tato chyba se zahodí)
end

try:
    Error(NetworkError: primární cesta selhala)
else:
    print "fallback"
end
```

`safe` při runtime chybě přeskočí zbytek svého bloku. `try/else` spustí `else` pouze tehdy, když `try` selže. `Error(Type: message)` vyvolá vlastní chybu. `check(condition, message)` vyvolá chybu při nepravdivé podmínce. Syntaktické chyby při parsování nelze zachytit uvnitř stejného zdroje.

Od 0.8.2 se neznámá funkce/proměnná, neexistující metoda a podporované
staticky zjistitelné chyby typů či argumentů uvnitř `safe`/`try` přeloží
na běhové `NameError`/`AttributeError`/`TypeError`. Totéž platí v tělech
funkcí, aby chybu mohl zachytit volající. Mimo funkce a ochranné bloky
zůstává přímá statická diagnostika. Chyba vzniká jen při dosažení vadného
výrazu; zbytek bloku se neprovede. Známá volání nepoužívají nový dynamický
lookup ani další kontroly. Zásobník se při zachycení vrátí na hranici rámce.
Syntaktické chyby, chybějící importy, nepodporované konstrukce, porušení
safe/sandbox pravidel, vyčerpání alokátoru, signály OS a `exit()` nejsou
potlačované. `safe` nevrací zpět již provedené I/O ani změny kolekcí.

## Funkce

```lsl
function motor(power):
    return power * 2
end

call motor(10)
result = motor(10)
```

`call` zahodí návratovou hodnotu; běžné volání ji lze použít ve výrazu.
`return` bez hodnoty vrátí `None`. Funkce čtou globální scope, zápis je
lokální pro aktuální volání. Funkce bez defaultů jsou first-class hodnoty:
lze je uložit, vrátit a předat jako callback (`type(callback)` je `Function`).
Lexikální closures nejsou podporovány.

Od 0.7.8 lze deklarovat `function f(a, b=2)` a volat `f(1)` nebo
`f(b=4, a=1)`. Default musí být immutable literál: číslo (i se znaménkem),
String, Bool nebo None. Povinné parametry předcházejí volitelným;
poziční argumenty předcházejí pojmenovaným. Chybějící, neznámé a duplicitní
argumenty compiler odmítne. Platí také pro metody, konstruktory a origin.
Builtin keyword volání, *args/**kwargs, keyword-only parametry a
first-class Function hodnoty s defaulty zatím nejsou podporovány.

Pořadí vyhodnocení více argumentů není součástí veřejného kontraktu; kód nesmí záviset na pořadí jejich vedlejších efektů. Compiler smí neunikající přímou funkci specializovat podle stabilně odvozených typů argumentů. First-class callback a dynamická introspekční hranice vždy zachovávají obecný tagged ABI.

## Třídy a instance

```lsl
class Auto:
    ctype Public
    wheels = 4

    function init(self, brand):
        self.brand = brand
    end

    function motor(self, power):
        return self.brand + ": " + String(power)
    end
end

car = Auto("Lux")
print car.wheels, car.motor(10)
```

`ctype Public` je výchozí; `ctype Private` zabrání exportu třídy z modulu.
Funkce s prvním parametrem přesně `self` se při přístupu přes instanci váže
jako metoda. `init(self, ...)` je volitelný konstruktor. Historický zápis
`class Name(True)` zůstává kompatibilní.

Jednoduchá dědičnost používá rodiče v závorkách. Potomek dědí konstruktor i
ostatní metody, vlastní metoda je přepíše a `origin` volá implementaci
bezprostředního rodiče:

```lsl
class ElectricCar(Auto):
    function init(self, brand, capacity):
        call origin.init(brand)
        self.capacity = capacity
    end

    function motor(self, power):
        return origin.motor(power) + " electric"
    end
end
```

LSL podporuje jednu rodičovskou třídu a cyklickou dědičnost odmítá při
překladu.

## Kolekce

```lsl
items = ["A", 1, True]
point = (10, 20)
fixed = ![1, 2, 3]
integers = IntArray()
integers.append(10)
integers.append(20)
data = {
    "A": "ahoj"
    "B": "balet"
}

items.append("konec")
items.extend([2, 3])
a = items[0]
b = items(1)        # alternativní indexace
items[2] = "ahoj"
fixed[1] = 8
del(items[0])
```

Čárky mezi řádky jednoduchého víceřádkového dictionary jsou volitelné. `RealArray` lze indexově měnit, ale jeho délka je pevná: `append`, `extend`, `pop` a `del(fixed[i])` selžou.

`IntArray` ukládá hodnoty přímo jako contiguous Int64 bez per-element objektu. `FloatArray` stejně ukládá raw IEEE-754 Float64 bity a poskytuje nativní `float_zeros`, `float_fill`, `float_sum`, `float_dot`, `float_axpy` a `float_matmul` kernely. Kernely běží nad dvěma SSE2 lane (packed double) se skalárním ocasem; `float_sum` a `float_dot` sčítají sudé a liché prvky v oddělených akumulátorech a na konci je spojí, takže se u dlouhých polí mohou v posledních bitech lišit od sekvenčního součtu. `float_axpy`, `float_fill` a `float_matmul` provádějí po prvcích stejné operace ve stejném pořadí jako skalární smyčka. `ByteArray` je packed byte buffer (jeden byte na prvek) pro `readbytes`/`writebytes` a nativní/OS I/O. Indexace a iterace mají statický typ `Int`, resp. `Float`; `append` a indexové přiřazení odmítnou chybný typ a ByteArray navíc hodnoty mimo `0..255`. Pro heterogenní data zůstává `List`.

Povolené metody:

- List: `append`, `extend`, `insert`, `pop`, `remove`, `clear`, `index`, `count`, `sort`, `reverse`, `copy`
- Dictionary: `get`, `keys`, `values`, `items`, `update`, `pop`, `clear`, `setdefault`, `copy`
- String: `lower`, `upper`, `split`, `strip`, `lstrip`, `rstrip`, `replace`, `join`, `startswith`, `endswith`, `title`, `capitalize`, `find`, `count`
- Tuple/RealArray: `index`, `count`; RealArray navíc `copy`
- IntArray: `append`, `clear`; dále indexace, indexové přiřazení, slicing, `len` a iterace
- FloatArray: `append`, `clear`; dále indexace, indexové přiřazení, slicing, `len`, iterace a nativní Float kernely
- ByteArray: `append`, `clear`; dále packed indexace, indexové přiřazení,
  slicing, `len`, iterace, `readbytes` a `writebytes`

Indexace a slicing (`value[start:stop]`) mají pravou mez exkluzivní a podporují záporné indexy. String indexy, `len`, slicing, iterace, `find` a `index` počítají validní Unicode code points, ne UTF-8 bajty.

## Vlákna a atomické operace

`thread_spawn(function)` spustí zadanou funkci bez parametrů v novém vláknu
se sdílenou pamětí (Linux `clone` s `CLONE_VM|CLONE_THREAD`) a vrátí Int
identifikátor vlákna, nebo `-1`, když je tabulka vláken plná (127 současně
běžících workerů) nebo se nepodařilo namapovat 8 MiB zásobník.
`thread_join(tid)` blokuje, dokud worker neskončí, a vrátí `0`; pro neznámý
`tid` (nikdy nespuštěný nebo slot už znovu použitý) vrátí `126`. Návratová
hodnota worker funkce se zahazuje; neodchycená výjimka ve workeru ukončí celý
proces stejně jako v hlavním vláknu.

```lsl
counter = IntArray()
counter.append(0)

function bump():
    i = 0
    while i < 1000:
        call atomic_add(counter, 0, 1)
        i += 1
    end
    return None
end

t = thread_spawn(bump)
u = thread_spawn(bump)
print thread_join(t), thread_join(u), counter[0]   # 0 0 2000
```

`popcount(x)` a `trailing_zeros(x)` jsou bitové builtiny nad `Int` (instrukce POPCNT/TZCNT; `trailing_zeros(0)` vrací 64). `cpu_count()` vrátí počet CPU dostupných procesu (affinity maska, respektuje `taskset`/cgroup; při chybě `1`) — podle něj dimenzujte počet workerů; paralelismus je vždy explicitní, kernel pak vlákna rozloží na jádra sám. Worker funkce nemá parametry: index práce si worker vezme z globálního `IntArray` čítače přes `atomic_add`.

Data si vlákna předávají přes globální proměnné. Běžné zápisy do sdílených
kolekcí nejsou synchronizované; pro sdílené čítače a zámky slouží lock-free
builtiny nad sloty `IntArray`: `atomic_add(array, index, delta)`,
`atomic_xchg(array, index, value)` a `atomic_cas(array, index, expected, new)`
vrací předchozí hodnotu slotu (`lock xadd`/`xchg`/`cmpxchg`, bez kontroly
mezí), `atomic_pause()` je `PAUSE` hint pro spin-wait smyčky.

Allokátor je chráněn futex mutexem, který se aktivuje až prvním
`thread_spawn`; jednovláknové programy neplatí nic. `gc()` smí volat jen hlavní
vlákno: zastaví workery signálem `SIGUSR1`, konzervativně projde jejich živé
zásobníky (včetně registrů uložených v signal frame) a po sweepu je probudí.
Ve workeru `gc()` vrátí `0` bez akce.

## Mazání

```lsl
del(name)
del(items[0])
del(object.member)
```

Mazat lze proměnnou, měnitelný index nebo člen LSL instance/třídy.

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


### Řazení a deduplikace (od 0.8.1)

`sorted(iterable)` vrací nový stabilně vzestupně seřazený List bez změny
vstupu. Přijímá sekvence, Set a Dictionary (klíče); prvky musí být kompatibilní
čísla nebo String. Podporován je jeden argument, zatím bez `key`/`reverse`.
`dedup(list)` vrací mělký List bez duplicit podle strukturální LSL rovnosti,
v pořadí prvních výskytů. Přijímá i vnořené měnitelné kolekce; původní list
nemění. `.sort()` nadále řadí na místě.

`set()` / `set(iterable)` vytváří samostatný měnitelný typ `Set`. Prvky jsou
neměnné skaláry nebo rekurzivně neměnné Tuple. Podporuje členství, délku,
pravdivost, iteraci, porovnání rovnosti bez ohledu na pořadí, převod na List
a metody `add`, `discard`, `remove`, `pop`, `clear`, `copy`, `update`, `union`,
`intersection`, `difference`, `symmetric_difference`, `issubset`, `issuperset`
a `isdisjoint`. Iterace/rendering zachovává pořadí vložení; `pop()` odebere
poslední prvek. `remove` chybějícího prvku a `pop` prázdného Set vyvolají
`KeyError`. Indexace, slicing, použití jako klíč Dictionary, set literály
a operátorové zkratky nejsou podporované. Lookup je lineární; Set konstrukce
i `dedup` mají v nejhorším případě kvadratický počet porovnání.

## Moduly

```lsl
load lux
load tensor as t
from lux load l as value_type
print lux.version, value_type([1, 2])
```

`load foo.bar` hledá `foo/bar.lsl` nejprve vedle zdrojového souboru, v compiler interních a built-in/system `lib/lsl/stdlib` cestách a teprve potom pod `~/.local/lib/lsl/stdlib`. `load foo.bar as baz` zpřístupní stejný staticky linkovaný modul pod prefixem `baz.`. Uživatelskou knihovnu lze získat přes `lsl install NAME`; built-in modul proto nelze uživatelskou kopií zastínit. Modulové symbols dostávají deterministický namespace prefix. Třídy označené `ctype Private` nejsou dostupné přes vnější namespace; public classes lze přímo konstruovat. `native` modul podporuje omezené self-contained Linux x86_64 ET_DYN Int64 kernels; obecné relocatable/libc pluginy nejsou součástí ABI v1.

Chybějící knihovna hlásí E3001 s názvem a přesným místem importu, včetně
importů uvnitř jiné knihovny. Výpis doporučí kontrolu místního souboru a pro
registry jméno `lsl search NAME` / `lsl install NAME`; nic sám nestahuje.
Chybějící built-in modul znamená poškozenou instalaci LSL, ne balíček k
doinstalování. Existující, ale nečitelný modul má samostatnou chybu E3002.

Grafický příklad [Snake](../examples/snake.lsl) potřebuje volitelné balíčky
`display` a `gfx` (`lsl install display`, `lsl install gfx`). X11 zápis
pokračuje i po částečném odeslání a čeká na uvolnění plného socketu. Odpojení
nebo timeout hlásí zachytitelný `X11Error`; po přerušeném přenosu je třeba
zavřít a znovu otevřít okno.

Vestavěný modul `lux` exportuje `version`, `language` a `l` (alias `type`). Další standardní moduly jsou `json`, `lconf`, `http`, `httpserver`, `sandbox`, `env`, `config`, `time`, `os`, `system`, `math` a `bigint`; podrobnosti jsou v `configuration.md`, `lconf.md`, `ai.md`, `server.md`, `sandbox.md`, `time.md`, `os.md` a `system.md`.

## Standardní funkce

- matematika: `min`, `max`, `sum`, `abs`, `sqrt`; modul `math` přidává
  exponenciálu, logaritmy, goniometrii, Sigmoid a statistiku
- znaky: `chr`, `ord`
- čas: `clock()` — čitelný String `YYYY-MM-DD HH:MM:SS UTC`; `monotonic()` — monotónní sekundy jako Float; modul `time` přidává Unix timestamp a `sleep`
- procesy: `system(command)` — vestavěný alias `os.run(command)` bez `load os`; String nebo argv List, hledání v PATH, návratový exit status, bez shell expanze
- soubory UTF-8: `readfile(path)`, `writefile(path, value)`, `appendfile(path, value)`, `exists(path)`
- Linux/POSIX filesystem: `cwd()`, `chdir(path)`, `mkdir(path)`, `remove_path(path)`
- proces: globální `args`, `arg(index)`, `arg_count()`, `run(program, arguments)`; modul `os` přidává bezpečné command String/List API a PATH lookup; dále `capture(program, arguments)`, `capture_stream(program, arguments, callback)`, `capture_input(program, arguments, input_text)`, `capture_status()`, `exit(status)`; `process.capture_result`/`process.capture_input_result` vrací `{stdout, stderr, status, ok}` a `process.check`/`process.check_input` vyvolá `ProcessError`; status je exit code, pro signál `128 + signal`, při selhání fork/wait 126 a při selhání exec 127
- environment: pouze přes modul `env` — `env.get(name, default)`, `env.has(name)`, `env.require(name)`; v pure config režimu není dostupný
- chyby: `last_error()` vrátí poslední chybu zachycenou `safe` nebo `try`
- nápověda: `help()` / `help("TOPIC")`; téma může být runtime String,
  návratová hodnota je None, neznámé téma vyvolá HelpError

## Garantované optimalizace codegenu

Optimalizace nemění pozorovatelnou sémantiku ani pořadí dynamických vedlejších efektů. Compiler skládá konstantní Int podvýrazy, odstraňuje konstantně mrtvé větve a nedosažitelný kód za terminátorem, používá immediate scalar aritmetiku/compare, deduplikuje String templates a konzervativně specializuje přímé neunikající funkce. Pro callbacky, explicitní dynamickou introspekci a nejednoznačné typy zůstává obecný boxed/tagged kód.

Int constant folding používá stejné modulo `2^64` a floor `//`/`%` chování jako runtime. Float výrazy se compile-time neskládají, aby zůstaly přesné NaN, Infinity, signed-zero a subnormal hrany. Podrobnosti a výkonová doporučení jsou v [programming.md](programming.md).

## Bezpečnost

Běžný programovací režim není bezpečnostní sandbox. Výchozí `lsl compile`
však odmítá privátní `__lsl_*`, native a thread operace mimo lexikální
`unsafe:` blok a kontroluje i uživatelské importy. Direktiva
`# lsl: unchecked-intarray` vyžaduje `lsl compile --unsafe`; nízkoúrovňový
`lslc` zůstává explicitní trust-core compiler.

`lsl sandbox` unsafe zdroj vůbec nepřeloží a spustí program v oddělených Linux
namespaces, prázdném root filesystemu a cgroup/resource limitech. Host cesty
jsou dostupné jen přes explicitní `--read`/`--write` capabilities. Podrobnosti
jsou v [bezpečnostním modelu](security.md) a [sandbox příručce](sandbox.md).
