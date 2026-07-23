# Programování v LSL 0.7

Toto je praktický průvodce pro autory aplikací. Přesná syntaxe a hraniční
sémantika jsou v [language.md](language.md); interní compiler je popsaný v
[compiler-development.md](compiler-development.md).

## První program

```lsl
name = input "Jméno: "
print "Ahoj", name
```

Spuštění ze zdroje, vytvoření samostatného ELF a jeho spuštění:

```text
./lsl hello.lsl
./lsl compile hello.lsl hello
./hello
```

`./lsl hello.lsl arg1 arg2` program nejprve přeloží a spustí. Pro opakované
spouštění používejte jednou přeložený ELF. Výsledek je statický Linux x86_64
program bez libc a dynamic loaderu.

Bez argumentů se spustí interaktivní zápis jedné společné translation unit:

```text
$ ./lsl
Lux Simple Lang 0.7 interactive source mode
Enter code; type exit on its own line to compile and run.
>>> value = 6 * 7
>>> print value
>>> exit
42
```

Bloky pište normálně včetně `end`. Na TTY samostatný řádek `exit` zápis ukončí
a celý zdroj jednou přeloží/spustí; `exit(status)` uvnitř programu zůstává
běžná funkce. Ctrl-D/EOF je také konec. Pipe skončí EOF a nepoužívá `exit`:

```text
printf 'print "ze stdin", 21 * 2\n' | ./lsl
```

Heredoc používá právě jeden shellový delimiter a žádný vnitřní terminátor:

```text
./lsl <<'EOF'
print "ze stdin", 21 * 2
EOF
```

`EOF` je libovolně pojmenovaný marker shellu, nikoli LSL syntaxe. Jde o
interaktivní native source mode, nikoli interpretaci každého řádku zvlášť:
díky tomu mají všechny řádky společný scope a žádný dřívější side effect se při
dalším vstupu neopakuje. Diagnostika používá cestu `<stdin>` a relativní `load`
hledá moduly z aktuálního pracovního adresáře.

Argumenty jsou dostupné přes `arg(index)`, `arg_count()` a globální `args`:

```lsl
if arg_count() < 2:
    print "usage: app INPUT"
    exit(2)
end
print readfile(arg(1))
```

## Soubory a moduly projektu

Doporučené rozložení:

```text
my-app/
  main.lsl
  model.lsl
  util/
    text.lsl
```

```lsl
# main.lsl
load model
from util.text load normalize as clean

item = model.create(clean("  Lux  "))
print item["name"]
```

`load model` hledá `model.lsl` vedle souboru, který import provedl. Tečkové
jméno `load util.text` odpovídá `util/text.lsl`. Standardní moduly se hledají v
`stdlib/`, respektive po instalaci v `<prefix>/lib/lsl/stdlib`. Importy jsou
staticky slinkované; za běhu se žádný modulový loader nespouští.

Modul exportuje své globální hodnoty a funkce. Třída s `ctype Private` se mimo
modul neexportuje. Cyklické importy jsou chyba.

## Volba datového typu

- `Int`, `Bool`, `None`, `Float` a `String` používejte pro skalární hodnoty.
- `List` je univerzální heterogenní měnitelná kolekce.
- `Tuple` je kolekce s pevnou délkou.
- `Dictionary` je mapa s immutable scalar klíči.
- `RealArray` má pevnou délku, ale stále dynamické prvky.
- `IntArray` ukládá souvislé raw Int64.
- `FloatArray` ukládá souvislé IEEE-754 Float64.
- `ByteArray` ukládá přesně jeden byte na prvek.

Pro větší numerická nebo binární data nepoužívejte `List`, pokud nepotřebujete
heterogenní prvky:

```lsl
samples = FloatArray()
samples.append(1.5)
samples.append(2.5)
print float_sum(samples)

payload = readbytes("image.bin")
payload[0] = 127
call writebytes("copy.bin", payload)
```

`FloatArray` poskytuje bulk kernely `float_fill`, `float_sum`, `float_dot`,
`float_axpy` a `float_matmul`. `stdlib/tensor.lsl` nad ním přidává shape,
strides, views a maticové operace. Bulk kernel je rychlejší než uživatelská
smyčka s indexací a zároveň dává compileru jasnější záměr.

## Řízení toku

```lsl
if score >= 90:
    grade = "A"
elif score >= 70:
    grade = "B"
else:
    grade = "C"
end

for i in rang(0, 100, 2):
    print i
end

while pending:
    call process_one()
end
```

`rang` má exkluzivní pravou mez. Stop i step výraz se vyhodnotí jednou před
smyčkou. `break` a `continue` fungují ve všech druzích smyček.

## Funkce a callbacks

```lsl
function square(value):
    return value * value
end

function apply(callback, value):
    return callback(value)
end

print square(9), apply(square, 10)
```

Parametry jsou poziční. Funkce nemají deklarované typy ani closures. Compiler
konzervativně odvozuje stabilní typy argumentů přímých funkcí a může pro ně
použít neboxovaný fast path. Jakmile se funkce předá jako callback nebo program
používá explicitní dynamickou introspekci, zůstává na obecném tagged ABI.
Výsledek je vždy sémanticky stejný; optimalizace není důvod měnit API programu.

