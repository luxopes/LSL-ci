# Deklarativní konfigurace

Produkční evaluator je `stdlib/configure.lsl`, sám přeložený self-hostovaným compilerem. Python se nepoužívá.

LSL má oddělený čistý evaluator pro konfigurace ve stylu NixOS. Konfigurační modul je běžný `.lsl` soubor, který exportuje `config` a volitelně `imports`, `options` a `assertions`.

```lsl
load config

imports = ["hardware.lsl", "services/ai.lsl"]
options = {
    "services.ai.enable": config.option("Bool", False, "Enable AI API")
    "services.ai.port": config.option("Int", 11434, "AI API port")
}
config = {
    "services": {
        "ai": {
            "enable": True
            "port": config.mkDefault(11434)
        }
    }
}
assertions = [[True, "policy rejected configuration"]]
```

Vyhodnocení:

```bash
./lsl config system.lsl
```

## Merge

Importy se vyhodnocují jednou v deterministickém post-order pořadí, root modul poslední.

- Dictionary se slučují rekurzivně.
- Listy se při stejné prioritě spojují.
- Skalární hodnota pozdějšího modulu vyhraje.
- `mkDefault(value)` má prioritu 100.
- obyčejná hodnota má prioritu 500.
- `mkForce(value)` má prioritu 1000.
- `mkOverride(priority, value)` nastaví explicitní prioritu.
- `mkIf(condition, value)` hodnotu při `False` úplně vynechá.

## Čistota a reprodukovatelnost

V config režimu nejsou dostupné `input`, souborové funkce, hodiny ani moduly `http` a `env`. Jedinými hostitelskými vstupy jsou root soubor a explicitní graf `imports`. Výsledek je deterministicky serializovatelný do kompaktního JSON. Config generator staticky odmítá ambientní I/O a síťové funkce. Kryptografický derivační store a generation hash ještě patří do vyššího aktivačního nástroje, nikoli do evaluatoru.

Deklarované options se kontrolují. Typ option může být `Bool`, `Int`, `Float`, `String`, `List`, `Dictionary`, `None`, `Any` nebo sjednocení, například `String|None`.

Aktuální evaluator řeší hodnoty a modulový systém. Generace, aktivace systému, rollback, package store a derivace budou vyšší nástroje nad tímto čistým výsledkem; nejsou předstírány jako hotová součást jazyka.
