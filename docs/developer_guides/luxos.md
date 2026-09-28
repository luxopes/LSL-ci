# Knihovna luxos

`load luxos`

Deklarativní konfigurační engine systému LuxOS: aplikuje manifest
(hostname, motd, balíčky, uživatelé) na běžící systém a vede generace
změn pro rollback.

## Funkce

### luxos.apply(config)

Validuje a aplikuje konfiguraci. S `LUXOS_DRY_RUN` jen vypíše plánované
změny; jinak provede změny a zaznamená novou generaci. Vrací seznam změn.

### luxos.apply_manifest()

Aplikuje manifest z cesty v `LUXOS_MANIFEST` (používá `lux rollback`).

### luxos.defaults()

Výchozí konfigurace:

```lsl
{"hostname": "luxos", "locale": "C", "timezone": "UTC",
 "keymap": "us", "motd": None, "packages": [], "users": []}
```

### luxos.validate_config(config)

Ověří celý manifest (hostname, identifikátory, balíčky, uživatelské
účty).

### luxos.field(config, name, fallback)

Čtení pole s fallbackem.

## Příklad

```lsl
load luxos

config = luxos.defaults()
config["hostname"] = "router"
config["packages"] = ["curl", "git"]
changes = luxos.apply(config)
```

## Chyby

- `ValueError` — neplatný manifest (hostname, identifikátory).

## Související stránky

- `lsl man system` — imperativní správa balíčků
- `lsl man config` — deklarativní konfigurace LSL
- `lsl man env` — `LUXOS_DRY_RUN`, `LUXOS_MANIFEST`
