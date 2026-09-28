# 5. Zpracování chyb

Každý program se může dostat do situace, kdy něco selže — soubor neexistuje,
uživatel zadal nesmysl, síťový požadavek vypršel. Když program na takovou
situaci není připravený, spadne (vypíše chybu a ukončí se). Tato kapitola
vysvětluje, jak chyby **zachytit** a **zpracovat**, aby váš program zůstal
stabilní a dal uživateli smysluplnou odezvu.

## Co je to chyba (error)

Když se v LSL programu stane něco neočekávaného — třeba dělení nulou,
otevření neexistujícího souboru nebo nesprávný typ — LSL **vyvolá chybu**
(throw error). Chyba přeruší normální tok programu a začne „probublávat"
nahoru, dokud ji někdo nezachytí.

Když chybu nic nezachytí, program vypíše chybovou zprávu na stderr
a ukončí se s nenulovým exit kódem.

## Přehled mechanismů

LSL nabízí pět nástrojů pro práci s chybami:

| Nástroj | Syntaxe | Kdy použít |
|---|---|---|
| `safe` | `safe: ... end` | Když chybu chcete ignorovat, program ať jede dál |
| `try/else` | `try: ... else: ... end` | Když při chybě chcete provést záložní plán |
| `Error()` | `Error(Typ: "zpráva")` | Když chcete sami vyvolat chybu |
| `check()` | `check(podmínka, "zpráva")` | Když chcete ověřit podmínku a při nesplnění selhat |
| `last_error()` | `last_error()` | Když chcete zjistit, jaká chyba nastala |

## safe — bezpečný blok

`safe` obalí kus kódu. Když uvnitř vznikne chyba, zbytek bloku se přeskočí,
ale program **pokračuje** dál za `end` — jako by se nic nestalo.

### Kdy to použít

Od 0.8.2 funguje také:

```lsl
safe:
    call nonexist()
end
print last_error()  # NameError s místem chyby
print "Program pokračuje"
```

Stejným způsobem lze zachytit neznámou proměnnou/metodu, chybný počet
argumentů a podporované statické typové chyby. Chyby z volaných funkcí
se předají volajícímu. `try/else` používá stejný mechanismus. Bez ochranného
bloku na nejvyšší úrovni compiler dál vypíše statickou chybu.

Nejde o potlačení všech možných selhání: parser, chybějící importy,
nepodporovaná syntaxe, bezpečnostní kontroly compileru, fatální nedostatek
paměti, signály operačního systému ani výslovné `exit()` se nezachytávají.
`safe` rovněž neprovádí rollback souborů nebo rozpracovaných změn dat.
Známá volání zůstávají přímá; úklid zásobníku běží pouze při chybě.

Když operace není kritická — například mazání dočasného souboru, který
třeba už neexistuje. Nebo když zkoušíte načíst soubor, který možná není.

### Jak to funguje

```lsl
print "Začátek"

safe:
    print "Uvnitř safe, začátek"
    x = 10 / 0            # TADY VZNIKNE CHYBA — dělení nulou
    print "Toto se nikdy nevypíše"  # přeskočeno
end

print "Konec — program pokračuje"
```

Výstup:

```
Začátek
Uvnitř safe, začátek
Konec — program pokračuje
```

Co se stalo:

1. Program vstoupil do `safe` bloku.
2. Napsal první zprávu.
3. Při pokusu o `10 / 0` vznikla chyba.
4. LSL **neukončil program**, ale přeskočil na `end` safe bloku.
5. Program pokračuje normálně dál.

**Důležité**: `safe` chybu zcela potlačí. Nevíte, co přesně selhalo,
dokud se nepodíváte přes `last_error()`. Pro operace, kde potřebujete
vědět *proč* to selhalo, použijte raději `try/else`.

### Příklad: načtení konfigurace

```lsl
safe:
    config = readfile("config.json")
end
if last_error() != None:
    print "Konfigurace se nepodařila načíst, používám výchozí hodnoty."
    config = '{"port": 8080}'
end
```

## try/else — pokus se záložním plánem

`try/else` je chytřejší varianta. Když blok `try` uspěje, blok `else`
se **neprovede**. Když `try` selže, provede se `else` jako záložní plán.

