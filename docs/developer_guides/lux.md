# Knihovna lux

`load lux`

Základní modul jazyka: metadata verze a malé sdílené pomocníky.

## Funkce

### lux.identity(value)

Vrátí hodnotu beze změny.

### lux.clamp(value, low, high)

Omezí číslo na interval `[low, high]`.

### lux.is_empty(collection)

`True`, pokud je kolekce prázdná (List, Tuple, Dictionary, Set,
RealArray, String).

## Příklad

```lsl
load lux

print lux.clamp(7, 0, 5)        # 5
print lux.is_empty([])          # True
```

## Související stránky

- `lsl man math` — `math.clamp` pro Float
- `lsl man config` — konfigurační moduly
