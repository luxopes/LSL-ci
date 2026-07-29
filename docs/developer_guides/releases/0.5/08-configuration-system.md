# 8. Konfigurační systém

LSL obsahuje čistý deklarativní evaluator pro reprodukovatelné systémové
konfigurace ve stylu NixOS. Tato kapitola vysvětluje, jak ho používat.

## Motivace: proč deklarativní konfigurace

Představte si, že máte soubor `config.lsl`, který popisuje nastavení
vašeho serveru — jaké služby běží, jací uživatelé existují, jaké balíčky
jsou nainstalované. Tento soubor je čistě deklarativní: říká CO má být,
ne JAK toho dosáhnout. Evaluator (konfigurační režim `lsl config`) z něj
vyrobí JSON, který pak jiný nástroj použije k nastavení systému.

Výhody:
- **Reprodukovatelnost**: stejný vstup → stejný výstup, vždy.
- **Bezpečnost**: evaluator nesmí na síť, nesmí k souborům, nesmí
  číst environment proměnné. Nemůže udělat nic destruktivního.
- **Slučování**: více modulů může přispívat do jedné konfigurace,
  hodnoty se slučují podle priorit.

## Dva režimy LSL

LSL rozlišuje dva režimy:

1. **Běžný programovací režim** (`./lsl program.lsl`) — plný přístup k
   souborům, procesům, síti, environment proměnným. Pro aplikace,
   správu systému a AI orchestrace.

2. **Konfigurační režim** (`./lsl config system.lsl`) — čistý evaluator
   bez I/O, sítě, environment proměnných a času. Pouze pro skládání
   deterministických konfigurací.

## Struktura konfiguračního modulu

Konfigurační modul je běžný `.lsl` soubor, který exportuje:

```lsl
load config

imports = ["hardware.lsl", "services/web.lsl"]

options = {
    "services.web.enable": config.option("Bool", False, "Povolit web server")
    "services.web.port": config.option("Int", 8080, "Port web serveru")
}

config = {
    "services": {
        "web": {
            "enable": True
            "port": config.mkDefault(8080)
        }
    }
}

assertions = [
    [True, "Tato aserce vždy projde"]
]
```

### Povinné exporty

| Symbol | Typ | Význam |
|---|---|---|
| `config` | Dictionary | Hlavní konfigurační strom |
| `imports` | List[String] | Seznam importovaných modulů |
| `options` | Dictionary | Deklarace voleb (typ, výchozí hodnota, popis) |
| `assertions` | List[[Bool, String]] | Bezpečnostní podmínky |

Vše kromě `config` je volitelné.

## Vyhodnocení

```bash
./lsl config system.lsl > system.json
```

Co se děje při vyhodnocení:

1. Importy se vyhodnocují v deterministickém **post-order** pořadí (nejdřív
   nejhlubší závislosti, root modul poslední).
2. Import cycle je chyba — je detekována před kompilací s diagnostikou
   celé cesty (např. `a.lsl -> b.lsl -> a.lsl`).
3. Hodnoty se slučují (merge) podle priorit.
4. Lazy hodnoty se materializují.
5. Ověří se assertions.
6. Výsledek se serializuje do JSON.

## Merge (slučování hodnot)

Více modulů může definovat stejné klíče. Hodnoty se slučují podle těchto
pravidel:

### Pravidla slučování

1. **Dictionary** se slučují rekurzivně — klíče z obou modulů se spojí.
2. **List** se při stejné prioritě spojují (konkatenují).
3. **Skalární hodnota** — vyhraje pozdější modul (vyšší priorita vítězí).

### Priority

| Funkce | Priorita | Význam |
|---|---|---|
| `config.mkDefault(value)` | 100 | Výchozí hodnota |
| obyčejná hodnota `value` | 500 | Normální nastavení |
| `config.mkForce(value)` | 1000 | Vynucená hodnota |
| `config.mkOverride(prio, value)` | `prio` | Explicitní priorita |

```lsl
# hardware.lsl
config = {
    "cpu": {
        "cores": 4                # priorita 500
        "frequency": config.mkDefault(2400)  # priorita 100
    }
}

# overrides.lsl (importován POZDĚJI)
config = {
    "cpu": {
        "cores": config.mkForce(8)      # priorita 1000 — přepíše
        "frequency": 3200               # priorita 500 — přepíše default
    }
}
```

### mkIf — podmíněná hodnota

```lsl
config = {
    "features": {
        "gpu": config.mkIf(gpu_enabled, {
            "driver": "nvidia"
            "version": "550"
        })
    }
}
```

Pokud je `gpu_enabled == False`, hodnota se úplně vynechá (jako by nebyla
definována). Při `True` se použije normálně.

## Options (deklarace voleb)

Options slouží k dokumentaci a validaci:

```lsl
options = {
    "services.web.enable": config.option("Bool", False, "Povolit web server")
    "services.web.port": config.option("Int", 8080, "Port web serveru")
    "services.web.hostname": config.option("String", "localhost", "Adresa serveru")
    "services.web.ssl": config.option("Bool|None", None, "SSL konfigurace")
}
```

