# LSL TODO

Přesný průběžný stav, hashe a důkazy jsou v `PURE_LSL_PROGRESS.md`.

## Hotovo

- pure-LSL Linux x86_64 compiler, přímý machine code a ELF writer;
- bitově shodný multi-stage fixed point bez C/Python/shell toolchainu;
- veřejné LSL-generované `lsl` a `compiler/lslc`;
- UTF-8 String, collections, Float, functions/callbacks, classes a exceptions;
- recursive modules, JSON a NixOS-style config evaluator;
- syscall filesystem/process/capture/env, HTTP argv boundary;
- mark-sweep cycle GC a free-list reuse;
- pure-LSL installer a test runner;
- přesný selfhost a config conformance.

## Nedávno hotovo (inkrementálně, každé s conformance testem a self-host fixed pointem)

- okruh 2: validace `Int(String)` a dynamické `Int(Any)` konverze (dřív `Int("abc")` vracelo garbage);
- okruh 2: oprava Float `**` mocniny (dřív `2.0 ** 53` vracelo `0`).

## Aktivní plán

- [x] Doplnit indexed augmented assignment pro List, RealArray a Dictionary.
- [x] Odstranit omezení literal-only `rang` kroku; stop i step se vyhodnotí jednou.
- [x] Dokončit Float round-trip/exponent formatting včetně subnormal, NaN a Infinity.
- [ ] Dokončit jednoznačný scalar tag ABI.
- [ ] Pokračovat zbývajícími runtime, plugin/AI/config a audit okruhy níže.

## Zbývá

- dokončit jednoznačný scalar tag ABI tak, aby ani záměrný raw Int shodný s živou heap adresou nemohl kolidovat s object value;
- zbytek okruhu 2: kontrolovaný integer overflow a další numerické edge cases;
- dokončit pokročilé Tuple/RealArray metody a runtime error parity;
- vedle hotového JSON process plugin ABI navrhnout pure-LSL in-process shared-object/zero-copy tensor loader;
- rozšířit negative/conformance, benchmarky a další targety;
- po finální kontrole odstranit případné zbylé transition poznámky a nepotřebné smoke zdroje.
