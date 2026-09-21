# Modul `os`

`system(command)` je dostupný i jako vestavěná funkce bez `load os`.
Používá přesně `os.run`: přijme String nebo argv List, vyhledá program v
PATH a vrátí exit status. Nevkládá shell; `;`, `|`, `$()` ani wildcardy
nespouštějí další příkazy. Pro bezpečné předání argumentů preferujte List.

Standardní modul `os` spouští Linux programy přes existující pure-LSL
`fork`/`execve`/`wait4` runtime. Nespouští `/bin/sh -c`.

```lsl
load os

status = os.run("ls -al")
print "status", status

output = os.capture("echo 'hello world'")
print output.strip()
```

Command musí být LSL `String` nebo explicitní `List[String]`. Správný zápis je
`os.run("ls -al")`; nequoted `os.run(ls -al)` by podle běžné LSL gramatiky
znamenal aritmetické `ls - al` nad dvěma proměnnými.

Pro programově vytvářené argumenty preferujte List, aby nebylo potřeba quoting:

```lsl
path = "directory with spaces"
status = os.run(["ls", "-al", path])
```

## API

- `os.run(command)` — zdědí stdin/stdout/stderr, počká a vrátí exit status;
- `os.system(command)` — alias `os.run`;
- `os.capture(command)` — vrátí stdout a status zpřístupní přes
  `capture_status()`;
- `os.capture_result(command)` — vrátí Dictionary
  `{stdout, stderr, status, ok}`;
- `os.check(command)` — vrátí stdout, při nenulovém statusu vyvolá
  `OSCommandError`;
- `os.run_argv(program, arguments)` a `os.capture_argv(...)` — explicitní
  dvouargumentové varianty;
- `os.which(name)` — první existující cesta v `PATH`, nebo `None`.

Jednořetězcový tokenizer podporuje whitespace, jednoduché/dvojité uvozovky a
backslash. Záměrně nepodporuje shell expanzi, `$VARIABLE`, `*`, pipes (`|`),
redirection (`>`, `<`), `&&`, subshelly ani command substitution. Tyto znaky se
předají jako obyčejné argumenty. Díky tomu hodnoty nevytvářejí shell injection.

Jméno bez `/` se hledá v `PATH`; chybějící `PATH` používá
`/usr/local/bin:/usr/bin:/bin`. Nenalezený executable skončí deterministickým
statusem `127`. `os.which` ověřuje existenci, nikoli executable permission;
konečné rozhodnutí dělá `execve`.

Pro složitější datový protokol nebo vstup použijte modul `process`, zejména
`capture_input_result`. Pro LuxOS/Debian package operace použijte vyšší modul
[`system`](system.md). `os` je ambientní process capability a v čistém
`lsl config` režimu je zakázán.
