# Release LSL 0.8.4

Vydání zaměřené na automatickou správu paměti a výkon dlouhoběžících programů.
Compiler i host runtime zůstávají pure LSL.
Compiler navíc uklízí dočasné struktury na hranicích překladových fází
a po dávkách dokončených funkcí, aby velký self-host build nedržel všechny
nepotřebné mezivýsledky až do konce.

## Automatický úklid

Herní smyčka nemusí volat `gc()`. Alokátor počítá alokované bajty včetně
znovu použitých bloků a režie; compiler vkládá kontroly na bezpečné hranice
příkazů a vyhodnocování podmínek. Po překročení rozpočtu následuje úklid.
Původní spouštění pouze při formátování Float nepokrývalo běžné herní smyčky.

Počáteční rozpočet je 4 MiB, po úklidu alespoň dvojnásobek živých bloků.
Nejde o limit RSS ani záruku maximální prodlevy: jediná operace může
alokovat více a úplný průchod heapem závisí na množství živých objektů.
Volné bloky se znovu používají; GC neslibuje okamžité vracení paměti OS.

Prokazatelně nealokující Int/Bool výrazy a typované číselné smyčky nemají
dodatečné GC kontroly. Ostatní cesty mají levnou kontrolu rozpočtu; registry
se ukládají až při skutečné potřebě úklidu. `gc()` nadále umožňuje výslovný
úklid a resetuje stejný rozpočet.

## Bezpečnost a vlákna

- Iterativní průchod grafu používá existující hlavičky bloků, nepotřebuje
  nový zásobník ani alokaci. Hluboká kolekce již nezruší celý úklid;
  cykly jsou podporované.
- Surové buffery kolekcí a I/O jsou odlišeny od jazykových objektů.
  Jejich obsah se nesmí vyhodnotit jako hlavička Listu ani native knihovny.
- Uchovávají se kořeny volajících, dočasné argumenty, výjimky a pozastavená
  vlákna. Rozpracovaný buffer ve workeru může bezpečně odložit uvolňování
  do dalšího úklidu; GC nikdy nesmí procházet neplatný datový ukazatel.
- Hlavní vlákno koordinuje GC a obsluhuje jej i během `thread_join()`.
  Samotný worker nesbírá; pokud hlavní vlákno zůstane v jiné dlouhé
  blokující operaci, úklid počká na jeho další bezpečný bod.
- Interní signál GC používá restart blokujících syscallů; `run()` a
  `capture()` opakují přerušené čekání na potomka. Úklid nemá způsobovat
  falešné chyby podprocesů.

Compiler nevkládá automatické kontroly dovnitř explicitního `unsafe`
bloku ani interních konstrukčních helperů. Unsafe kód musí udržovat
vlastní paměťové invarianty i přes volání běžných funkcí, které mohou
vyvolat úklid.

## Měření a ověření

Mediány pěti sériových běhů na stejném Ryzen 5 5500U, Linux x86_64.
Stejné zdroje přeložené compilerem 0.8.3 a 0.8.4; žádné ruční `gc()`.

| Test | 0.8.3 | 0.8.4 |
| --- | ---: | ---: |
| Snake: pohyb a renderer, 200 snímků | 4,172 s | 0,715 s |
| Snake: konečný RSS | 668 276 KiB | 5 956 KiB |
| Int smyčka, 100 000 000 iterací | 0,2541 s | 0,2543 s |

Snake tak v tomto testu běží přibližně 5,8× rychleji; nejde o obecné
zrychlení všech programů. Měření zahrnuje `term.write` do `/dev/null`,
nikoli čekání na klávesnici, vykreslování terminálového emulátoru nebo
časování snímků. Renderer ani herní pohyb nebyly pro nové vydání upraveny.
Checksum je u obou verzí 119 600, u číselné smyčky 4 799 999 352.

Dlouhý běh 10 000 snímků trval 32,143 s, měl konečný RSS 5 956 KiB
a checksum 5 980 000; prošel pod limitem 128 MiB virtuální paměti.
Reprodukce a metodika jsou v `tests/benchmarks/`.

Plná testovací sada prošla pod 4 GiB včetně skutečné GTX 1650,
fuzz/stress testů, instalátoru a updateru. Compiler stage 2/3 je bitově
shodný a veřejné nástroje se sestavují sériově pod 2 GiB. Herní testy
ověřují pohyb, růst, kolize, uvolněný ocas, jídlo, výhru a renderer;
interaktivní test ověřuje obnovení terminálu po Q, Ctrl+C i nárazu.

## Přechod

Aktualizujte LSL příkazem `lsl update` (u systémové instalace
`sudo /usr/local/bin/lsl update --system`). Zdrojové programy stačí znovu
spustit; samostatné binárky vytvořené příkazem `lsl compile` znovu přeložte,
protože mají runtime zabudovaný. Grafické knihovny zůstávají volitelnými
balíčky a kvůli této změně nevyžadují nové vydání.

Regrese jsou v `tests/automatic_gc_conformance.lsl`,
`tests/gc_raw_buffer_conformance.lsl`,
`tests/automatic_gc_threads_conformance.lsl` a
`tests/compiler/automatic_gc_codegen_conformance.lsl`.
