# 11. Výkon a optimalizace

Tato kapitola vysvětluje, jak psát rychlý LSL kód — čemu se vyhnout,
které konstrukce jsou pomalé a proč, a jak využít nativní kernely pro
maximální výkon.

## Než začnete optimalizovat

Od LSL 0.8.4 probíhá úklid nepoužívané paměti automaticky podle objemu
alokací. Do běžné herní smyčky není potřeba přidávat `gc()`.
Rozpočet začíná na 4 MiB a přizpůsobuje se živému heapu; není to limit RSS.
Nealokující číselné smyčky nemají GC kontroly. GC vrací bloky do alokátoru
pro další použití, nikoli nutně ihned operačnímu systému. Není to hard-real-time
collector: prodleva závisí na heapu a dlouhá jednotlivá operace může odložit
další bezpečný bod. Hlavní vlákno obsluhuje úklid i během `thread_join()`.

První pravidlo optimalizace: **neměřit znamená nevědět**. Než začnete
kód zrychlovat, změřte, kde tráví čas. LSL k tomu poskytuje
`time.perf_counter()` — monotónní čas s vysokým rozlišením.

Druhé pravidlo: **správnost před rychlostí**. Nejdřív napište kód,
který funguje. Teprve potom ho zrychlujte — a po každé změně ověřte,
že pořád funguje správně.

## Co compiler optimalizuje automaticky

Codegen LSL 0.6.9 bezpečně provádí tyto optimalizace (žádná nemění
pozorovatelnou sémantiku):

### 1. Constant folding (skládání konstant)

```lsl
# Toto se přeloží jako: result = 46
result = (2 + 3) * (4 + 5) + 1

# Int aritmetika je skládaná rekurzivně s modulo 2^64 wrapováním
# Float výrazy se NESKLÁDAJÍ compile-time (NaN, Infinity, signed zero)
```

### 2. Dead code elimination (odstranění mrtvého kódu)

```lsl
if False:
    print "Toto se nikdy nespustí a negeneruje kód"
end

while False:
    print "Ani toto"
end
```

### 3. Unreachable code elimination

Kód za bezpodmínečným `return`, `break`, `continue` nebo `Error()` se
odstraní:

```lsl
function early_exit(x):
    if x < 0:
        return 0
    end
    return x * 2
    # Kód za posledním return se negeneruje
end
```

### 4. Immediate aritmetika

Tam, kde compiler zná typy (Int), použije přímé x86-64 instrukce bez
boxingu:

```lsl
# Generuje přímé ADD/SUB/CMP instrukce
a = 10
b = 20
c = a + b
```

### 5. Deduplikace stringů

Stejné stringové templaty se v kódu uloží jen jednou:

```lsl
printl "Ahoj {name}"
printl "Ahoj {name}"  # Použije stejný template string
```

### 6. Specializace přímých funkcí

Funkce, které neuniknou jako callback a jejichž typy argumentů lze
stabilně odvodit, mohou být specializovány (neboxovaný fast path).

Jakmile funkci předáte jako callback, zůstane na obecném tagged ABI.

### 7. Efektivní dělení

- Dělení/modulo konstantní mocninou dvou → bitové operace.
- Obecné dělení → optimalizované algoritmy (magic division).

### 8. Kompaktní kódování

Compiler používá nejkratší možné x86-64 immediates, stack offsety a memory
displacements.

### 9. Malé mocniny a konstantní Stringy

`x ^ 0` až `x ^ 4` se emitují inline bez volání obecného power runtime a
základ se přitom vyhodnotí právě jednou. Strom složený pouze z konstantních
Stringů se spojí při překladu. Lux String používá vyvážený concat strom, takže
šablona s mnoha poli nekopíruje rostoucí prefix kvadraticky.

### 10. Registrové `for` smyčky

Staticky celočíselné čítače, indexy a akumulátory horkých smyček zůstávají v
callee-saved registrech. Compiler při tom počítá i skryté přístupy vytvořené
loweringem `for` a čtení i zápis složeného přiřazení, například `total += i`.
`rang(stop)` a `rang(start, stop)` používají přímou kladnou větev s krokem
jedna; dynamická kontrola znaménka a nulového kroku zůstává jen u varianty se
třetím argumentem.

