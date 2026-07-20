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

## Zbývá

- dokončit jednoznačný scalar tag ABI tak, aby ani záměrný raw Int shodný s živou heap adresou nemohl kolidovat s object value;
- dokončit pokročilé Tuple/RealArray metody a runtime error parity;
- doplnit Float exponent/round-trip formatting a další numerické edge cases;
- vedle hotového JSON process plugin ABI navrhnout pure-LSL in-process shared-object/zero-copy tensor loader;
- rozšířit negative/conformance, benchmarky a další targety;
- po finální kontrole odstranit případné zbylé transition poznámky a nepotřebné smoke zdroje.
