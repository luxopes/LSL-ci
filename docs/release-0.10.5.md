# Release LSL 0.10.5 (připravuje se)

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
- Nové testy `memory_footprint_conformance` a `memory_release_conformance`
  (jen Linux, mimo emulaci).