## Co compiler NEoptimalizuje

- **Špatné algoritmy** — O(n²) zůstane O(n²).
- **Zbytečné I/O** — každé volání `readfile` uvnitř smyčky skutečně čte.
- **Nevhodné datové struktury** — List s 1M boxovaných Intů zůstane pomalý.
- **Skryté vedlejší efekty** — volání funkcí se neduplikuje ani
  nepřehazuje.

## Datové struktury a výkon

### Boxované vs neboxované typy

| Typ | Alokace na prvek | Použití |
|---|---|---|
| `Int` (skalár) | Ne (immediate) | Lokální proměnné, čítače |
| `Float` (skalár) | **Ano** (boxed na heap) | Jednotlivé desetinné hodnoty |
| `List` | **Ano** (každý prvek je heap objekt) | Heterogenní kolekce |
| `IntArray` | **Ne** (contiguous Int64) | Pole celých čísel |
| `FloatArray` | **Ne** (contiguous Float64) | Pole desetinných čísel |

### Pravidlo: Vyhýbejte se Floatům v horkých smyčkách

```lsl
# ŠPATNĚ — každá iterace alokuje boxovaný Float
total = 0.0
for i in rang(1000000):
    total = total + Float(i) * 1.5
end

# LÉPE — celočíselný výpočet
total = 0
for i in rang(1000000):
    total = total + (i * 3) // 2     # * 1.5 pomocí Int aritmetiky
end

# NEJLÉPE — bulk kernel nad FloatArray
data = FloatArray()
for i in rang(1000000):
    data.append(Float(i))
end
total = float_sum(data)
```

### Typované pole vs List

```lsl
# POMALÉ — List s boxovanými Int prvky
data = []
for i in rang(1000000):
    data.append(i)              # každý prvek je heap objekt
end
print len(data)

# RYCHLÉ — IntArray s raw Int64 prvky
data = IntArray()
for i in rang(1000000):
    data.append(i)              # ukládá se přímo jako Int64
end
print len(data)                 # ~4-10× rychlejší, méně paměti
```

## Nativní kernely

Pro maximální výkon numerických výpočtů používejte nativní runtime kernely.
Ty pracují přímo nad raw daty, bez boxingu a bez alokací v hot path.

### FloatArray kernely

```lsl
# Vytvoření pole
zeros = float_zeros(1000000)       # pole 1M nul (FloatArray)
data = FloatArray()
for i in rang(1000):
    data.append(Float(i) * 0.1)
end

# Součet všech prvků
total = float_sum(data)            # nativní kernel, O(n) bez boxingu

# Skalární součin
a = FloatArray()
b = FloatArray()
# ... naplnění ...
dot = float_dot(a, b)              # nativní kernel

# AXPY: y = alpha * x + y (in-place, BLAS level 1)
call float_axpy(2.5, x, y)        # y = 2.5*x + y

# Maticové násobení (BLAS level 3)
c = float_matmul(a, b, m, k, n)    # FloatArray(m*k) × FloatArray(k*n) → FloatArray(m*n)

# Vyplnění
call float_fill(data, 42.0)        # všechny prvky na 42.0
```

Kernely jsou vektorizované: pracují nad dvěma SSE2 lane (`movupd`,
`addpd`, `mulpd`) se skalárním ocasem pro lichou délku. `float_sum` a
`float_dot` drží sudé a liché prvky v oddělených akumulátorech a spojí je na
konci, takže se u velmi dlouhých polí mohou v posledních bitech lišit od čistě
sekvenčního součtu; `float_axpy`, `float_fill` a `float_matmul` dávají bitově
stejné výsledky jako skalární smyčka (matmul akumuluje řádek `C[i, :]` v
pořadí `k` s vysíláním `A[i, k]` do obou lane, což je zároveň cache-friendly —
256×256 matmul je proti skalární verzi přibližně 4,5× rychlejší).

