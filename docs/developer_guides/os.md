# Knihovna os

`load os`

Bezpečné spouštění Linuxových programů: přímé hledání v PATH a `execve`
s argv seznamem — nikdy `/bin/sh -c`, žádný shell, žádná expanze a roury.
Argumenty s mezerami, uvozovkami nebo speciálními znaky jsou proto
bezpečné.

## Funkce

### os.run(command) → Int

Spustí příkaz a vrátí exit status. `command` je String (tokenizovaný bez
shellu) nebo argv List.

### os.system(command) → Int

Alias `os.run`.

### os.capture(command) → String

Zachytí stdout. Výsledný status a stderr jsou dostupné přes
`capture_status()` a `capture_stderr()`.

### os.capture_result(command) → Dictionary

```lsl
{"stdout": String, "stderr": String, "status": Int, "ok": Bool}
```

### os.check(command) → String

Jako `capture`, ale při nenulovém statusu vyhodí `OSCommandError`.

### os.run_argv(program, arguments) / os.capture_argv / os.capture_argv_clean

Přímé varianty s argv seznamem (bez tokenizace Stringu).

### os.which(name)

Najde spustitelný soubor v PATH; `None`, pokud chybí.
`os.which_trusted(name)` hledá jen v důvěryhodných systémových adresářích.

### os.executable(name)

Zkontrolovaná cesta ke spustitelnému souboru.

## Příklad

```lsl
load os

status = os.run("ls -al")
print "exit status:", status

result = os.capture_result(["echo", "hello"])
print result["stdout"].strip()   # "hello"

print os.check("uname -a")
```

## Chyby

- `OSCommandError` — nenulový status v `check`/`os.check`.
- `OSError` — neplatné argumenty.

## Související stránky

- `lsl man process` — strukturované zachytávání se stdin a streamem
- `lsl man env` — proměnné prostředí
- `lsl man system` — správa balíčků