`config.option(typ, výchozí_hodnota, popis)`:

- **typ** — `"Bool"`, `"Int"`, `"Float"`, `"String"`, `"List"`,
  `"Dictionary"`, `"None"`, `"Any"`, nebo sjednocení `"String|None"`.
- **výchozí_hodnota** — použije se, pokud option není nastavena.
- **popis** — lidsky čitelný popis.

Chování:

- Missing required option (bez defaultu) → chyba.
- Chybějící nepovinná option → materializuje se z defaultu.
- Typ option a defaultu se musí shodovat.
- Descriptor nese provenienci (soubor, který option deklaroval).

## Lazy hodnoty

`config.lazy(thunk)` umožňuje odložené vyhodnocení:

```lsl
config = {
    "users": {
        "root": {
            "home": "/root"
            "shell": "/bin/bash"
        }
    }
    "defaultUserShell": config.lazy(function():
        return config["users"]["root"]["shell"]
    end)
}
```

- `thunk` je bezargumentová Function.
- Vyhodnotí se až při materializaci výsledného stromu.
- Rekurzivní thunk dependency → `ConfigCycleError`.

Poznámka: LSL 0.5 nemá closures, takže thunk musí číst buď modulové
globály, nebo volat jiné pojmenované funkce.

## Assertions

Assertions ověřují bezpečnostní podmínky:

```lsl
assertions = [
    [config["services"]["web"]["port"] >= 1024, "Port nesmí být privilegovaný"]
    [config["services"]["web"]["port"] != 22, "Port 22 je vyhrazen pro SSH"]
    [len(config["users"]) > 0, "Musí existovat alespoň jeden uživatel"]
]
```

Každá aserce je dvojice `[podmínka, zpráva]`. Pokud je podmínka `False`,
vyhodnocení selže s danou zprávou.

## Čistota a reprodukovatelnost

V konfiguračním režimu (`lsl config`) nejsou dostupné:

- `input` — žádné čtení ze stdin
- `readfile`, `writefile`, `appendfile`, `remove_path` — žádný filesystém
- `readbytes`, `writebytes` — žádné binární I/O
- `clock()`, `time` modul — žádný čas
- `env` modul — žádné environment proměnné
- `http` modul — žádná síť
- `os`, `process`, `system`, `run` — žádné procesy

Jediným vstupem je root soubor a explicitní graf `imports`. Výsledek je
**deterministicky serializovatelný** do JSON.

## Příklad: Jednoduchá konfigurace

`system.lsl`:

```lsl
load config

imports = ["hardware.lsl", "networking.lsl", "services.lsl"]

config = {
    "hostname": "myserver"
    "timezone": "Europe/Prague"
}

assertions = [
    [config["hostname"] != "", "hostname nesmí být prázdný"]
]
```

`networking.lsl`:

```lsl
load config

config = {
    "networking": {
        "hostname": config.mkDefault("localhost")
        "interfaces": {
            "eth0": {
                "useDHCP": True
            }
        }
    }
}
```

`services.lsl`:

```lsl
load config

options = {
    "services.ssh.enable": config.option("Bool", True, "Povolit SSH")
}

config = {
    "services": {
        "ssh": {
            "enable": True
            "port": 22
        }
    }
}

assertions = [
    [config["services"]["ssh"]["port"] > 0, "SSH port musí být kladný"]
]
```

Spuštění:

```bash
./lsl config system.lsl
```

Výstup:

```json
{
  "hostname": "myserver",
  "timezone": "Europe/Prague",
  "networking": {
    "hostname": "localhost",
    "interfaces": {
      "eth0": {
        "useDHCP": true
      }
    }
  },
  "services": {
    "ssh": {
      "enable": true,
      "port": 22
    }
  }
}
```

## Porovnání: konfigurační vs imperativní režim

| Vlastnost | `lsl config` | `lsl program.lsl` |
|---|---|---|
| I/O (soubory) | ❌ zakázáno | ✅ povoleno |
| Síť | ❌ zakázáno | ✅ povoleno |
| Environment | ❌ zakázáno | ✅ povoleno |
| Čas | ❌ zakázáno | ✅ povoleno |
| Procesy | ❌ zakázáno | ✅ povoleno |
| `system.install` | ❌ zakázáno | ✅ povoleno |
| Reprodukovatelnost | ✅ 100% | ❌ závisí na vstupech |
| Určení | Skládání konfigurace | Správa systému a aplikace |

Pro správu balíčků a služeb použijte imperativní režim s modulem `system`.
Konfigurační režim je pouze pro čisté skládání konfiguračního stromu.

## Kam dál

- [09 — GUI programování](09-gui-programming.md): tvorba grafických aplikací
- [10 — AI aplikace](10-ai-applications.md): AI orchestrace
- [12 — Interní architektura compileru](12-compiler-internals.md): jak compiler funguje uvnitř