Výkonnostní rozdíl oproti uživatelským smyčkám může být **400× a více**.
V horké smyčce nikdy neindexujte FloatArray po prvcích v LSL — použijte
bulk kernel.

### Srovnání: LSL smyčka vs kernel

```lsl
load time

# Verze s LSL smyčkou (POMALÁ)
a = FloatArray()
for i in rang(100000):
    a.append(Float(i) * 0.01)
end

start = time.perf_counter()
total_loop = 0.0
for i in rang(len(a)):
    total_loop = total_loop + Float(a[i])   # každá iterace boxuje!
end
elapsed_loop = time.perf_counter() - start
printl "Smyčka: {total_loop} za {elapsed_loop} s"

# Verze s kernelem (RYCHLÁ)
start = time.perf_counter()
total_kernel = float_sum(a)
elapsed_kernel = time.perf_counter() - start
printl "Kernel: {total_kernel} za {elapsed_kernel} s"

printl "Zrychlení: {elapsed_loop / elapsed_kernel}×"
```

## Modul tensor — vícerozměrná pole

Pro numerické výpočty s maticemi a tenzory použijte modul `tensor`:

```lsl
load tensor

# Vytvoření tenzoru
t = tensor.from_values([1.0, 2.0, 3.0, 4.0, 5.0, 6.0], [2, 3])
print t.shape       # [2, 3] — 2 řádky, 3 sloupce
print t.size()      # 6
print t.get([0, 0]) # 1.0
print t.get([1, 2]) # 6.0

# Reshape
t2 = t.reshape([3, 2])
print t2.shape      # [3, 2]

# View (zero-copy)
t3 = t2.view([2, 2], [2, 1], 0)  # view na sub-tenzor

# Maticové násobení
a = tensor.from_values([1, 2, 3, 4], [2, 2])
b = tensor.from_values([5, 6, 7, 8], [2, 2])
c = a.matmul(b.data, [2, 2])       # používá float_matmul kernel

# Součet
total = t.sum()                     # používá float_sum kernel
```

### Koncepty Tensoru

- **data** — sdílený `FloatArray` (mutable).
- **shape** — rozměry (např. `[2, 3, 4]`).
- **strides** — kroky pro každou dimenzi.
- **offset** — počáteční pozice v datech.
- **view** — zero-copy pohled na jiný tenzor (sdílí data, jiné shape/strides/offset).

Změna dat přes view je okamžitě viditelná ve všech ostatních views.

## Plugin ABI

LSL podporuje dvě plugin hranice: procesní (JSON přes nový `exec`) a omezenou
fork-isolated (ET_DYN).

### Procesní plugin ABI (doporučeno)

Plugin je samostatný executable, komunikace přes JSON:

```lsl
load plugin

result = plugin.request("/opt/my-plugin", "embed", {"text": "hello"})
print result   # {"vector": [1.0, 2.0, 3.0]} (Dictionary)
```

Formát požadavku (argv):

```json
{"abi":1,"operation":"embed","payload":{"text":"hello"}}
```

Úspěšná odpověď (stdout):

```json
{"abi":1,"ok":true,"value":{"vector":[1,2,3]}}
```

Chyba:

```json
{"abi":1,"ok":false,"error":"model unavailable"}
```

**Výhody**: izolace, jednoduchý ownership, nezávislost na architektuře.
**Nevýhody**: latence procesního startu, serializace JSON.

### ET_DYN plugin ABI (pokročilé)

Pro důvěryhodné, self-contained CPU kernely:

```lsl
load native

# Načtení knihovny
lib = native.open("./kernel.so")

# Vyhledání symbolu
func = native.symbol(lib, "compute")

# Zavolání (max 6 Int argumentů, vrací Int)
result = native.call(func, [19, 23])

# Uvolnění
call native.close(lib)
```

Omezení ABI v1:

- Image musí být position-independent, bez relocations, external symbols,
  libc a constructors.
- `st_value` musí odpovídat file mapping offsetu.
- Vstup i výstup: pouze Int64.
- Loader nepředává LSL heap pointery.
- Max 6 argumentů.

