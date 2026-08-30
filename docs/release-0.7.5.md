# LSL 0.7.5

LSL 0.7.5 opravuje vyčerpání alokátoru dlouhoběžícího HTTP serveru. Chybu
odhalil reálný provoz: loopback dashboard po hodinách běhu spadl s
`MemoryError: allocator or object table exhausted`.

## Hlavní změny

- `httpserver.serve_listener` volá po každém obslouženém požadavku `gc()`.
  Automatická alokační heuristika s request smyčkou nedrží krok — měřený
  program bez explicitního `gc()` narostl za 8000 iterací na 2,5 GB RSS,
  s ním zůstal na 28 MB. Ve worker vláknech je `gc()` no-op, takže vláknové
  listenery se nemění; listener na hlavním vlákně zůstává plochý.
- Nová endurance konformance: child proces obslouží 1200 požadavků
  s handlerem alokujícím ~100 KB na požadavek a ověří, že jeho VmRSS
  zůstane pod 150 MB. Bez opravy test měřitelně selže (2,9 GB, status 3).
- Dlouhoběžící smyčky mimo httpserver mají volat `gc()` periodicky samy;
  doporučení je doplněno v programátorské příručce.

## Známý otevřený defekt

Kombinace `gc()` na hlavním vlákně, běžícího worker vlákna a heapu po
~9 MiB HTTP přenosu skrz vláknový `serve_listener` se umí zablokovat:
`gc()` doběhne, ale následující alokace hlavního vlákna se točí s drženým
heap mutexem a worker na tomtéž mutexu čeká. Reprodukce je
`tests/known_issues/gc_thread_bigheap_hang.lsl` (mimo test runner).
Praktické pravidlo do opravy: dlouhoběžící listener provozujte ve vlastním
procesu (přesně to dělá endurance konformance i LuxAI Enterprise) a
nekombinujte `gc()` s aktivně alokujícími worker vlákny po velkých
přenosech. Oprava patří do navazujícího vydání.

## Ověření vydání

Bitově shodný self-host fixed point, plná testovací sada včetně endurance
konformance, porovnání configu a kontrola release ELF prošly. Compiler má
SHA-256 `3fd701c3c850ec94ae9c7944b359ccea55038883968e3146edaab49b63bca837`,
CLI `07f13c9331cf3f57e8813d0b2decaa3204e956340f23c337ca7da7b7e039305b` a
test runner
`1117f3d14be4a5d7dff251774fb8baa9739d850abeda37d3e5b13003f7a9a81d`.
