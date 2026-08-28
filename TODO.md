# LSL TODO

Přesný průběžný stav, hashe a důkazy jsou v `PURE_LSL_PROGRESS.md`. Aktuální handoff, pořadí blockerů a ověřovací příkazy jsou v `COMPLETION_PLAN.md`.

## 0.7.1 — audit chyb a bezpečnostní hardening

- [x] Auditovat nové hranice 0.7: HTTP/HTTPS, sandbox, provenance a safe/unsafe.
- [x] Opravit nalezené chyby a ke každé přidat cílenou regresi.
- [x] Znovu projít compiler/runtime, procesy, filesystem a paměťové ABI.
- [x] Povýšit 0.7.1-dev na release; fixed point, full suite, čistá instalace,
  installed fixed point, config a ELF audit už prošly.

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
- 0.6.9: kontrolované veřejné Any ABI pro kolekce, numeriku, konverze,
  metody a I/O; typed arrays a ByteArray slicing mají samostatné boundary testy.
- 0.6.9: odstraněny zbývající nalezené raw-Int/live-pointer kolize v
  dynamických operátorech a redukcích; compiler hlásí chybnou aritu bez pádu.
- 0.7.0: `lsl origin`, syscall-only HTTP / nginx/OpenSSL HTTPS server,
  provenance sidecary a nový capability `lsl sandbox`.
- 0.7.0: lexikální `unsafe:` hranice, safe kontrola uživatelského importního
  grafu, sandbox zákaz unsafe kódu a oprava interní/public ABI hranice modulů.

## Aktivní plán

- [x] Doplnit indexed augmented assignment pro List, RealArray a Dictionary.
- [x] Odstranit omezení literal-only `rang` kroku; stop i step se vyhodnotí jednou.
- [x] Dokončit Float round-trip/exponent formatting včetně subnormal, NaN a Infinity.
- [x] Dokončit dokumentované collection metody a Dictionary konverzi.
- [x] Odstranit pevný 4096B limit vstupu, číst celý řádek a zachovat původní `input "prompt"` i call syntaxi.
- [x] Odstranit pevný 1MiB limit `capture()` dynamicky rostoucím bufferem.
- [x] Dokončit jednoznačný scalar tag ABI včetně metadata-tagged callback returns a raw-Int/live-pointer collision proof.
- [x] Doplnit AI provider errors/retry/cancellation, lazy config/cycles/defaults/provenance, structured process status a pure-LSL zero-copy CPU Tensor.
- [x] Doplnit omezený in-process CPU ET_DYN Int64 kernel ABI a neomezené stderr capture.
- [x] Doplnit skutečné průběžné process/HTTP transport chunk callbacks.
- [x] Doplnit dynamický růst object registry a String intern cache.
- [x] Spustit závěrečný full suite, config, installed fixed-point a ELF audit.
- [x] Ošetřit process pipe/memfd/fork/read/wait/lseek/dup2 failure a doplnit deadlock-free `capture_input`.
- [x] Doplnit reálný RLIMIT_NOFILE fault corpus pro pipe/memfd cleanup a uzavřít close(2)/EINTR politiku.
- [ ] Volitelně rozšířit syntetický fault injection na obtížně vyvolatelné fork/wait/read větve.
- [x] Ověřit 0.7.0 přes full suite, čistou instalaci, instalovaný fixed
  point, config, reálný loopback HTTP/HTTPS smoke test a audit generovaných ELF.
- [x] Povýšit 0.7.0 na release, reprodukovat binárky a vytvořit archivy, tag
  a webový manuál.
- [x] Doplnit valid-source frontend fuzz, strict JSON malformed/round-trip corpus, generativní config corpus a GC cycle/deep/reuse stress.
- [x] Změřit a zrychlit compiler bez změny deterministického výstupu; doplnit near-native IntArray/FloatArray kernely a packed ByteArray.

## Feature scope 0.5 bez GPU

Feature scope je implementovaný: self-host compiler/runtime, jazyk a collections, config lazy/default/provenance, AI retry/cancellation/SSE + live transport chunks, process JSON ABI, structured stdout/stderr/status, zero-copy CPU Tensor a omezený in-process CPU ET_DYN ABI v1.

## Zbývá hardening/bugfix/audit

- plný Rust ownership/borrow checker ani statický důkaz absence data races
  zatím nejsou implementované; 0.7 poskytuje auditovatelnou `unsafe:` hranici,
  checked runtime a procesový sandbox, což je záměrně užší model;
- pro vysoce rizikový multi-tenant provoz zůstává nad rámec vestavěného
  sandboxu host-level seccomp allowlist nebo VM/microVM hranice;
- případná budoucí změna definované Int overflow sémantiky by byla samostatná
  jazyková změna; současné two's-complement modulo `2^64` chování má conformance;
- případná ABI v2 rozšíření nad hotovým self-contained CPU ET_DYN v1 (relocations/Tensor descriptors); GPU je mimo aktuální scope;
- rozšířit negative corpus a benchmarky; další targety nejsou blocker 0.5;
- [x] Přesunout veškeré testy/smoke fixtures a runner pod `tests/`; v `compiler/pure/` ponechat jen produkční funkcionalitu.
- [x] Doplnit kompaktní x86 encoding, constant/control-flow optimalizace, guarded direct-function specialization a code-size quality guard.
- [x] Dopsat praktický programming guide a interní compiler/release guide.
- [x] Přidat syscall-only `time` modul a no-argument TTY/pipe/heredoc source režim ukončený `exit` nebo EOF.
- [x] Přidat shell-free `os` modul pro command String/List, PATH, run/capture/status/check a sjednotit stdin terminátory.
