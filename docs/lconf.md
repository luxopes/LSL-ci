# Dependency manifest `config.lconf`

`config.lconf` je dependency soubor vyhrazený pro budoucí aplikační archivy
`.lux`. Záměrně jde o jednoduchý řádkový formát, ne XML ani spustitelný LSL.
Každý neprázdný řádek vybírá jeden ze tří zdrojů balíčků:

```text
# Dependencies of lux-ai
apt: gimp, ca-certificates
lux: lux-runtime
lsl: external_pckg
```

- `apt` — systémový balíček Debian/APT;
- `lux` — aplikace z budoucího Lux package repozitáře;
- `lsl` — modul z budoucího LSL module repozitáře.

Jeden zdroj může být na více řádcích. Čárka odděluje více jmen na řádku. Jména
mohou obsahovat ASCII písmena, číslice, `+`, `-`, `.`, `_`, `:` a `@`.
Whitespace, úvodní `-`, prázdná hodnota, neznámý zdroj a duplicitní jméno jsou
chyba. Stejné jméno v různých zdrojích zůstává samostatnou dependency.

## LSL API

```lsl
load lconf
load json

text = "apt: gimp\nlux: lux-ai\nlsl: external_pckg\n"
dependencies = lconf.decode(text)
print json.encode(dependencies)
```

Výsledek má vždy tři Listy:

```json
{"apt":["gimp"],"lux":["lux-ai"],"lsl":["external_pckg"]}
```

- `lconf.parse(text, path)` používá `path` v přesné line diagnostice;
- `lconf.decode(text)` používá source jméno `<config.lconf>`;
- `lconf.encode(dictionary)` zapisuje kanonické pořadí `apt`, `lux`, `lsl` a
  jednu dependency na řádek.

Modul neprovádí filesystem ani network I/O. Volající explicitně načte položku
archivu a předá parseru její UTF-8 text.

## Rezervovaný layout archivu `.lux`

Package manager a vzdálený repozitář vzniknou samostatně. Rezervovaný lokální
formát je POSIX tar se suffixem `.lux` a přesně těmito top-level položkami:

```text
ABOUT
config.lconf
<jeden executable pojmenovaný v ABOUT>
```

`ABOUT` ponese minimálně package name, version, architecture, executable name a
description. `config.lconf` používá formát výše. Budoucí installer musí odmítnout
absolutní cesty, `..`, odkazy unikající z extraction rootu, device nodes,
duplicitní položky, nevalidní UTF-8 metadata a executable odlišný od `ABOUT`.
Network katalog, signatures a trust policy jsou záměrně odloženy, dokud nebude
specifikovaný Lux server.
