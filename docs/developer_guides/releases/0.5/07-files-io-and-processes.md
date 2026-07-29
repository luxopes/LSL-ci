# 7. Soubory, I/O a procesy

Tato kapitola vysvětluje, jak LSL komunikuje s okolním světem: čtení
a zápis souborů, výpis na obrazovku, čtení z klávesnice, spouštění
externích programů a posílání HTTP požadavků.

## Proč je to důležité

Program, který nekomunikuje s okolím, je k ničemu — nemůže načíst data,
zobrazit výsledky ani spolupracovat s jinými programy. LSL k tomu
poskytuje bezpečné API: na rozdíl od shellových jazyků nikdy nevolá
`/bin/sh -c`, takže nemůže dojít k shell injection útoku. Každý externí
program se spouští přes přímé `execve` s oddělenými argumenty.

## Souborový systém

### Základní operace

```lsl
# Aktuální adresář
current = cwd()          # vrátí absolutní cestu
call chdir("/tmp")        # změní pracovní adresář

# Vytvoření a mazání
call mkdir("muj_adresar")
call remove_path("stary_soubor.txt")
call remove_path("prazdny_adresar")

# Existence
if exists("config.json"):
    print "Konfigurace nalezena"
end
```

### Textové soubory

LSL poskytuje jednoduché built-in funkce pro UTF-8 textové soubory:

```lsl
# Zápis (přepíše existující soubor)
writefile("note.txt", "První řádek\nDruhý řádek\n")

# Čtení
text = readfile("note.txt")
print text

# Připojení
appendfile("note.txt", "Třetí řádek\n")
```

Funkce vrací `None` při úspěchu, při chybě vyvolají runtime výjimku.

### Binární soubory

Pro binární data použijte `ByteArray` a built-in funkce `readbytes`/`writebytes`:

```lsl
# Čtení binárního souboru
data = readbytes("image.png")
print "Velikost:", len(data), "bytů"

# Prohlížení hlavičky
print "Prvních 8 bytů:"
for i in rang(8):
    print data[i]
end

# Zápis binárního souboru
buf = ByteArray()
buf.append(0x89)   # PNG signature byte 1
buf.append(0x50)   # P
buf.append(0x4E)   # N
buf.append(0x47)   # G
# ... další byty ...
call writebytes("output.png", buf)
```

### Práce s cestami

```lsl
# Skládání cest
dir = "/home/user"
file = "config.json"
path = dir + "/" + file     # "/home/user/config.json"

# Kontrola
if exists(path):
    content = readfile(path)
end
```

LSL nemá specializované funkce pro manipulaci s cestami (`dirname`,
`basename`, `join`). Použijte stringové operace nebo si napište vlastní
pomocné funkce.

## Standardní vstup a výstup

### Čtení ze stdin

```lsl
# Řádek s výzvou
jmeno = input "Zadej jméno: "

# Obecné čtení
jmeno = input("Zadej jméno: ")
```

`input` přečte jeden řádek a odstraní koncové LF/CRLF.

### Zápis na stdout a stderr

```lsl
print "Jdu na stdout"
# Zápis na stderr — není přímo podporován.
# Lze emulovat přes proces:
call os.run(["echo", "chyba", ">&2"])  # nesprávně, os nepoužívá shell
# Pro stderr použijte modul fd nebo nativní runtime:
```

### Interaktivní režim vs pipe

LSL rozlišuje interaktivní terminál (TTY) a pipe:

- **TTY**: zobrazí se banner a `>>>` prompt, vstup končí řádkem `exit`
  nebo Ctrl-D.
- **Pipe/heredoc**: vstup končí EOF, prompt se nevypisuje.

```text
# Pipe — bez promptu
printf 'print 6 * 7\n' | ./lsl

# Heredoc — bez promptu, bez exit
./lsl <<'EOF'
load time
print time.time()
EOF
```

## Spouštění externích programů

LSL poskytuje **bezpečné** API pro spouštění programů — vždy přes přímé
`execve` s odděleným argv, **nikdy** přes `/bin/sh -c`. Tím se eliminuje
shell injection.

### Modul os

```lsl
load os
```

#### os.run(command) — spustí a počká

```lsl
status = os.run("ls -al")
print "Exit status:", status

# Ekvivalentní:
status = os.run(["ls", "-al"])
```

- Zdědí stdin/stdout/stderr.
- Vrátí exit status (Int).
- Command je String (tokenizuje se: mezery, uvozovky, backslash) nebo
  `List[String]` (přímé argv).

#### os.capture(command) — zachytí stdout

```lsl
output = os.capture("uname -a")
print output.strip()

# Explicitní argv:
output = os.capture(["uname", "-a"])
```

Vrátí `String` — kompletní stdout. Status je dostupný přes `capture_status()`.

#### os.capture_result(command) — kompletní výsledek

```lsl
result = os.capture_result(["ls", "/neexistujici"])
print result["stdout"]   # ""
print result["stderr"]   # chybová zpráva
print result["status"]   # 2
print result["ok"]       # False
```

Vrací Dictionary `{stdout, stderr, status, ok}`.

#### os.check(command) — kontrola úspěchu

```lsl
try:
    output = os.check("cat /etc/hostname")
    print output.strip()
else:
    print "Chyba při čtení:", last_error()
end
```

Vrátí stdout, při nenulovém statusu vyvolá `OSCommandError`.

