# Knihovna configure

`load configure`

Generuje nativní evaluátor konfigurace pro jeden graf modulů — nástroj,
za kterým stojí `lsl-configure`. Zjednodušeně: čte importy konfiguračního
grafu, validuje čistotu zdrojů a staví spustitelný obrázek evaluátoru.

## Hlavní funkce

### configure.collect(path, seen, active, order, sources, source_budget)

Projde graf importů od `path` a sesbírá zdrojové soubory v
deterministickém pořadí s rozpočtem na velikost a hloubku grafu.

### configure.validate_pure(tokens, path)

Ověří, že zdroj obsahuje jen povolené konstrukce pro konfigurační
evaluaci (žádný nebezpečný kód).

### configure.extract_imports(tokens, path)

Vytáhne importy ze zdroje (`load` řádky).

### configure.snapshot_name(index) / configure.module_name(root, path)

Deterministická jména modulů grafu pro kompilaci.

## Použití

```lsl
load configure

path = "examples/config/system.lsl"
```

Knihovna je primárně vnitřní nástroj `lsl-configure`; koncoví uživatelé
vyhodnocují konfigurace přes `lsl config SOUBOR`.

## Chyby

- `ConfigError` — neplatný graf, překročený rozpočet, cyklus importů.

## Související stránky

- `lsl man config` — deklarace voleb a priority
- `lsl man lconf` — manifesty závislostí
