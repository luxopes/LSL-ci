# Specifikace Lux Simple Lang 0.7

Tento dokument je jazyková specifikace. Produkční implementace je pure-LSL self-hostovaný native compiler. Soubory používají UTF-8 a příponu `.lsl`.

## Základní pravidla

- Jeden příkaz je zpravidla na jednom řádku.
- `#` začíná komentář mimo řetězec.
- Blok začíná hlavičkou a končí samostatným `end`.
- Odsazení nemá význam, ale doporučují se čtyři mezery.
- Názvy rozlišují malá a velká písmena a mají tvar `[A-Za-z_][A-Za-z0-9_]*`.
- Literály a operátory používají čitelnou syntaxi Pythonu: `+ - * / // % **`, porovnání, `and`, `or`, `not`, `in` a závorky.
- Čárka odděluje argumenty. Víceřádkové `[]`, `()`, `{}` je jeden logický příkaz.

## Proměnné a typy

```lsl
enabled = True
count = 42
ratio = 1.5
name = "Lux"
nothing = None
```

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

`Bool(value)`, `Int(value)`, `Float(value)`, `String(value)`, `List(value)`, `Tuple(value)` a `Dictionary(value)` převádějí hodnoty. `IntArray()`, `FloatArray()` a `ByteArray()` vytvářejí prázdná měnitelná typed pole; volání s jedním argumentem je checked cast existujícího pole stejného typu. Přiřazení podporuje také `+=`, `-=`, `*=`, `/=` a `%=`.

`Int` je signed 64-bit two's-complement hodnota. Aritmetika, mocnina, negace a převod z desetinného Stringu se definovaně redukují modulo `2^64`; nepoužívají `OverflowError`. `INT64_MIN // -1` proto vrací `INT64_MIN` a zbytek `0` bez CPU trapu.

Dictionary klíče mohou být immutable scalar hodnoty `String`, `Int`, `Bool`, `None`, `Float` nebo `Function`. Collection, Dictionary, Class a Instance klíče compiler odmítá; tím hash index nezávisí na pozdější mutable změně klíče.

## Výstup a vstup

```lsl
name = input "Jméno: "
print "ahoj", name, "je ti", 1 + 10
printl "ahoj {name}, je ti {1 + 10}"
```

`print` odděluje hodnoty mezerou a přidá nový řádek. `printl` nejdřív vyhodnotí svůj argument jako řetězec a pak vyhodnotí výrazy v `{...}`. Původní zkrácená syntaxe `input "prompt"` i obecná call syntaxe `input("prompt")` vypíšou prompt bez newline, přečtou jeden celý stdin řádek do dynamicky rostoucího bufferu, odstraní koncové LF/CRLF a vrátí UTF-8 `String`.

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

## Funkce

```lsl
function motor(power):
    return power * 2
end

call motor(10)
result = motor(10)
```

`call` zahodí návratovou hodnotu; běžné volání ji lze použít ve výrazu. Parametry jsou povinné a předávají se pozičně. `return` bez hodnoty vrátí `None`. Funkce čtou globální scope, zápis je lokální pro aktuální volání. Funkce jsou first-class hodnoty: lze je uložit, vrátit a předat jako callback (`type(callback)` je `Function`). Lexikální closures a keyword arguments nejsou součástí syntaxe 0.7.

Pořadí vyhodnocení více argumentů není v 0.7 součástí veřejného kontraktu; kód nesmí záviset na pořadí jejich vedlejších efektů. Compiler smí neunikající přímou funkci specializovat podle stabilně odvozených typů argumentů. First-class callback a dynamická introspekční hranice vždy zachovávají obecný tagged ABI.

## Třídy a instance