### Jak to funguje

```lsl
try:
    print "Primární cesta"
    Error(MujTypChyby: "něco se pokazilo")
    print "Toto se nevypíše"
else:
    print "Záložní cesta — try selhal"
end
```

Výstup:

```
Primární cesta
Záložní cesta — try selhal
```

Pokud by v `try` bloku **nevznikla** chyba, `else` by se přeskočilo.

### try/else vs safe

Hlavní rozdíl:

- `safe`: chybu ignoruje a pokračuje dál. Nevíte, jestli blok proběhl
  celý nebo byl přerušen (dokud nezavoláte `last_error()`).
- `try/else`: dává vám explicitní větev pro případ selhání. `else` se
  provede **jen** když `try` selže.

```lsl
safe:                    try:
    akce()                   akce()
end                      else:
# vždy pokračuje sem         zachranna_akce()
                         end
                         # sem pokračuje v obou případech
```

### Vnořené try/else

```lsl
try:
    print "Zkouším hlavní zdroj"
    data = readfile("/etc/app/config.json")
else:
    try:
        print "Zkouším uživatelskou konfiguraci"
        data = readfile("~/.config/app/config.json")
    else:
        print "Nic nenačteno, používám prázdný objekt"
        data = "{}"
    end
end
```

### Když try uspěje, else se neprovede

Toto je častý zdroj zmatení:

```lsl
try:
    print "Vše OK"
else:
    print "Toto se NEvypíše — try uspěl!"
end
# Výstup: Vše OK (jen jedna řádka)
```

## Error — vlastní chyba

Když váš kód narazí na situaci, která nemá smysl, můžete **sami** vyvolat
chybu:

```lsl
Error(TypeError: "očekáván Int, dostal String")
Error(ValueError: "hodnota musí být kladná")
Error(MojeAplikacniChyba: "databáze není dostupná")
```

Co se stane:

1. Běh programu se přeruší.
2. Chyba začne probublávat směrem nahoru (ven z aktuální funkce, ven z
   volající funkce, ...).
3. První `safe` nebo `try/else`, který ji zachytí, ji zpracuje.
4. Pokud nic, program skončí s chybou.

Syntaxe je `Error(TypChyby: "popis")`. `TypChyby` je vámi zvolené
identifikující jméno. `popis` je text vysvětlující, co se stalo.

### Kdy použít Error

Když nemůžete pokračovat a volající by měl vědět proč:

```lsl
function najdi_uzivatele(jmeno, databaze):
    if jmeno not in databaze:
        Error(UzivatelNenalezen: "uživatel '" + jmeno + "' neexistuje")
    end
    return databaze[jmeno]
end
```

## check — ověření a selhání

`check(podmínka, "zpráva")` je zkratka: když podmínka neplatí, vyvolej
chybu s danou zprávou. Je to častý vzor — „ověř, že je to v pořádku,
jinak se rozbij".

```lsl
# Toto:
check(vek >= 0, "věk nesmí být záporný")

# Je ekvivalentní tomuto:
if vek < 0:
    Error(ValueError: "věk nesmí být záporný")
end
```

### Typické použití

```lsl
function bezpecne_deleni(a, b):
    check(b != 0, "dělení nulou")
    return a / b
end

function vytvor_uzivatele(jmeno, email):
    check(len(jmeno) >= 2, "jméno musí mít alespoň 2 znaky")
    check("@" in email, "neplatný email")
    return {"jmeno": jmeno, "email": email}
end

function nacti_soubor(cesta):
    check(exists(cesta), "soubor neexistuje: " + cesta)
    return readfile(cesta)
end
```

`check` je ideální pro **předpodmínky** — ověření, že funkce dostala
smysluplné argumenty, než s nimi začne pracovat.

## last_error() — co se vlastně stalo?

Po `safe` nebo `try` bloku můžete zjistit, jaká chyba vznikla (pokud
vůbec):

```lsl
safe:
    value = Int("toto není číslo")
end
err = last_error()
if err != None:
    print "Chyba:", err
end
```

