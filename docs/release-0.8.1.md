# LSL 0.8.1

Vydání přidává řazení, množiny a deduplikaci v čistém LSL.

- `sorted(iterable)` vrací nový stabilně vzestupně seřazený List; vstup
  nemění. Přijímá sekvence, Set a klíče Dictionary. Podporuje jeden
  poziční argument, zatím bez `key` a `reverse`.
- `set()` / `set(iterable)` vytváří skutečný typ Set. Obsahuje jedinečné
  neměnné hodnoty, podporuje členství, iteraci, GC, rovnost nezávislou na
  pořadí a množinové metody. Iterace zachovává pořadí vložení; vyhledávání
  je lineární, nejde o hashovou tabulku. Mutable kolekce nelze vložit.
- `dedup(list)` vrací nový List s prvními výskyty v původním pořadí.
  Strukturálně porovnává i vnořené mutable kolekce a podporuje cykly.
  Vstup nemění; porovnávání má v nejhorším případě kvadratickou složitost.
- `help("sorted")`, `help("set")` a `help("dedup")` popisují nové funkce.
  Webový i offline manuál obsahují příklady a přesné limity.

```lsl
values = [3, 1, 3, 2]
print sorted(values) # [1, 2, 3, 3]
print dedup(values)  # [3, 1, 2]
print set(values)    # {3, 1, 2}
print values        # [3, 1, 3, 2]
```

Stávající `list.sort()` nadále řadí seznam na místě a vrací None.
Set zatím nemá literál, comprehension, indexaci ani operátorové zkratky;
podporované metody a typy prvků uvádí [kolekce](developer_guides/04-collections.md).

Compiler, runtime, CLI a testy zůstávají self-hosted LSL. CUDA worker ani
formát podepsaného aktualizačního kanálu se nemění. Z 0.8.0 lze přejít přes
`lsl update`, pro systémovou instalaci `sudo /usr/local/bin/lsl update --system`.
Pro starší 0.7.8 platí [jednorázový instalační postup](developer_guides/17-cli-and-packages.md#jednorázový-přechod-z-078).
