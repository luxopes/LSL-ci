# LSL 0.7.6

LSL 0.7.6 opravuje kolaps alokátoru známý z vydání 0.7.5 jako
"gc+thread deadlock". Nebyl to deadlock: alokátor používal jediný volný
seznam s lineárním first-fit průchodem, takže po milionech malých
uvolněných bloků (např. boxované hodnoty z per-byte průchodu 9 MiB HTTP
body) každá další alokace prohledávala celý seznam s drženým heap mutexem.
Hlavní vlákno se točilo, worker čekal na mutexu a proces vypadal zamrzle.

## Hlavní změny

- Alokátor přechází na 136 segregovaných volných seznamů: velikosti do
  1024 bytů mají přesné 8bytové biny (hlava binu vždy přesně padne),
  velikosti 1 KiB–1 MiB se zaokrouhlují na strop své třídy
  (2K/4K/8K/16K/64K/256K/1M), takže i tam platí exact fit a dokonalé
  znovupoužití; pouze neomezená nejvyšší třída zůstává first-fit
  s omezeným probe budgetem. Alokace je O(1) místo O(počtu volných bloků).
- Hlavy seznamů žijí ve state bloku na ofsetech 192..1279; programové
  globály se posunuly na 1280+. Hlavy nejsou GC roots.
- Reprodukce z 0.7.5 (`tests/known_issues/`) je povýšena na řádnou
  konformanci `tests/gc_bigheap_threads_conformance.lsl`: 9 MiB round-trip
  přes vláknový listener následovaný main-thread serve smyčkou s gc() nyní
  doběhne v sekundách.
- Endurance profil: smíšená alokační smyčka s gc() po 100 iteracích drží
  VmRSS ploché (28,7 MB přes 40 000 iterací). Stejný program na 0.7.5
  nedoběhl 40 000 iterací ani za 10 minut kvůli lineárním průchodům.

## Kompatibilita

Zaokrouhlení na strop třídy zvyšuje vnitřní fragmentaci objektů mezi 1 KiB
a 1 MiB nejvýše na dvojnásobek požadované velikosti; objekty nad 1 MiB se
nezaokrouhlují. Sémantika programů se nemění.

## Ověření vydání

Bitově shodný self-host fixed point, plná testovací sada (včetně nové
gc-bigheap konformance, HTTP endurance a split konformance), porovnání
configu a kontrola release ELF prošly. Compiler má SHA-256
`828f1b56cc4020e3c850ce29aa129fc7c3ba2198ea008b333dbab10bd597e776`, CLI
`ebc29e380ad01880bd09337e35dd2d63204d0cd59d9ae1437ad9a7c02437ae0f` a test
runner `d613672eb70c905c4c2ea912e54b3ecaf242e757dfc9559c15d1c6ebb647a31a`.