```lsl
# Příklad: vytvoření ET_DYN image v čistém LSL
code = ByteArray()
# ... zapsání strojových instrukcí (return a + b) ...
call writebytes("kernel.so", code)

lib = native.open("./kernel.so")
add = native.symbol(lib, "add")
print native.call(add, [40, 2])  # 42
call native.close(lib)
```

## Pravidla pro výkonný LSL kód

### 1. Int, ne Float (ve smyčkách)

```lsl
# ŠPATNĚ
for i in rang(1000000):
    x = Float(i) * 0.001    # alokuje Float objekt
end

# SPRÁVNĚ
for i in rang(1000000):
    x = i * 1000             # celočíselný scale, žádný Float
end
```

### 2. Typované pole, ne List (pro numeriku)

```lsl
# ŠPATNĚ
values = []
for i in rang(1000000):
    values.append(i)          # 1M heap objektů
end

# SPRÁVNĚ
values = IntArray()
for i in rang(1000000):
    values.append(i)          # 1M raw Int64
end
```

### 3. Bulk kernel, ne element smyčka

```lsl
# ŠPATNĚ
total = 0.0
for i in rang(len(data)):
    total = total + Float(data[i])
end

# SPRÁVNĚ
total = float_sum(data)
```

### 4. Měřte s monotonic()

```lsl
load time

start = time.perf_counter()
# ... měřený kód ...
elapsed = time.perf_counter() - start
printl "Trvalo: {elapsed} s"
```

### 5. Předkompilujte pro opakované spuštění

```bash
# Jednorázový compile
./lsl compile program.lsl program

# Opakované spuštění
./program arg1 arg2
```

### 6. Pořadí argumentů

Nejisté pořadí vedlejších efektů: nepředávejte více I/O operací v jednom
volání. Nejprve je přiřaďte:

```lsl
# ŠPATNĚ — pořadí get_x() a get_y() není definováno
result = compute(get_x(), get_y())

# SPRÁVNĚ
x = get_x()
y = get_y()
result = compute(x, y)
```

## Vlákna

`thread_spawn(function)` spustí funkci bez parametrů jako worker se sdílenou
pamětí a vrátí Int tid (`-1` při vyčerpání 127 slotů nebo selhání mmap 8 MiB
zásobníku); `thread_join(tid)` počká na jeho konec (vrací `0`, `126` pro
neznámý tid). Počet workerů dimenzujte podle `cpu_count()` (počet CPU v affinity masce procesu). Sdílená data předávejte přes globální proměnné a synchronizujte
je `atomic_add`/`atomic_xchg`/`atomic_cas` nad `IntArray` sloty a
`atomic_pause()` ve spin smyčkách.

```lsl
# lsl: unchecked-intarray
partial = IntArray()
partial.append(0)
partial.append(0)

function half0():
    acc = 0
    i = 0
    while i < 5000000:
        acc += i % 7
        i += 1
    end
    partial[0] = acc
    return None
end

function half1():
    acc = 0
    i = 5000000
    while i < 10000000:
        acc += i % 7
        i += 1
    end
    partial[1] = acc
    return None
end

a = thread_spawn(half0)
b = thread_spawn(half1)
call thread_join(a)
call thread_join(b)
print partial[0] + partial[1]
```

Pro využití všech jader spusťte `cpu_count()` workerů a nechte je brát kusy
práce z atomického čítače:

```lsl
# lsl: unchecked-intarray
chunks = 64
next_chunk = IntArray()
next_chunk.append(0)
partial = IntArray()
i = 0
while i < chunks:
    partial.append(0)
    i += 1
end

function worker():
    while True:
        c = atomic_add(next_chunk, 0, 1)
        if c >= chunks:
            return None
        end
        acc = 0
        j = c * 2000000
        stop = j + 2000000
        while j < stop:
            acc += (j * 7) % 13
            j += 1
        end
        partial[c] = acc
    end
    return None
end

n = cpu_count()
tids = IntArray()
k = 0
while k < n:
    tids.append(thread_spawn(worker))
    k += 1
end
k = 0
while k < n:
    call thread_join(tids[k])
    k += 1
end
```

