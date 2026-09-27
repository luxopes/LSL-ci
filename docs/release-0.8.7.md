# Release LSL 0.8.7

Drobné vydání se dvěma jazykovými opravami z praxe. Compiler i host runtime
zůstávají pure LSL; generovaný kód pro dosavadní programy se nemění.

## rang jako hodnota

`rang(...)` bylo dosud jen součástí `for i in rang(...)` a comprehensions;
jinde skončilo matoucí chybou `unknown native function: rang`. Od 0.8.7 je
mimo `for` běžnou hodnotou — List celých čísel, která by smyčka navštívila:

```lsl
delitele = List(rang(2, 100 + 1))
print rang(4)              # [0, 1, 2, 3]
print len(rang(0, 10, 3))  # 4
print rang(10, 0, -3)      # [10, 7, 4, 1]
```

`rang(STOP)`, `rang(START, STOP)` a `rang(START, STOP, STEP)` vyžadují Int
argumenty, `STEP` nesmí být nula a výsledek smí mít nejvýše 100 000 000 prvků.
Smyčky `for` a comprehensions dál běží bez alokace seznamu. Parametr nebo
proměnná jménem `rang` má stejně jako dosud přednost.

## List.find

`seznam.find(hodnota)` vrátí pozici prvního výskytu, nebo `-1`, když prvek
chybí — stejně jako `find` u Stringu, zatímco `index` vyvolá `ValueError`.
Funguje i pro Tuple a RealArray a pro hodnoty, jejichž typ je znám až za běhu
(`find` rozliší String a List). Dosud `find` na Listu končil chybou
`type List has no method find`.

## Manuál

Kapitola 17 vysvětluje, proč `sudo lsl …` nevidí uživatelské knihovny
(`sudo` nastaví `HOME=/root`) a že aktualizace LSL knihovny nemaže.

## Ověření

`tests/rang_value_conformance.lsl` a `tests/list_find_conformance.lsl`
v agregovaném korpusu; plná sada a fixed-point.

## Přechod

`lsl update` (u systémové instalace `sudo /usr/local/bin/lsl update --system`).
