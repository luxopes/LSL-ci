# Knihovna config

`load config`

Pomocníci pro deklarativní konfigurační moduly vyhodnocované příkazem
`lsl config`. Konfigurace je graf LSL modulů; knihovna poskytuje
deklarace voleb a prioritní kombinátory.

## Deklarace voleb

```lsl
config.option(expected_type, default_value, description)
config.required(expected_type, description)
```

- `expected_type` — jeden z `"str"`, `"int"`, `"bool"`, `"list"`,
  `"set"` (nebo `None` pro volný typ).
- `required` nemá výchozí hodnotu; bez nadefinování selže vyhodnocení.

## Priority a kombinátory

```lsl
config.mkOverride(priority, value)   # hodnota s prioritou
config.mkDefault(value)              # nejnižší priorita (default)
config.mkForce(value)                # nejvyšší priorita (force)
config.mkIf(condition, value)        # hodnota jen při splnění podmínky
config.lazy(thunk)                   # odložené vyhodnocení funkce
```

Hodnoty se slučují podle priority: `force` přebije vše, `default`
přebije jen nic.

## Příklad

```lsl
load config

port = config.option("int", 8080, "Port HTTP serveru")
host = config.required("str", "Adresa pro bind")

theme = config.mkOverride(50, "dark")
```

Konfigurační moduly se vyhodnocují `lsl config SOUBOR`, který vypíše
sloučený výsledek jako JSON. Vyhodnocení běží s časovými a paměťovými
limity.

## Chyby

- `ConfigError` — neplatná deklarace, chybějící povinná volba,
  nekompatibilní typy při slučování.

## Související stránky

- `lsl man configure` — generátor evaluátoru
- `lsl man lconf` — manifesty závislostí
- `lsl man env` — proměnné prostředí (v config režimu zakázané)
