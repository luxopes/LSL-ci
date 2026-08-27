# 6. Moduly, standardní knihovny a balíčky

Tato kapitola navazuje na základy modulů z kapitoly 3. Vysvětluje
podrobně, jak modulový systém funguje uvnitř, jaké standardní knihovny
máte k dispozici a jak instalovat knihovny třetích stran.

## Proč moduly a standardní knihovny

Když píšete program, nechcete pokaždé znovu vymýšlet, jak naparsovat
JSON, poslat HTTP požadavek nebo spustit externí program. Standardní
knihovny (stdlib) jsou předpřipravené moduly, které tyto úlohy řeší za
vás — stačí je importovat a používat.

## Modulový systém — opakování a rozšíření

### Jak moduly fungují

Každý `.lsl` soubor je samostatný modul. Když napíšete `load jmeno`,
compiler udělá toto:

1. Vyhledá soubor `jmeno.lsl` podle pravidel popsaných níže.
2. Přeloží ho jako samostatnou jednotku.
3. Jeho veřejné symboly (proměnné, funkce, třídy) zpřístupní pod
   prefixem `jmeno.`.

Důležité: importy jsou **statické** — vše se vyřeší při překladu.
Za běhu se žádný modulový loader nespouští, žádné soubory se nenačítají.
Výsledný ELF už obsahuje všechen potřebný kód.

Celý modul lze pojmenovat kratším aliasem:

```lsl
load tensor as t

matrix = t.from_values([1, 2, 3, 4], [2, 2])
```

Alias mění pouze jméno viditelné v importujícím souboru; interní namespace
modulu zůstává deterministický.

### Pravidla vyhledávání

Při `load jmeno` se soubor hledá v tomto pořadí:

1. **Relativně k importujícímu souboru** — např. `load util.text` hledá
   `util/text.lsl` vedle aktuálního souboru.
2. **Compiler interní cesty** — moduly zabudované přímo v compileru.
3. **System/built-in stdlib** — `<prefix>/lib/lsl/stdlib/jmeno.lsl`.
4. **Uživatelské knihovny** — `~/.local/lib/lsl/stdlib/jmeno.lsl`.

Built-in moduly **nelze** zastínit uživatelskou kopií — přednost má vždy
system stdlib.

### Determinismus a prefixy

Modulové symboly dostávají deterministický namespace prefix založený na
cestě a jménu modulu. To zaručuje reprodukovatelnost napříč různými
instalacemi.

## Seznam standardních modulů

### Vestavěný modul lux

```lsl
load lux

print lux.version    # verze LSL (např. "0.6")
print lux.name       # "Lux Simple Lang"
print lux.l([1, 2])  # "List" — alias pro type()
```

### json — JSON codec

```lsl
load json

# Enkódování
data = {"name": "Ada", "values": [1, 2, 3]}
text = json.encode(data)        # '{"name":"Ada","values":[1,2,3]}'
pretty = json.pretty(data)      # totéž + newline

# Dekódování
parsed = json.decode('{"key": "value"}')
print parsed["key"]             # "value"

# Chyba
try:
    json.decode("{invalid")
else:
    print "JSON chyba:", last_error()   # JsonError
end
```

### lconf — dependency manifest

```lsl
load lconf

text = "apt: curl, git\nlux: myapp\nlsl: textkit\n"
deps = lconf.decode(text)
# {"apt": ["curl", "git"], "lux": ["myapp"], "lsl": ["textkit"]}

print lconf.encode(deps)
# apt: curl
# apt: git
# lux: myapp
# lsl: textkit
```

### http — HTTP(S) klient

```lsl
load http

# GET požadavek
response = http.get("https://api.example.com/data")
print response["status"]   # HTTP status kód
print response["ok"]       # Bool: 200–299
print response["text"]     # tělo odpovědi

# POST požadavek
body = {"key": "value"}
headers = {"Content-Type": "application/json"}
response = http.post("https://api.example.com/submit", body, headers, 30)
```

HTTP(S) transport používá systémový `/usr/bin/curl` spuštěný přes přímé
`execve` s odděleným argv — shell ani interpolace se nespouští.

### env — proměnné prostředí

```lsl
load env

token = env.get("API_TOKEN", "default-token")
print token

if env.has("DEBUG"):
    print "Debug mód"
end

secret = env.require("SECRET_KEY")  # chyba pokud není nastaveno
```

Důležité: v čistém `lsl config` režimu je modul `env` zakázán, protože
by narušil reprodukovatelnost.

### time — čas a měření

```lsl
load time

# Wall clock
print time.time()            # Unix timestamp (Float)
print time.now()             # alias pro time()

# Monotónní měření (pro intervaly a timeouty)
start = time.monotonic()
call time.sleep(0.1)
elapsed = time.monotonic() - start
print elapsed                # ~0.1 sekundy

# High-resolution
start = time.perf_counter()
# ... mereny kod ...
elapsed = time.perf_counter() - start
```

Pro měření intervalů používejte `monotonic`/`perf_counter`, ne `time`/`now`
— wall clock může správce systému změnit.

### os — spouštění programů

```lsl
load os

# Spuštění s výpisem
status = os.run("ls -al")
print "exit status:", status

# Zachycení výstupu
output = os.capture("uname -a")
print output.strip()

# Strukturovaný výsledek
result = os.capture_result(["echo", "hello"])
print result["stdout"]   # "hello\n"
print result["status"]   # 0
print result["ok"]       # True

# Kontrola úspěchu
try:
    text = os.check("cat neexistujici.txt")
else:
    print "Soubor nelze přečíst"
end

# PATH lookup
path = os.which("python3")
if path != None:
    print "Nalezen:", path
end
```