Na 12jádrovém stroji běží tento pool na ~1000 % CPU (`time`: 0,33 s user,
0,033 s real); pod `taskset -c 0-3` `cpu_count()` vrátí 4 a pool se
automaticky zmenší.

Allokátor je serializovaný futex mutexem aktivovaným prvním `thread_spawn`
(jednovláknové programy neplatí nic), takže alokačně těžké workery se o zámek
dělí — dělte práci tak, aby vlákna počítala nad `IntArray`/`FloatArray` bez
alokací v hot path. `gc()` smí volat jen hlavní vlákno; zastaví workery přes
`SIGUSR1`, projde jejich zásobníky a po sweepu je probudí.

## Převody Float a paměť

`String(Float)` v 0.6.5 hledá nejkratší round-trip zápis pomocí stackového
kandidáta a porovnání raw IEEE-754 bitů. Korekční ani zkracovací smyčka proto
nevytváří pomocný heapový String a Float pro každý pokus. Veřejný
`Float(String)` při čtení číslic mutuje jeden privátní akumulátor.

Dlouhá smyčka s opakovaným formátováním vytváří výsledné Stringy. Od 0.8.4
ji pokrývá stejný automatický byte-pressure GC jako ostatní alokující smyčky;
dřívější podmínka 256 převodů a 4 096 nových adres již neplatí.
Pro numerické hot pathy přesto dál preferujte
`FloatArray` bulk kernely; optimalizace převodu není náhradou za neboxovaná
pole.

## Benchmarking

Měření provádějte sériově na stejném stroji:

```lsl
load time

function benchmark(name, iterations, func):
    start = time.perf_counter()
    for i in rang(iterations):
        call func()
    end
    elapsed = time.perf_counter() - start
    printl "{name}: {elapsed} s ({elapsed / Float(iterations) * 1000000} µs/iter)"
end

function test_operation():
    # ... testovaná operace ...
end

call benchmark("operace", 10000, test_operation)
```

Pro přesné výsledky:

- Měřte medián alespoň 5 běhů.
- Zaznamenejte: compile wall time, peak RSS, velikost ELF, runtime wall time,
  peak RSS, vstupní rozměr a checksum/stdout.
- Oddělte compile cold start od runtime.

## CUDA backend

LSL 0.7.7 poskytuje jednorázové FloatArray kernely s automatickým CPU
fallbackem i persistentní `cuda.session()`. Session drží CUDA kontext,
uchovává buffery na GPU a další příkazy předává přímo přes Unix socket.
`Tensor.to_device(session)` vrací DeviceTensor pro výpočty bez opakovaného
nahrávání mezivýsledků.

Podporované dense Float64 operace jsou sum, dot, AXPY, matmul, elementwise
add/subtract/multiply/divide, scale, fill, ReLU a transpozice.
Compiler a host ELF stále nepoužívají libc ani CUDA knihovny; NVIDIA runtime
vlastní volitelný izolovaný worker.

```lsl
load cuda
load tensor

call cuda.configure("cuda/lsl-cuda-worker", "required", 0)
s = cuda.session()
host = tensor.from_values([1, 2, 3, 4], [2, 2])
a = host.to_device(s)
b = a.matmul(a)
print b.sum()
call s.close()
```

Na GTX 1650 byl medián pěti výpočtů 512×512 dne 5. 9. 2026: CPU 0,04325 s,
persistentní CUDA včetně downloadu 0,02228 s (1,94×). Jednorázová inicializace
a dva uploady trvaly 0,319 s. Pro malé jednorázové vstupy obvykle vyhraje CPU;
opakované GPU operace amortizují inicializaci.

Konfigurace, životnost prostředků, CPU fallback, číselné tolerance, přesné
limity a reprodukovatelný benchmark jsou v [CUDA a GPU tenzory](15-cuda.md).

## Kam dál

- [12 — Interní architektura compileru](12-compiler-internals.md): pipeline, self-host, ABI, vývojářský cyklus