`last_error()` vrací:
- Text chybové zprávy (String), pokud chyba nastala.
- `None` před první chybou a po úspěšném dokončení těla `safe` nebo `try`.

Úspěch maže i starší chybu nebo chybu zachycenou uvnitř vnořeného bloku.
Platí to také při odchodu z těla přes `return`, `break` a `continue`.
Při selhání zůstává text dostupný v `else` a po zachycení chyby; stav je
oddělený pro každé vlákno. Pokud v obsluze spouštíte další `safe`/`try`,
uložte si původní text nejprve do proměnné. Samotné čtení `last_error()`
stav nemaže.

### Příklad: logování chyb

```lsl
for soubor in seznam_souboru:
    safe:
        data = readfile(soubor)
        call zpracuj(data)
    end
    if last_error() != None:
        print "CHYBA:", soubor, "—", last_error()
    end
end
```

## Chybové typy ve standardních modulech

Různé moduly používají různé chybové typy — podle toho je můžete
rozlišit:

| Modul | Typ chyby | Význam |
|---|---|---|
| `json` | `JsonError` | Neplatný JSON |
| `os` | `OSCommandError` | Chyba při spuštění příkazu |
| `process` | `ProcessError` | Chyba procesu |
| `system` | `PackageError` | Chyba balíčkování |
| `system` | `SystemError` | Systémová chyba |
| `tensor` | `TensorShapeError` | Neplatný tvar tenzoru |
| `tensor` | `TensorIndexError` | Index mimo rozsah |
| `tensor` | `TensorLayoutError` | Ne-kontinuální tenzor |
| `config` | `ConfigCycleError` | Cyklická závislost |
| `fd` | `FileError` | Souborová/socketová chyba |

```lsl
load json

try:
    data = json.decode("{neplatny json")
else:
    print "Selhalo parsování JSON:", last_error()
    data = {}
end
```

## Omezení

- **Syntaktické chyby** (ParseError) nelze zachytit — objeví se při
  překladu, ještě před spuštěním.
- **`exit(status)`** nelze zachytit — bezpodmínečně ukončí celý proces.
- **Není `finally`** — LSL nemá blok, který by se provedl vždy, ať už
  chyba nastala nebo ne. Úklidové operace musíte buď udělat před `end`,
  nebo duplikovat do `else` větve.

## Shrnutí: jak vybrat správný mechanismus

```
Může tato chyba nastat za normálního provozu?
  ├── NE → použij check() — ať to selže hned a hlasitě
  └── ANO → potřebuju vědět, ŽE selhalo?
       ├── ANO → try/else
       └── NE  → safe (a případně last_error() pro logování)
```

## Kompletní příklad

Program, který načte JSON konfiguraci, validuje ji a použije:

```lsl
load json

function nacti_konfiguraci(cesta):
    # Načtení souboru
    try:
        text = readfile(cesta)
    else:
        Error(ConfigError: "nelze přečíst konfigurační soubor: " + cesta)
    end

    # Parsování JSON
    try:
        config = json.decode(text)
    else:
        Error(ConfigError: "neplatný JSON v konfiguraci")
    end

    # Validace povinných klíčů
    check("port" in config, "konfigurace musí obsahovat 'port'")
    check(config["port"] >= 1024, "port musí být >= 1024")
    check("host" in config, "konfigurace musí obsahovat 'host'")

    return config
end

function spust_server(config):
    printl "Spouštím server na {config['host']}:{config['port']}"
    # ... server logic ...
end

# Hlavní program
try:
    config = nacti_konfiguraci("server.json")
    call spust_server(config)
else:
    print "CHYBA:", last_error()
    print "Server nelze spustit."
    exit(1)
end
```

Tento kód:

1. Zkusí načíst a naparsovat JSON.
2. Ověří, že obsahuje povinné klíče ve správném formátu.
3. Pokud cokoliv selže, vypíše srozumitelnou chybu a ukončí se.

## Kam dál

- [06 — Moduly a standardní knihovny](06-modules-and-imports.md):
  přehled všech vestavěných modulů.
- [07 — Soubory, I/O a procesy](07-files-io-and-processes.md):
  práce se soubory, spouštění programů, HTTP.
