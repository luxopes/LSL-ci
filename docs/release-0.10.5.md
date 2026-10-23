# Release LSL 0.10.5

Rychlost a paměť: malé programy mají 136 kB místo 2,2 MB, běh je
o 3–10 % rychlejší, `lsl skript.lsl` startuje z cache za ~1 ms a démon
GTK/D-Bus v LSL má stejnou paměť jako tentýž program v C.

## Změny

- Paměť malých programů: bitmapa objektů (řídká mapa 4 MiB) se mapuje
  s `MADV_NOHUGEPAGE`; na jádrech s transparentními velkými stránkami
  „always“ (Arch/LuxOS, Debian) zabíral první dotyk 2 MiB fyzické paměti.
  Minimální program má 136 kB RSS místo 2,2 MB; démon GTK/D-Bus v LSL má
  stejnou anonymní paměť jako tentýž program v C (12,7 MB; Python 27,4 MB).
- GC vrací jádru stránky velkých volných bloků (od 32 KiB, `MADV_DONTNEED`
  při úklidu): po uvolnění velkých dat klesne RSS (40 × 1 MiB řetězců:
  50 MB → 1,5 MB po `gc()`; dříve zůstávalo 70 MB).
- `glib.main()` a `gtk.main()` přepnou `print` na přímý zápis, aby záznamy
  démona šly do roury nebo žurnálu hned; `glib.unbuffered()` nejdřív
  vyprázdní čekající výstup.
- Rozpočet GC mezi úklidy je nejméně 2 MiB místo 4 MiB (dál 3× živá data):
  halda malých programů zůstává v cache, běh je o 3–10 % rychlejší
  (allocation_gc −9 %, pfmt −10 %, list_access −10 %) a program s malou
  živou množinou drží o polovinu méně paměti (2,6 MB místo 4,9 MB).
- Cache přeložených skriptů: `lsl program.lsl` si přeložený program uloží
  do `$XDG_CACHE_HOME/lsl/programs` (jinak `~/.cache/lsl/programs`, 0700)
  a při dalším spuštění ho rovnou spustí (~2 ms místo ~110 ms). Klíčem je
  verze a otisk binárky `lsl`, cíl a cesta skriptu; manifest nese velikost
  a čas změny každého načteného zdroje (skript, standardní knihovna,
  moduly), změna kteréhokoli vede k novému překladu. `LSL_CACHE=0` cache
  vypne. Na Linuxu je otiskem velikost a čas změny souboru, na Windows
  a macOS otisk obsahu (FNV-1a), takže cache funguje na všech hostitelích.
- Start programu s mnoha řetězcovými literály je o 40 % levnější
  (literály se kopírují bez internovací tabulky a GC se zkouší jednou
  na konci; 3500 literálů 0,47 → 0,27 ms).
- Nové testy `memory_footprint_conformance` a `memory_release_conformance`
  (jen Linux, mimo emulaci).

## Ověření

- Celá sada testů, oba pevné body (překladač i backend LuxIR 0.4.1),
  bundly `linux-x86_64-gnu` (110 z 110) a WebAssembly (90 z 90), hello pro
  všech 11 cílů; nové testy `memory_footprint_conformance`,
  `memory_release_conformance` a `cli_cache_conformance`.
- Výkon proti 0.10.4: generovaný kód programů je stejný až na inicializaci
  literálů; benchmarky běhu jsou rychlejší díky rozpočtu GC.
