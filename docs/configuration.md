# Deklarativní konfigurace

Produkční evaluator je `stdlib/configure.lsl`, sám přeložený self-hostovaným compilerem. Python se nepoužívá.

Tento čistý evaluator je určený jen pro skládání datového JSON výstupu. Správa
LuxOS není zvláštní DSL: napište běžný `.lsl` program, načtěte modul `system` a
spusťte jej přes `./lsl machine.lsl`; viz [system.md](system.md).

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

Importy se vyhodnocují jednou v deterministickém post-order pořadí, root modul poslední. Import cycle skončí před kompilací s diagnostikou celé cesty, například `a.lsl -> b.lsl -> a.lsl`.

- Dictionary se slučují rekurzivně.
- Listy se při stejné prioritě spojují.
- Skalární hodnota pozdějšího modulu vyhraje.
- `mkDefault(value)` má prioritu 100.
- obyčejná hodnota má prioritu 500.
- `mkForce(value)` má prioritu 1000.
- `mkOverride(priority, value)` nastaví explicitní prioritu.
- `mkIf(condition, value)` hodnotu při `False` úplně vynechá.

## Lazy hodnoty

`config.lazy(thunk)` odloží volání bezargumentové Function až do materializace výsledného stromu. Každý lazy výsledek se rekurzivně materializuje stejně jako běžná hodnota. Rekurzivní thunk dependency je detekována a končí `ConfigCycleError`, místo nekonečné rekurze. LSL 0.6 nemá closures, takže thunk čte module globals nebo volá jiné pojmenované funkce.

## Čistota a reprodukovatelnost

V config režimu nejsou dostupné `input`, souborové funkce, hodiny ani moduly `http`, `env`, `time`, `os` a `system`. Jedinými hostitelskými vstupy jsou root soubor a explicitní graf `imports`. Výsledek je deterministicky serializovatelný do kompaktního JSON. Config generator staticky odmítá ambientní I/O a síťové funkce. Kryptografický derivační store a generation hash ještě patří do vyššího aktivačního nástroje, nikoli do evaluatoru.

Deklarované options se kontrolují a descriptor nese provenance souboru, který option deklaroval; missing/type diagnostika tento soubor vypíše. Chybějící nepovinná option se materializuje do výsledného stromu ze svého defaultu; chybějící required option je chyba. Typ option i defaultu musí odpovídat `Bool`, `Int`, `Float`, `String`, `List`, `Dictionary`, `None`, `Any` nebo sjednocení, například `String|None`.

Aktuální evaluator řeší hodnoty a modulový systém. Generace, aktivace systému, rollback, package store a derivace budou vyšší nástroje nad tímto čistým výsledkem; nejsou předstírány jako hotová součást jazyka.
