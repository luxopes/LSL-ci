# LSL 0.7.8

Patch vydání přidává `random` v čistém LSL a list/dict comprehensions.
Compiler, runtime i standardní knihovna zůstávají self-hosted bez Pythonu,
libc a externího assembleru/linkeru. CUDA worker se nemění.

- `random`: MT19937, reprodukovatelné seedy, SHA-512 textové seedování,
  snapshot/restore, OS SystemRandom, náhodné bajty a BigInt až 4096 bitů.
  Rozsahy, shuffle, choice/choices/sample včetně vah a počtů; všechna běžná
  veřejná rozdělení Python random, včetně binomial. Veřejná volání jsou
  synchronizovaná mezi vlákny. Přesná kompatibilita a limity: [random.md](random.md).
- Comprehensions: vnořené listy/slovníky, více for/if klauzulí, ploché
  rozbalování, oddělené proměnné a klíč před hodnotou. Tuple lze vytvořit
  eager převodem; Set, lazy generátory a gzip komprese se nepřidávají.
- Výchozí immutable argumenty a pojmenovaná volání deklarovaných funkcí,
  metod a konstruktorů, s kontrolou chybějících/duplicitních argumentů.
  Keyword builtiny a Function hodnoty s defaulty zatím nejsou podporovány.
- Poprvé vydané binárky obsahují již dokončený self-updater:
  `lsl update` aktualizuje LSL, `lsl update NAME` knihovnu. Ed25519 manifest,
  verze/platforma/velikost/SHA-256, atomické přepnutí a rollback.
  Registry je `https://lsl.lux-ai.cz/packages`. Viz [updates.md](updates.md).

Nové testy pokrývají referenční SHA-512/MT19937 vektory, BigInt, stav,
váhy a mezní vstupy, statistické sanity kontroly, sdílená vlákna,
comprehension scopes/GC a compile-time bezpečnostní diagnostiku.

Self-host stage 2 a 3 jsou bitově shodné. Sériový build všech LSL nástrojů
proběhl pod 2 GiB; pro úplnou sadu s HTTP/GC stress je vyhrazen limit 4 GiB.
Compiler SHA-256:
`00743c98334cc8014f709a4204fe556e69ecc61450441a4f2ed64deaa66bf9bc`.
CLI SHA-256:
`a810cb486e6041e1ad214f6943129b1509e2af62bdb17a72aa0e00dd603b9149`.
