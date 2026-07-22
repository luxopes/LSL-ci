# LSL TODO

Přesný průběžný stav, hashe a důkazy jsou v `PURE_LSL_PROGRESS.md`. Aktuální handoff, pořadí blockerů a ověřovací příkazy jsou v `COMPLETION_PLAN.md`.

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
- [x] Dokončit dokumentované collection metody a Dictionary konverzi.
- [x] Odstranit pevný 4096B limit `input()` a číst přesně jeden řádek.
- [x] Odstranit pevný 1MiB limit `capture()` dynamicky rostoucím bufferem.
- [ ] Dokončit jednoznačný scalar tag ABI (Function type 10 je hotový; zbývá raw Any return hranice).
- [x] Doplnit AI provider errors/retry/cancellation, lazy config/cycles/defaults/provenance, structured process status a pure-LSL zero-copy CPU Tensor.
- [x] Doplnit omezený in-process CPU ET_DYN Int64 kernel ABI a neomezené stderr capture.
- [ ] Pokračovat dynamic table growth, skutečný HTTP streaming a audit okruhy níže.

## Zbývá

- dokončit jednoznačný scalar tag ABI tak, aby ani záměrný raw Int shodný s živou heap adresou nemohl kolidovat s object value;
- další numerické edge cases; Int overflow má definovanou two's-complement modulo `2^64` sémantiku a conformance;
- případná ABI v2 rozšíření nad hotovým self-contained CPU ET_DYN v1 (relocations/Tensor descriptors); GPU je mimo aktuální scope;
- rozšířit negative/conformance, benchmarky a další targety;
- po finální kontrole odstranit případné zbylé transition poznámky a nepotřebné smoke zdroje.