#### os.which(name) — PATH lookup

```lsl
python = os.which("python3")
if python != None:
    print "Python nalezen:", python
else:
    print "Python není v PATH"
end
```

#### Bezpečný tokenizer

Jednořetězcový tokenizer podporuje whitespace, jednoduché a dvojité
uvozovky a backslash escape. **Nepodporuje** shell expanzi:

- `$VAR`, `${VAR}` — nepoužívá se
- `*`, `?` — nepoužívá se (žádný glob)
- `|`, `>`, `<`, `>>` — nepoužívá se (žádné pipes)
- `&&`, `||` — nepoužívá se
- `$(...)`, `` `...` `` — nepoužívá se

```lsl
# BEZPEČNÉ — hodnoty se nikdy neinterpretují shellem
user_input = "soubor s mezerami.txt"
status = os.run(["cat", user_input])

# BEZPEČNÉ — i s uvozovkami v tokenizeru
status = os.run("cat 'soubor s mezerami.txt'")
```

### Modul process

Pro pokročilejší procesní operace použijte `process`:

```lsl
load process

# Zachycení s rozlišením stdout/stderr
result = process.capture_result("/usr/bin/git", ["status"])
if not result["ok"]:
    Error(ProcessError: result["stderr"])
end
print result["stdout"]

# Odeslání vstupu do procesu
result = process.capture_input_result("/usr/bin/sort", [], "c\na\nb\n")
print result["stdout"]   # "a\nb\nc\n"

# Streamování výstupu za běhu
function handle_chunk(chunk):
    print "Přijato:", len(chunk), "bytů"
end
result = process.capture_stream("/usr/bin/curl", [url], handle_chunk)
```

### Vestavěné run()

Pro jednoduché případy lze použít vestavěnou funkci `run()`:

```lsl
status = run("/usr/bin/echo", ["hello", "world"])
print status
```

Funkce `capture(program, arguments)` zachytí stdout jako String.

## Práce se síťí (HTTP/HTTPS)

```lsl
load http

# GET
response = http.get("https://api.github.com/repos/torvalds/linux")
if response["ok"]:
    data = json.decode(response["text"])
    print data["description"]
else:
    print "HTTP chyba:", response["status"]
end

# POST s JSON
body = {"prompt": "Hello", "max_tokens": 100}
headers = {"Content-Type": "application/json", "Authorization": "Bearer " + token}
response = http.post("https://api.openai.com/v1/completions", body, headers, 30)
print response["text"]
```

HTTP transport používá systémový `/usr/bin/curl` přes `execve` — shell se
nespouští. Parametry se předávají jako oddělené argv prvky.

## Proměnné prostředí

```lsl
load env

# Čtení s výchozí hodnotou
home = env.get("HOME", "/tmp")
debug = env.get("DEBUG", "0")

# Kontrola existence
if env.has("API_KEY"):
    print "API klíč nastaven"
end

# Povinná proměnná
token = env.require("SECRET_TOKEN")
```

Důležité: `env` je ambientní vstup. V konfiguračním režimu (`lsl config`)
je zakázán, protože by narušil reprodukovatelnost.

## Vzory a doporučení

### Bezpečné čtení souboru

```lsl
try:
    text = readfile(path)
else:
    print "Nelze číst:", path, "-", last_error()
    text = ""
end
```

### Atomický zápis

```lsl
function atomic_write(path, content):
    tmp = "/tmp/" + path.replace("/", "_") + ".tmp"
    writefile(tmp, content)
    call remove_path(path)
    call writefile(path, readfile(tmp))  # zjednodušená atomická náhrada
    call remove_path(tmp)
end
```

Pro produkční použití preferujte `system.write_file()`, které dělá
skutečnou atomickou `mv`.

### Zpracování adresáře

```lsl
# Procházení výstupu ls
result = os.capture_result(["ls", "/some/dir"])
if result["ok"]:
    for line in result["stdout"].split("\n"):
        if line != "":
            print "Soubor:", line
        end
    end
end
```

### Dávkové zpracování

```lsl
files = ["a.txt", "b.txt", "c.txt"]
for path in files:
    if exists(path):
        text = readfile(path)
        print path, ":", len(text), "znaků"
    else:
        print path, ": NENALEZEN"
    end
end
```

### Pipe-like skládání

```lsl
# Ekvivalent: ls | grep .lsl | wc -l
ls_output = os.capture(["ls"])
lines = ls_output.split("\n")
count = 0
for line in lines:
    if ".lsl" in line:
        count += 1
    end
end
print "Počet .lsl souborů:", count
```

## Omezení

- **Žádné pipes v rámci jednoho volání** — `os` a `process` záměrně
  nepodporují shell pipes. Pro skládání spusťte procesy postupně a ručně
  propojte jejich výstupy.
- **Žádná redirection** — `>`, `<`, `>>` nejsou podporovány.
- **Žádné subshelly** — `$(...)` a `` `...` `` nejsou podporovány.
- **Žádná expanze proměnných** — `$VAR` shell neexpanduje.

Tato omezení jsou **záměrná** — eliminují celou třídu shell injection útoků.

## Kam dál

- [08 — Konfigurační systém](08-configuration-system.md): deklarativní konfigurace
- [09 — GUI programování](09-gui-programming.md): grafické aplikace
- [10 — AI aplikace](10-ai-applications.md): AI orchestrace a HTTP
