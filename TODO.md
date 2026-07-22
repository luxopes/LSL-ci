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
- [x] Dokončit jednoznačný scalar tag ABI včetně metadata-tagged callback returns a raw-Int/live-pointer collision proof.
- [x] Doplnit AI provider errors/retry/cancellation, lazy config/cycles/defaults/provenance, structured process status a pure-LSL zero-copy CPU Tensor.
- [x] Doplnit omezený in-process CPU ET_DYN Int64 kernel ABI a neomezené stderr capture.
- [x] Doplnit skutečné průběžné process/HTTP transport chunk callbacks.
- [x] Doplnit dynamický růst object registry a String intern cache.
- [x] Spustit závěrečný full suite, config, installed fixed-point a ELF audit.
- [ ] Dokončit fault-injection hardening process setup/cleanup syscallů.
- [x] Změřit a zrychlit compiler/test runner bez změny deterministického výstupu (full −59 %, compiler −9 %, peak RSS −5,6 %).

## Feature scope 0.7 bez GPU

Feature scope je implementovaný: self-host compiler/runtime, jazyk a collections, config lazy/default/provenance, AI retry/cancellation/SSE + live transport chunks, process JSON ABI, structured stdout/stderr/status, zero-copy CPU Tensor a omezený in-process CPU ET_DYN ABI v1.

## Zbývá hardening/bugfix/audit

- další numerické edge cases; Int overflow má definovanou two's-complement modulo `2^64` sémantiku a conformance;
- případná ABI v2 rozšíření nad hotovým self-contained CPU ET_DYN v1 (relocations/Tensor descriptors); GPU je mimo aktuální scope;
- rozšířit negative/conformance, benchmarky a další targety;
- po finální kontrole odstranit případné zbylé transition poznámky a nepotřebné smoke zdroje.