Pořadí vedlejších efektů uvnitř více argumentů není v 0.7 veřejný kontrakt.
Nevkládejte proto několik zápisů nebo závislých I/O operací do jednoho volání;
nejdřív je přiřaďte do pojmenovaných hodnot.

## Třídy

```lsl
class Counter(True):
    ctype Public
    value = 0

    function init(self, start):
        self.value = start
    end

    function increment(self):
        self.value += 1
        return self.value
    end
end

counter = Counter(10)
print counter.increment()
```

Instance a třídy jsou dynamické Dictionary objekty. Pro jednoduchá datová
potrubí bývá obyčejný `Dictionary` levnější a průhlednější; třídu použijte tam,
kde dává smysl společné chování a stav.

## Chyby a cleanup

```lsl
try:
    text = readfile("settings.json")
else:
    print "nelze načíst konfiguraci:", last_error()
    text = "{}"
end

check(len(text) > 0, "prázdný vstup")
```

- `Error(Type: message)` vyvolá chybu.
- `try/else` provede fallback při chybě.
- `safe` chybu zahodí a pokračuje za blokem.
- `last_error()` vrátí poslední zachycenou zprávu.
- `check` je vhodný pro invarianty a validaci hranic.

LSL používá GC, ale procesy, nativní library handles a protokoly mají explicitní
životní cyklus. `native.open` vždy párujte s `native.close`; u procesních API
kontrolujte strukturovaný `status`/`ok`.

## Soubory, procesy a síť

Textové API používá UTF-8 String; binární API používá ByteArray:

```lsl
writefile("note.txt", "ahoj\n")
text = readfile("note.txt")
bytes = readbytes("note.txt")
```

Proces spouštějte oddělenými argv, nikdy skládáním shell command stringu:

```lsl
load process
result = process.capture_result("/usr/bin/tool", ["--input", "data value"])
if not result["ok"]:
    Error(ProcessError: result["stderr"])
end
print result["stdout"]
```

Pro pohodlné Linux příkazy bez shellu použijte `os`; command musí být String
nebo List[String]:

```lsl
load os

call os.run("ls -al")
result = os.capture_result(["uname", "-a"])
print result["stdout"], result["status"]
```

Zápis `os.run(ls -al)` bez uvozovek není command literal: v LSL by znamenal
odečítání proměnných `ls` a `al`. `os` podporuje quotes/backslash a PATH lookup,
ale záměrně ne shell pipes, redirection ani expanzi. Viz [os.md](os.md).

Konfigurace balíčků LuxOS je obyčejný LSL program. Modul `system` nejdřív zkusí
Lux a při nenulovém statusu použije apt:

```lsl
load system

for package in ["git", "curl"]:
    call system.install(package)
end
```

Program spusťte běžně jako `./lsl machine.lsl`; nejde o čistý `lsl config`
režim. Funkce skutečně mění systém a vyžadují odpovídající oprávnění. Viz
[system.md](system.md).

`http` používá `/usr/bin/curl` přes `execve`, bez shellové interpolace. Secrets
načítejte přes modul `env`; neukládejte je do config výstupu. Podrobnosti jsou v
[ai.md](ai.md), [configuration.md](configuration.md) a
[native-plugins.md](native-plugins.md).

## Čas a timeouty

```lsl
load time

started = time.monotonic()
call time.sleep(0.1)
print time.monotonic() - started
print time.time()  # Unix timestamp
```

Intervaly měřte přes `time.monotonic()` nebo `time.perf_counter()`, ne přes wall
clock, který může správce systému změnit. `time.sleep()` používá `nanosleep` a
po `EINTR` pokračuje se zbývající dobou. Celé API a chyby popisuje
[time.md](time.md).

## Co compiler optimalizuje automaticky

Codegen 0.7 bezpečně provádí:

- skládání konstantních celočíselných podvýrazů;
- odstranění konstantně neproveditelných větví a `while False`;
- odstranění kódu za bezpodmínečným `return`, `break`, `continue` nebo `Error`;
- immediate aritmetiku a přímé scalar compare/branch instrukce;
- deduplikaci stejných String templates;
- konzervativní specializaci neunikajících přímých helper funkcí;
- sílu dělení/módula konstantní mocninou dvou a magic division;
- kompaktní x86-64 immediates, stack offsets a memory displacements.

Proto například následující zápis negeneruje násobení a sčítání konstant při
každém průchodu:

```lsl
total = 0
for i in rang(1000000):
    total = total + ((2 + 3) * (4 + 5)) + 0
end
```

Compiler ale nemůže opravit špatný algoritmus, zbytečné I/O, nevhodnou datovou
strukturu nebo skryté vedlejší efekty. Pro numeriku stále volte typed arrays a
bulk kernely, pro opakované spuštění předem přeložený ELF a pro obecný plugin
izolované process ABI.

## Ladění a testování

Compiler vypisuje kód chyby, source span, caret a nápovědu. Runtime chyby jdou na
stderr a proces končí nenulově, pokud je nezachytí `safe` nebo `try`.

Pro malý projekt udržujte vstup a očekávaný výstup vedle sebe:

```text
./compiler/lslc app.lsl /tmp/app
/tmp/app > /tmp/app.out
cmp expected.out /tmp/app.out
```

Před reportem compiler chyby přiložte minimální `.lsl` reprodukci, přesný výstup
`./compiler/lslc`, Linux/x86_64 prostředí a commit/hash compileru.