Command musí být `String` (tokenizuje se) nebo `List[String]` (přímé argv).
Shell (`/bin/sh -c`) se nespouští — žádné pipes, redirection, expanze.

### process — rozšířené procesní API

```lsl
load process

# Zachycení stdout i stderr
result = process.capture_result("/usr/bin/tool", ["--input", "data"])
print result["stdout"]
print result["stderr"]
if not result["ok"]:
    Error(ProcessError: result["stderr"])
end

# Vstup do procesu
result = process.capture_input_result("/usr/bin/sort", [], "c\na\nb\n")
print result["stdout"]

# Streamování výstupu
function on_chunk(chunk):
    print "chunk:", len(chunk), "bytů"
end
result = process.capture_input_stream_result("/usr/bin/tool", [], "request\n", on_chunk)
```

### system — správa systému (LuxOS/Debian)

```lsl
load system

# Balíčky
call system.refresh()                              # apt update
backend = system.install("git")                    # "lux" nebo "apt"
call system.remove("old-package")

# Služby
call system.enable_service("nginx.service")
call system.restart_service("nginx.service")
active = system.service_active("nginx.service")

# Identita
call system.set_hostname("myserver")
call system.set_timezone("Europe/Prague")

# Uživatelé a skupiny
call system.ensure_group("developers")
call system.ensure_user("ada", "/bin/bash", ["developers"])

# Atomické soubory
call system.ensure_directory("/etc/myapp", "0750")
call system.write_file("/etc/myapp/config", "port=8080\n", "0640")
```

Modul `system` je **imperativní** — funkce skutečně mění systém. Vyžaduje
odpovídající oprávnění.

### display, gfx, ui — GUI

Viz [09 — GUI programování](09-gui-programming.md).

### tensor a cuda — CPU tenzory s volitelnou CUDA akcelerací

```lsl
load tensor

# Vytvoření tenzoru
t = tensor.from_values([1, 2, 3, 4, 5, 6], [2, 3])
print t.shape     # [2, 3]
print t.get([0, 0])  # 1.0
print t.get([1, 2])  # 6.0

# Maticové násobení
a = tensor.from_values([1, 2, 3, 4], [2, 2])
b = tensor.from_values([5, 6, 7, 8], [2, 2])
c = a.matmul(b.data, [2, 2])
```

Tensor `sum`, `dot`, `axpy` a `matmul` automaticky použijí CUDA worker,
pokud `cuda.probe()` ověří skutečný NVIDIA kernel a práce překročí
`LSL_CUDA_MIN_ELEMENTS` (výchozí 400 000 000 pracovních jednotek).
Bez workeru běží stejné API přes nativní CPU FloatArray kernely.

```text
LSL_CUDA_WORKER=./cuda/lsl-cuda-worker
LSL_CUDA=auto                 # auto | required | off
LSL_CUDA_DEVICE=0
LSL_CUDA_MIN_ELEMENTS=400000000
```

```lsl
load cuda as gpu

print gpu.probe(), gpu.devices(), gpu.backend()
```

### native — nativní knihovny (omezené ABI)

```lsl
load native

lib = native.open("./kernel.so")
func = native.symbol(lib, "compute")
result = native.call(func, [19, 23])
call native.close(lib)
```

Podporuje self-contained Linux x86\_64 ET\_DYN s Int64 vstupem a výstupem.
Obecné relocatable/libc pluginy nejsou součástí ABI v1. Viz
[11 — Výkon a optimalizace](11-performance-and-optimization.md).

### plugin — procesní plugin ABI

```lsl
load plugin

result = plugin.request("/opt/my-plugin", "embed", {"text": "hello"})
# komunikuje přes JSON stdin/stdout s izolovaným procesem
```

### ai — AI orchestrace

Viz [10 — AI aplikace](10-ai-applications.md).

### configure — konfigurační evaluator

Viz [08 — Konfigurační systém](08-configuration-system.md).

### Další moduly

- `fd` — raw descriptor/socket I/O (používáno interně jinými moduly).
- `input` — evdev klávesnice (pro framebuffer GUI).
- `css` — deklarativní styly pro GUI.
- `config` — configurační primitiva.

## Instalace uživatelských knihoven

LSL podporuje správu jednosouborových zdrojových knihoven:

```text
lsl install textkit
lsl update textkit
lsl install --config libraries.conf
```

Knihovny se instalují do `~/.local/lib/lsl/stdlib/`.

### Postup instalace

1. Stáhne se zdrojový soubor a SHA-256 sidecar z registru.
2. Ověří se hash přes `sha256sum`.
3. Provede se zkušební překlad (`lsl compile`).
4. Atomickou `mv` se nahradí cílový soubor.

### Konfigurační soubor

```text
# libraries.conf
textkit
statkit
jsonkit
```

Jeden název na řádek; podporovány komentáře `#` a prázdné řádky.

### Vlastní registr

```text
LSL_REGISTRY=https://example.org/lsl lsl install mylib
```

Vzdálená URL musí používat HTTPS.

### Bezpečnost

- Uživatelské moduly **nemohou** zastínit built-in moduly.
- Registr je zatím nepodepsaný — HTTPS + hash ověří integritu, ale
  neprokazuje identitu vydavatele.
- Jméno modulu smí obsahovat jen `[a-z][a-z0-9_]{0,63}` — nelze uniknout
  z cílového adresáře.

## Kam dál

- [07 — Soubory, I/O a procesy](07-files-io-and-processes.md): podrobné API pro práci se soubory a procesy
- [08 — Konfigurační systém](08-configuration-system.md): deklarativní konfigurace
- [09 — GUI programování](09-gui-programming.md): tvorba grafických aplikací
- [10 — AI aplikace](10-ai-applications.md): AI orchestrace v LSL