```lsl
class Auto(True):
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

Podmínka `class Name(condition)` určuje, zda se tělo třídy vykoná. Při `False` vznikne vypnutá definice bez členů. `ctype Public` je výchozí; `ctype Private` zabrání exportu třídy z modulu. Funkce s prvním parametrem přesně `self` se při přístupu přes instanci váže jako metoda. `init(self, ...)` je volitelný konstruktor.

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

`IntArray` ukládá hodnoty přímo jako contiguous Int64 bez per-element objektu. `FloatArray` stejně ukládá raw IEEE-754 Float64 bity a poskytuje nativní `float_zeros`, `float_fill`, `float_sum`, `float_dot`, `float_axpy` a `float_matmul` kernely. `ByteArray` je packed byte buffer (jeden byte na prvek) pro `readbytes`/`writebytes` a nativní/OS I/O. Indexace a iterace mají statický typ `Int`, resp. `Float`; `append` a indexové přiřazení odmítnou chybný typ a ByteArray navíc hodnoty mimo `0..255`. Pro heterogenní data zůstává `List`.

Povolené metody:

- List: `append`, `extend`, `insert`, `pop`, `remove`, `clear`, `index`, `count`, `sort`, `reverse`, `copy`
- Dictionary: `get`, `keys`, `values`, `items`, `update`, `pop`, `clear`, `setdefault`, `copy`
- String: `lower`, `upper`, `split`, `strip`, `lstrip`, `rstrip`, `replace`, `join`, `startswith`, `endswith`, `title`, `capitalize`, `find`, `count`
- Tuple/RealArray: `index`, `count`; RealArray navíc `copy`
- IntArray: `append`, `clear`; dále indexace, indexové přiřazení, slicing, `len` a iterace
- FloatArray: `append`, `clear`; dále indexace, indexové přiřazení, slicing, `len`, iterace a nativní Float kernely
- ByteArray: `append`, `clear`; dále packed indexace, indexové přiřazení, `len`, iterace, `readbytes` a `writebytes`

Indexace a slicing (`value[start:stop]`) mají pravou mez exkluzivní a podporují záporné indexy. String indexy, `len`, slicing, iterace, `find` a `index` počítají validní Unicode code points, ne UTF-8 bajty.

## Mazání

```lsl
del(name)
del(items[0])
del(object.member)
```

Mazat lze proměnnou, měnitelný index nebo člen LSL instance/třídy.

## Moduly

```lsl
load lux
from lux load l as value_type
print lux.version, value_type([1, 2])
```

`load foo.bar` hledá `foo/bar.lsl` nejprve vedle zdrojového souboru a poté v instalovaném `lib/lsl/stdlib`, odvozeném od cesty compileru. Modulové symbols dostávají deterministický namespace prefix. Třídy označené `ctype Private` nejsou dostupné přes vnější namespace; public classes lze přímo konstruovat. `native` modul podporuje omezené self-contained Linux x86_64 ET_DYN Int64 kernels; obecné relocatable/libc pluginy nejsou součástí ABI v1.

Vestavěný modul `lux` exportuje `version`, `language` a `l` (alias `type`). Další standardní moduly jsou `json`, `lconf`, `http`, `env`, `config`, `time`, `os` a `system`; podrobnosti jsou v `configuration.md`, `lconf.md`, `ai.md`, `time.md`, `os.md` a `system.md`.

## Standardní funkce

- matematika: `min`, `max`, `sum`, `abs`, `round`
- znaky: `chr`, `ord`
- čas: `clock()` — monotónní čas v sekundách; aplikační modul `time` přidává wall clock, pojmenovaný monotonic/perf counter a `sleep`
- soubory UTF-8: `readfile(path)`, `writefile(path, value)`, `appendfile(path, value)`, `exists(path)`
- Linux/POSIX filesystem: `cwd()`, `chdir(path)`, `mkdir(path)`, `remove_path(path)`
- proces: globální `args`, `arg(index)`, `arg_count()`, `run(program, arguments)`; modul `os` přidává bezpečné command String/List API a PATH lookup; dále `capture(program, arguments)`, `capture_stream(program, arguments, callback)`, `capture_input(program, arguments, input_text)`, `capture_status()`, `exit(status)`; `process.capture_result`/`process.capture_input_result` vrací `{stdout, stderr, status, ok}` a `process.check`/`process.check_input` vyvolá `ProcessError`; status je exit code, pro signál `128 + signal`, při selhání fork/wait 126 a při selhání exec 127
- environment: `getenv(name)` vrátí String nebo `None`; v pure config režimu není dostupné
- chyby: `last_error()` vrátí poslední chybu zachycenou `safe` nebo `try`
- nápověda: `help()`

## Garantované optimalizace codegenu

Optimalizace nemění pozorovatelnou sémantiku ani pořadí dynamických vedlejších efektů. Compiler skládá konstantní Int podvýrazy, odstraňuje konstantně mrtvé větve a nedosažitelný kód za terminátorem, používá immediate scalar aritmetiku/compare, deduplikuje String templates a konzervativně specializuje přímé neunikající funkce. Pro callbacky, explicitní dynamickou introspekci a nejednoznačné typy zůstává obecný boxed/tagged kód.

Int constant folding používá stejné modulo `2^64` a floor `//`/`%` chování jako runtime. Float výrazy se compile-time neskládají, aby zůstaly přesné NaN, Infinity, signed-zero a subnormal hrany. Podrobnosti a výkonová doporučení jsou v [programming.md](programming.md).

## Bezpečnost

Běžný programovací režim není bezpečnostní sandbox. LSL program může číst a zapisovat soubory, spouštět procesy nebo přes modul `system` měnit balíčky s právy aktuálního procesu. Oddělený `lsl config` režim staticky odmítá ambientní I/O, síť, environment a process capabilities.
