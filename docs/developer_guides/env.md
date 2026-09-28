# Knihovna env

`load env`

Čte proměnné prostředí procesu a od LSL 0.8.9 automaticky načítá `.env`.
Soubor se čte až za běhu; jeho hodnoty se při kompilaci nevkládají do binárky.

## Kde se hledá .env

- `lsl program.lsl`: vedle vstupního skriptu, i když jej spouštíte z jiného adresáře.
- Program vytvořený `lsl compile` nebo `lslc`: vedle spustitelné binárky.
- Interaktivní režim a zdroj ze stdin: v aktuálním pracovním adresáři.

Platí i pro nepřímý import `env` z jiné knihovny. Chybějící `.env` nevadí;
existující nečitelný nebo neplatný soubor vyvolá chybu.
Nehledají se nadřazené adresáře ani automaticky celý domovský adresář.

**Proměnná prostředí procesu má přednost**, i když obsahuje prázdný řetězec.
Hodnoty z `.env` jsou uložené pouze v modulu `env`; nemění prostředí procesu
ani prostředí jeho potomků. Soubor se automaticky načte jednou při inicializaci
modulu; další proces jej načte znovu.

## Formát souboru

```dotenv
# komentář
LUX_AI_API=hodnota
export DEBUG=true
EMPTY=
TITLE="Text s mezerami # uvnitř hodnoty"
LITERAL='${HOME} se nerozvíjí'
NAME=value # komentář za hodnotou
```

Jména v `.env` odpovídají `[A-Za-z_][A-Za-z0-9_]*` (nejvýše 255 znaků).
Podporovány jsou LF/CRLF, UTF-8 v hodnotách, úvodní BOM, prázdné řádky,
mezery kolem `=` a volitelné `export`. Poslední výskyt stejného jména vyhrává.
Neuvozené `#` začíná komentář na začátku hodnoty nebo po mezeře/tabulátoru;
`abc#def` zůstává celou hodnotou. Jednoduché uvozovky zachovají obsah doslova.
V dvojitých uvozovkách fungují `\n`, `\r`, `\t`, `\"` a `\\`;
neznámé escape sekvence zůstávají doslova. Víceřádkové hodnoty nejsou podporované.
Shellové příkazy ani interpolace proměnných se neprovádějí.
Limit souboru je 1 MiB. Chyby uvádějí cestu a číslo řádku, nikoli jeho obsah.

## Funkce

### env.get(name, default_value)

Vrátí proměnnou procesu, jinak hodnotu z `.env`, jinak `default_value`.
Jméno musí mít 1..255 znaků bez NUL a `=`. Výchozí hodnota může mít libovolný typ.

### env.has(name)

Vrací `True`, je-li jméno v prostředí procesu nebo v načteném `.env`.
Prázdná hodnota je stále nastavená proměnná.

### env.require(name)

Jako `get`, ale při chybějícím jménu vyvolá `EnvironmentError`.

### env.load_dotenv(path=None)

Explicitně načte další soubor nebo znovu výchozí `.env`. Vrací `True`, pokud
soubor existoval a byl načten, jinak `False`. Relativní explicitní cesta je
vůči pracovnímu adresáři. Hodnoty doplní/přepíše v modulu; exportované proměnné
mají stále přednost. Při chybě zůstávají dříve načtené hodnoty zachované.

## Příklad

Uložte `.env` a `program.lsl` do stejného adresáře:

```lsl
load env

api_key = env.require("LUX_AI_API")
print env.has("LUX_AI_API")
```

Stačí `lsl program.lsl`; není potřeba `source .env` v shellu.
V čistém režimu `lsl config` je modul `env` nadále zakázán.

## Chyby

- `EnvironmentError` — neplatné jméno, chybějící povinná proměnná nebo neplatný `.env`.
- `FileError` — soubor existuje, ale nelze jej přečíst.

## Související stránky

- `lsl man os` — spouštění programů
- `lsl man config` — deklarativní konfigurace
