# LSL TODO

Přesný průběžný stav, hashe a důkazy jsou v `PURE_LSL_PROGRESS.md`. Aktuální handoff, pořadí blockerů a ověřovací příkazy jsou v `COMPLETION_PLAN.md`.

## Otevřené nálezy auditu release 0.9.1 — 11. 10. 2026

Ověřeno na tagu `v0.9.1`, commit `0928f4798a2245813f25711d50ea50577da90ade`.
Reprodukce, výstupy a příčiny: [audit/0.9.1/LSL-0.9.1-audit.md](audit/0.9.1/LSL-0.9.1-audit.md).
P1/P2 zde označuje prioritu auditu. Nálezy nejsou automaticky regrese zavedené v 0.9.1.
Obecné Int operace mají wrap modulo 2^64; položky gcd/lcm požadují vyjasnit a kontrolovat rozsah matematického API.

- [ ] **AUD-091-01 (P1): Rozbalování přepisuje dosud nepřečtené hodnoty.** `compiler/pure/parser.lsl:307`. unpack_statements čte holder[index] až při zápisu do jednotlivých cílů. Nejdřív zachytit všechny prvky do dočasných hodnot.
  Reprodukce: `audit/0.9.1/alias_unpack.lsl`. Očekáváno: [2, 1].
- [ ] **AUD-091-02 (P1): Nepřesný decimal → Float.** `compiler/pure/dynamic_stdlib.lsl:1117`. Známá chyba převodu decimal do binary64, stále v 0.9.1. Float("0.49999999999999994") chybně vrací přesně 0.5. Použít správně zaokrouhlený parser. Nejde o nově objevenou regresi.
  Reprodukce: `audit/0.9.1/float_boundary.lsl`. Očekáváno: False. Další závažné projevy téže chyby: `float_long_fraction.lsl` vrací NaN pro číslo přesně 1; `float_long_mantissa.lsl` vrací inf pro číslo přesně 1; JSON parser pak odmítá platný konečný token (`json_long_float.lsl`).
- [ ] **AUD-091-03 (P2): Overflow počtu desetinných míst Float.** `stdlib/math.lsl:73`. point + places přeteče. Totéž math.trunc. Kontrolovat mezní digits před součtem; dostatečně velký kladný počet míst má ponechat číslo.
  Reprodukce: `audit/0.9.1/round_float_digits_max.lsl`. Očekáváno: 1.5.
- [ ] **AUD-091-04 (P2): Overflow negace digits Int.MIN.** `stdlib/math.lsl:122`. -places přeteče pro -9223372036854775808; rang pak nemá průchody a jednotka zůstane 1. Explicitně ošetřit dolní mez. Float varianta s 0.015 také chybně ponechá číslo kvůli součtu.
  Reprodukce: `audit/0.9.1/round_int_digits_min.lsl`. Očekáváno: 0.
- [ ] **AUD-091-05 (P2): round velkého Int na 10^19 tiše vrací nulu.** `stdlib/math.lsl:122`. Větev -places >= 19 ignoruje zaokrouhlení poloviny od nuly. Rozlišit -19 od menších places a zkontrolovat overflow.
  Reprodukce: `audit/0.9.1/round_int_overflow.lsl`. Očekáváno: Overflow/ValueError: výsledek 10000000000000000000 není Int64.
- [ ] **AUD-091-06 (P2): trunc odmítá reprezentovatelný výsledek pro Int.MIN.** `stdlib/math.lsl:122`. Paušální zákaz vstupu Int.MIN vyhodí chybu i když výsledek fits Int64. Pracovat se záporným zbytkem bez abs/negace MIN.
  Reprodukce: `audit/0.9.1/trunc_int_min.lsl`. Očekáváno: -9223372036854775800.
- [ ] **AUD-091-07 (P1): floor/ceil převádí příliš velký Float na nesmyslný záporný Int.** `stdlib/math.lsl:14,23`. floor(1e20) → -9223372036854775808, ceil → -9223372036854775807. Před Int(number) ověřit konečnost a rozsah jako check_integral.
  Reprodukce: `audit/0.9.1/floor_large.lsl`. Očekáváno: Chyba rozsahu; nikoli záporné číslo.
- [ ] **AUD-091-08 (P2): exp předčasně přetéká pro konečný výsledek.** `stdlib/math.lsl:305`. Pevná mez number > 709 je příliš nízká; exp(709.5) se vejde do Float64. Použít správné meze a škálování exponentu.
  Reprodukce: `audit/0.9.1/exp_finite.lsl`. Očekáváno: Přibližně 1.3549863193146328e308.
- [ ] **AUD-091-09 (P2): exp ztrácí reprezentovatelné subnormály.** `stdlib/math.lsl:305`. Pro záporné x nejdříve počítá exp(abs(x)), které přeteče, a pak 1/inf. Počítat záporný exponent přímo nebo bezpečně škálovat.
  Reprodukce: `audit/0.9.1/exp_subnormal.lsl`. Očekáváno: Přibližně 4.47628622567513e-309.
- [ ] **AUD-091-10 (P2): hypot má zbytečný overflow i underflow.** `stdlib/math.lsl:471`. hypot(1e200,1e200) → inf; hypot(1e-200,1e-200) → 0.0. Škálovat největší absolutní hodnotou před umocněním.
  Reprodukce: `audit/0.9.1/hypot_large.lsl`. Očekáváno: Přibližně 1.414213562373095e200.
- [ ] **AUD-091-11 (P1): is_close považuje NaN a různá nekonečna za blízká.** `stdlib/math.lsl:477`. NaN proti 1 → True; +inf proti 1 → True; +inf proti -inf → True. Ošetřit rovnost, NaN a inf před odečítáním a výpočtem tolerance. Základní Float porovnání NaN přitom v kontrolním testu funguje.
  Reprodukce: `audit/0.9.1/isclose_nan.lsl`. Očekáváno: False.
- [ ] **AUD-091-12 (P2): gcd může vrátit záporný výsledek.** `stdlib/math.lsl:253`. abs(Int.MIN) zůstane záporné kvůli wrap Int64. Funkce pak vrací záporné gcd. Ošetřit overflow kladného výsledku.
  Reprodukce: `audit/0.9.1/gcd_min.lsl`. Očekáváno: Chyba rozsahu nebo BigInt 9223372036854775808.
- [ ] **AUD-091-13 (P2): lcm tiše vrací nesprávný výsledek po overflow.** `stdlib/math.lsl:264`. lcm(Int.MAX,2) → 2. Int operace mají dokumentovaný wrap, ale matematické API tak vrací nesprávné lcm bez indikace; přidat kontrolu rozsahu jako factorial.
  Reprodukce: `audit/0.9.1/lcm_overflow.lsl`. Očekáváno: Chyba rozsahu nebo BigInt 18446744073709551614.
- [ ] **AUD-091-14 (P2): mean a median přetékají na konečných výsledcích.** `stdlib/math.lsl:485,513`. mean([1e308,1e308]) a median stejného seznamu → inf. Mezisoučet přeteče, i když výsledná hodnota je konečná. Bezpečný průměr a škálované sčítání.
  Reprodukce: `audit/0.9.1/mean_large.lsl`. Očekáváno: 1e308.
- [ ] **AUD-091-15 (P2): sin vrací NaN pro konečný platný argument.** `stdlib/math.lsl:383`. Redukce úhlu převádí počet otoček do Int64 přes floor. Pro 1e20 je mimo rozsah; výsledný úhel rozbije Taylorovu řadu. Nutná redukce pro velké Float argumenty nebo explicitní zdokumentovaná chyba rozsahu.
  Reprodukce: `audit/0.9.1/sin_large.lsl`. Očekáváno: Přibližně -0.6452512852657808.
- [ ] **AUD-091-16 (P2): Čas odmítá zlomek poslední sekundy roku 9999.** `stdlib/time.lsl:41`. Horní mez 253402300799.0 vylučuje poslední téměř celou sekundu. Kontrolovat rozsah do začátku roku 10000 (exkluzivně) a ošetřit zaokrouhlení.
  Reprodukce: `audit/0.9.1/time_last_fraction.lsl`. Očekáváno: 9999-12-31T23:59:59.500000+00:00.
- [ ] **AUD-091-17 (P2): HTTP odmítá platný znak tečka v názvu hlavičky.** `stdlib/httpserver.lsl:190`. X.Test: ok → HTTP 400. Implementovat token/tchar podle RFC 9110 §5.1 a §5.6.2; tečka je dokonce doporučená pro interoperabilní nové názvy.
  Reprodukce: `audit/0.9.1/http_probe.lsl`; skutečné HTTP odpovědi: `http_results.json`.
- [ ] **AUD-091-18 (P1): HTTP ponechá nepovolený CR uvnitř hodnoty hlavičky.** `stdlib/httpserver.lsl:336`. X-Test: one\rtwo je přijat s HTTP 200 a původní hodnota je předána handleru. RFC 9110 §5.5 vyžaduje odmítnutí nebo nahrazení CR/LF/NUL. Ověřit každý field-value po rozdělení CRLF. Test prokazuje parser mismatch; neprokazuje zneužití za konkrétní proxy.
  Reprodukce: `audit/0.9.1/http_probe.lsl`; skutečné HTTP odpovědi: `http_results.json`.
- [ ] **AUD-091-19 (P1): HTTP posílá tělo u odpovědí, které tělo mít nesmějí.** `stdlib/httpserver.lsl:556`. Reálný socket dostal BADBODY pro 204 i 304; 204 má Content-Length: 7. RFC 9110 §15.3.5, §15.4.5 a §8.6. Centralizovat pravidla framingu pro jednotlivé statusy i stream.
  Reprodukce: `audit/0.9.1/http_probe.lsl`; skutečné HTTP odpovědi: `http_results.json`.
- [ ] **AUD-091-20 (P2): Ověřovací nástroje nefungují z čistého release checkoutu.** `tools/qbe/verify_image.py:64; tools/qbe/verify.py:118`. verify_image.py padá před první kontrolou na build/qbe/runtime.o; skutečný runtime je compiler/qbe/runtime.o. verify.py má stejnou pevnou závislost na konci (statické potvrzení, v tomto auditu znovu celý neproběhl). Přidat explicitní runtime parametr nebo odvodit release cestu.
  Důkaz: `audit/0.9.1/verify_image.stderr`; v `verify.py` stejná pevná cesta potvrzena čtením zdroje.

- [ ] **AUD-091-21 (P2): BigInt přijímá nekánonický nulový stav.** `stdlib/bigint.lsl:80`. Konstruktor přijme {"sign":0,"digits":"5"}; text() je 0 a is_zero() True, ale absolute().text() je 5. Zkontrolovat invariant reprezentace v _parts.
  Reprodukce: `audit/0.9.1/bigint_zero_sign.lsl`. Očekáváno: Odmítnout sign=0 s digits!=0 nebo normalizovat digits na 0.
- [ ] **AUD-091-22 (P2): JSON odmítá platný výstup přesně na hranici 4 MiB.** `stdlib/json.lsl:99`. Bool větev odečte 5 bajtů ještě před rozlišením true/false a true refunduje až poté. ["x"*4194295,True] má přesně 4194304 bajtů, ale je odmítnut; kontrolní stejně dlouhý JSON s False projde. Odečítat skutečnou délku tokenu.
  Reprodukce: `audit/0.9.1/json_exact_limit.lsl`. Očekáváno: Délka zakódovaného JSON 4194304.
- [ ] **AUD-091-23 (P1): printr obchází zákaz I/O v čisté konfiguraci.** `stdlib/configure.lsl:180`. lsl config vypíše UNEXPECTED-OUTPUT před JSON a vrátí exit 0. Nové printr chybí v zakázaných identifikátorech; synchronizovat pravidla pro všechny výstupní builtin funkce.
  Reprodukce: `audit/0.9.1/config_printr.lsl`. Očekáváno: Staticky odmítnout stejně jako print.
- [ ] **AUD-091-24 (P1): Čistá konfigurace přijímá ambientní hodiny a CPU vstup.** `stdlib/configure.lsl:180`. monotonic() vrátí hostitelský čas v JSON; cpu_count() také projde. Doplnit purity kontrolu podle kategorií builtinů, ne pouze historického seznamu jmen.
  Reprodukce: `audit/0.9.1/config_monotonic.lsl`. Očekáváno: Odmítnout ambientní vstupy podle docs/configuration.md a docs/time.md.
- [ ] **AUD-091-25 (P2): Konfigurační lexer neignoruje blokové komentáře.** `stdlib/configure.lsl:28`. /* readfile("not-executed") */ chybně skončí Impure configuration identifier readfile. Sdílet lexer jazyka nebo podporovat blokové komentáře.
  Reprodukce: `audit/0.9.1/config_block_comment.lsl`. Očekáváno: Přijmout čistou konfiguraci s komentářem.
- [ ] **AUD-091-26 (P2): Konfigurační lexer odmítá validní escaped a raw stringy.** `stdlib/configure.lsl:28`. "a\"b" je odmítnuto jako Unterminated configuration string. Kontrola konce stringu ignoruje stav escaped. Také validní raw string s koncovým backslashem odmítá; zachovat odlišnou raw sémantiku.
  Reprodukce: `audit/0.9.1/config_escaped_quote.lsl`. Očekáváno: Přijmout validní řetězec obsahující escaped quote.
- [ ] **AUD-091-27 (P1): Tabulátor vypne options i assertions; komentář vytváří falešný export.** `stdlib/configure.lsl:295`. has_export hledá substring name + " =" nebo name + "=". options/assertions s tabulátorem před = se tiše ignorují: nepravdivá assertion i missing required option skončí exit 0 s {}. Naopak # options = v komentáři vyvolá chybu neexistující proměnné. Odvozovat exporty z tokenů/AST.
  Reprodukce: `audit/0.9.1/config_assertions_tab.lsl`. Očekáváno: Nepravdivá assertion musí skončit chybou; chybějící required option také.
- [ ] **AUD-091-28 (P2): Float options odmítají skutečný Float.** `stdlib/configure.lsl, generované dynamic_type`. dynamic_type neobsahuje typový kód 6 (Float), proto je hodnota 1.5 označena Any a Float option/default odmítnut. Doplnit Float i regresi pro Float|None.
  Reprodukce: `audit/0.9.1/config_float_option.lsl`. Očekáváno: Přijmout Float 1.5 a výchozí Float hodnotu.
- [ ] **AUD-091-29 (P2): Sentinel pro chybějící option koliduje s platnou Dictionary hodnotou.** `stdlib/configure.lsl, missing sentinel a get_path`. Required Dictionary option s touto hodnotou skončí Missing required option. Porovnání používá strukturální == na běžném Dictionary sentinelu. Vrátit existenci zvlášť nebo použít nezaměnitelnou identitu.
  Reprodukce: `audit/0.9.1/config_missing_sentinel.lsl`. Očekáváno: Přijmout existující Dictionary hodnotu {"__missing":True}.
- [ ] **AUD-091-30 (P2): mkIf(False, ...) v List nevynechá položku.** `stdlib/configure.lsl, materialize List větev`. Výsledek je {"items":[1,{"__omit":true},3]}; interní omit marker uniká do uživatelského JSON. Stejnou filtraci jako u Dictionary použít i pro List, nebo výslovně omezit a zdokumentovat kontrakt mkIf.
  Reprodukce: `audit/0.9.1/config_list_omit.lsl`. Očekáváno: {"items":[1,3]}.
- [ ] **AUD-091-31 (P1): Průchod String a validace dlouhých řetězců mají kvadratický čas.** `compiler/pure/heap_runtime_linux_x86_64.lsl:2270,2309; stdlib/lconf.lsl:11`. 10k/20k/40k ASCII znaků: for c in x 0.146/0.591/2.273 s; lconf.valid_dependency 0.307/1.232/4.887 s. Byte kontrola 40k znaků 0.0012 s, 1 MiB 0.0122 s. String index volá runtime_length a znovu hledá znak od počátku. Iterovat byte offsetem s UTF-8 dekódováním a cache délky; zachovat Unicode sémantiku. lconf.encode pro 1MiB jméno překročilo 20s limit; to není důkaz chyby formátu.
  Reprodukce: `audit/0.9.1/string_iteration_performance.lsl`. Očekáváno: Lineární postup po UTF-8 codepointech, nikoli opakované procházení prefixu.
- [ ] **AUD-091-32 (P1): HTTP request-line přijímá neplatnou metodu i control znak v targetu.** `stdlib/httpserver.lsl:336`. Metoda G\tET i target /one\rtwo jsou přijaty s 200 a nezměněné předány handleru. Validovat method token a request-target podle RFC 9112 §3.1/3.2. Nejde o pouhou toleranci whitespace oddělovačů: znak zůstává uvnitř komponenty.
  Reprodukce: `audit/0.9.1/http_request_line.lsl`. Očekáváno: Odmítnout invalid request-line před zavoláním handleru.
- [ ] **AUD-091-33 (P1): Merge List/Dictionary ztrácí prioritu mkForce/mkDefault.** `stdlib/configure.lsl, deep_merge`. Sloučení dvou wrapperů stejné priority vrátí holý List/Dictionary (priorita se změní na 500). Výsledek force scénáře [1,2,3]; tři mkDefault seznamy dají [1,2] místo [1,2,3]. Uchovat obal s původní prioritou ve výsledku merge.
  Reprodukce: `audit/0.9.1/config_priority_force/main.lsl`. Očekáváno: Po dvou mkForce([1])/mkForce([2]) obyčejná [3] nesmí vyhrát: [1,2].
- [ ] **AUD-091-34 (P2): Chybný default option se nekontroluje, je-li hodnota explicitně zadána.** `stdlib/configure.lsl, option validation wrapper`. config.option("Int","bad default",...) s config.port=123 projde. Default se typově kontroluje pouze při chybějící hodnotě. Validovat descriptor/default nezávisle na výsledném stromu.
  Reprodukce: `audit/0.9.1/config_invalid_default.lsl`. Očekáváno: Odmítnout String default pro Int option podle dokumentovaného kontraktu.

- [ ] **AUD-091-C01 (kontrakt):** Sjednotit nebo zdokumentovat rozdílný UTC rozsah `time.parse_iso8601` a `time.iso8601`: parser přijme `0001-01-01T00:00:00+01:00`, formatter vzniklý čas odmítne. Reprodukce `audit/0.9.1/time_parse_range.lsl`. Nezapočteno mezi potvrzené chyby.

## Vydání 0.9.0 BETA a návazný plán — 11. 10. 2026

Rozsah 0.9.0 BETA je Linux x86_64 s novým backendem odvozeným od QBE,
implementovaným v LSL. Další operační systémy a architektury nejsou součástí
ověřeného rozsahu této BETA. Výsledné release binárky, hashe a provedené
ověřovací kroky musí dokládat příslušný release report; tento plán nepředjímá
výsledky dosud neprovedených testů ani publikaci artefaktů.

Všechny níže neuzavřené požadavky a nahlášené chyby jsou explicitně plánované
pro **0.9.1**. Původní popisy, reprodukce a workaroundy z main 0.8.9 jsou
zachovány; přepis backendu sám o sobě není důkazem opravy každého hlášení.
Zvláště provozní hlášení poškození SSE při souběhu workeru a `gc()` zůstává
otevřené do ověření konkrétního scénáře, i když nový backend obsahuje opravy
vláknového GC. Historické dokončené položky a starší měření níže se vztahují
k uvedeným starším verzím.

Samostatný web a manuály mají jediný zdroj v
[LuxAI/LSL-Web](https://git.lux-ai.cz/LuxAI/LSL-Web). Oddělení obsahu a lokální
atomický deployer jsou dokončené; produkční hosting čeká na provozní údaje.
Podepsaný stabilní kanál 0.8.9 zůstává zachován vedle 0.9.0 BETA.

- [x] **0.9.1:** Reprodukovatelné diagnostické cesty importů stdlib: CLI, instalátor a test runner nyní obsahují absolutní cesty build adresáře. Frontend a backend mají bitově shodný self-host i po přemístění; sjednotit source mapping také pro ostatní nástroje.
  Stav 0.9.1: cesty ke zdrojům stdlib, compiler/pure a extensions se v binárce zkracují na relativní; CLI přeložené z jiného adresáře s absolutní cestou je bajtově shodné.

## Hotovo v 0.8.6 — 27. 9. 2026

- [x] Více importů na jednom řádku: `load term, time`.
- [x] Společný alias pro všechny knihovny na řádku: `load term, time as a`;
  člen se hledá v uvedených knihovnách v pořadí.
- [x] Stejné uvozovky uvnitř interpolace l-stringu bez escapování:
  `l"{"a" * x}"`, včetně vnoření a chybových případů (regresní testy).
- [x] Interaktivní `lsl`: zvýrazňování syntaxe, historie, barevné prompty
  `>>>`/`...` s automatickým odsazením bloků.
- [x] `lsl --tui [SOUBOR]`: terminálový editor ve stylu Vimu se zvýrazňováním.
- [x] Průběh v procentech při instalaci (`lsl-install`) i aktualizaci
  (`lsl update`: stahování i instalace).
- [x] `lsl man` formátuje Markdown (nadpisy, seznamy, kódové bloky, tabulky,
  inline kód, odkazy) v terminálovém prohlížeči i v `--plain` režimu.
- [x] `lsl about [KNIHOVNA]` a about text knihoven v `help("knihovna")`;
  registrové balíčky se popisují úvodním komentářem zdroje.

## Opraveno v 0.8.4 — 22. 9. 2026

- [x] Automatický GC i bez formátování Float a bez ručního `gc()` ve hře.
- [x] Byte-pressure rozpočet, reuse a vynechání kontrol v čistých číselných smyčkách.
- [x] Iterativní průchod hlubokých/cyklických grafů a rozlišení raw bufferů.
- [x] Kořeny callbacků/výjimek, GC během join a odolné čekání na podprocesy.

## Opraveno v 0.8.3 — 21. 9. 2026

- [x] Memory safety: čtení lokální proměnné před přiřazením vracelo obsah
  neinicializovaného slotu, u referencí včetně pádu SIGSEGV. Doplněna statická
  definite-assignment kontrola pro větve, smyčky, výjimky a opětovné použití
  slotů; také ochrana globálů a nekolidující interní jména.
- [x] Srozumitelná diagnostika chybějících importů a X11 backpressure (-11).
- [x] Typové deklarace, inkrement/dekrement, builtin system a čitelný clock.
- [x] Bitově shodný self-host build a úplná sada včetně hardwarové CUDA regrese
  na GTX 1650; release binárky přegenerované.

## Dokončený audit 0.7.1

- [x] Auditovat nové hranice 0.7: HTTP/HTTPS, sandbox, provenance a safe/unsafe.
- [x] Opravit nalezené chyby a ke každé přidat cílenou regresi.
- [x] Znovu projít compiler/runtime, procesy, filesystem a paměťové ABI.
- [x] Povýšit 0.7.1-dev na release; fixed point, full suite, čistá instalace,
  installed fixed point, config a ELF audit už prošly.

## Hotovo

- 0.7.7: persistentní CUDA session, device buffery, dense Float64 operace,
  DeviceTensor, CPU fallback, device selection, protokol a hardwarové regrese.

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

## Aktivní plán 0.9.1

- [x] **0.9.1:** Zpřesnit statickou kontrolu přiřazení pro prokazatelně neprázdné
  smyčky, aby přijala čtení proměnné po smyčce, pokud přiřazení proběhne
  na každé cestě vedoucí k tomuto čtení. Bez dodatečných běhových kontrol
  a bez automatické inicializace nulou či `None`. Analýzu omezit na bezpečně
  prokazatelné případy; zohlednit `break`, `continue`, větvení, změny kolekce
  přes aliasy i vedlejší účinky volání. Pokud důkaz chybí, zachovat současné
  odmítnutí. Doplnit pozitivní i negativní regrese (včetně prázdných či
  vyprázdněných kolekcí) a změřit dopad na čas a paměť překladu; ověřit,
  že nevzniká dodatečná běhová režie ani oslabení paměťové bezpečnosti.
  Stav 0.9.1: smyčky přes literálně neprázdné `rang`, List/Tuple/RealArray a String; `break`/`continue` se slučují konzervativně. Dopad na čas překladu nebyl samostatně měřen (sada testů beze změny délky běhu).
- [x] **0.9.1:** FIX: Opravit zdrojové pozice diagnostiky výrazů v interpolacích.
  Reprodukce v 0.8.9: E2002 při čtení `chyba` v
  `printl "Epocha: {epocha} loss: {chyba}"` nesprávně ukazuje na první
  řádek `load random`. Chyba musí označit skutečné použití `chyba`
  v původním souboru, se správným řádkem a sloupcem. Zachovat původní
  pozice při parsování interpolovaných výrazů a doplnit regresní testy
  pro `printl`, l-stringy a importované moduly.
  Stav 0.9.1: hotovo včetně l-stringů s escape sekvencemi a importovaných modulů; regrese v `tests/compiler/language_091_negative.lsl`.
- [x] **0.9.1:** Opravit čítače vnořených `for` smyček se stejným jménem proměnné:
  oddělit interní stav iterace od uživatelské proměnné, aby vnitřní `for i`
  neměnil počet iterací vnějšího `for i` ani nezpůsoboval zacyklení.
  Reprodukce v 0.8.9: vnější `rang(3)` s vnitřním `rang(2)` provede jen
  jednu vnější iteraci místo tří; kombinace `rang(100)` / `rang(10)` se
  zacyklí. Doplnit regrese pro oba případy, přiřazení do proměnné v těle,
  `break` a `continue`.
  Stav 0.9.1: hotovo; nezávislý interní čítač, regrese v `language_091_conformance`.
- [x] **0.9.1:** Sjednotit výpisy běhových chyb s obvyklým formátem diagnostiky LSL.
  Místo holého `LSL runtime error: TypeError: sequence index must be Int`
  zobrazit `error[...]`, typ a srozumitelný popis chyby, soubor, řádek,
  sloupec, příslušný zdrojový kód s označením chybného výrazu a vhodné
  `help:` s návodem k opravě; u typových chyb uvést očekávaný i skutečný typ.
  Zachovat správné zdrojové pozice včetně interpolací, funkcí a importů,
  barevný výstup dle stávajících pravidel terminálu a `NO_COLOR`.
  Pokrýt běh přes `lsl` i samostatné zkompilované binárky regresními testy;
  zachycené chyby v `try`/`safe` nesmí samovolně vypisovat diagnostiku.
  Stav 0.9.1: formát `error[Druh]`, pozice, zdrojový řádek (jen z `.lsl`, kvůli tajemstvím v `.env`), help a barvy podle NO_COLOR/FORCE_COLOR. Očekávaný a skutečný typ zatím uvádějí jen některé hlášky runtime.
- [x] **0.9.1:** Přidat výchozí hodnoty parametrů uživatelských funkcí po vzoru Pythonu,
  například `function f(x = 10):`. Vynechaný argument použije deklarovanou
  výchozí hodnotu, explicitně předaný argument ji nahradí. Doplnit pravidla
  pro povinné/volitelné parametry, dokumentaci a regresní testy.
  Stav 0.9.1: ověřeno, že funguje již v 0.9.0.
- [x] **0.9.1:** Opravit hlášené chování `help("nonexist")`: neexistující téma má vypsat
  srozumitelnou anglickou zprávu, například `No help available for topic: nonexist.`,
  nikoli vyvolat chybu či ukončit program. Zachovat `help()` i známá témata
  a pokrýt všechny tyto případy regresními testy.
  Stav 0.9.1: hotovo; `lsl help neexistuje` vypíše zprávu na stderr a skončí stavem 1.
- [x] **0.9.1:** Doplnit volitelný druhý argument `Dictionary.get(key, default=None)`
  po vzoru Pythonu. `.get(key)` vrátí existující hodnotu, při chybějícím klíči
  `None`; `.get(key, default)` místo toho vrátí zadanou výchozí hodnotu.
  Odstranit hlášené selhání při jednom argumentu; nesprávný počet argumentů
  musí mít srozumitelnou diagnostiku, nikdy pád runtime. Přidat dokumentaci
  a regrese včetně uložených hodnot `None`, `False` a `0`.
  Stav 0.9.1: ověřeno, že funguje již v 0.9.0.
- [x] **0.9.1:** Pro další vydání doplnit rozbalování položek v běžném `for`, například
  `for x, target in data:` pro seznam dvojic. V LSL 0.8.9 tento zápis končí
  E1210 (`expected in after loop variable`), přestože comprehensions
  rozbalování podporují. Sjednotit chování, přidat srozumitelnou chybu při
  nesprávném počtu hodnot, dokumentaci a regresní testy včetně uvedené
  vnořené trénovací smyčky s výpočty Int/Float.
  Stav 0.9.1: hotovo (`for a, b in ...`, E1209 pro duplicitní jména, ValueError při jiné délce).
- [x] **0.9.1:** Přidat raw řetězce `r"..."` (r-string) bez interpretace escape sekvencí,
  interpolace a jiných automatických úprav. Doplnit `printr` pro výpis
  přesného obsahu bez přidaného odřádkování či oddělovačů; popsat syntaxi
  v dokumentaci a ověřit chování regresními testy.
  Stav 0.9.1: hotovo (`r"..."`, `r'...'`, `printr`).
- [x] **0.9.1:** Přidat podporu blokových komentářů `/* ... */`, včetně více řádků,
  diagnostiky neukončeného komentáře, dokumentace a regresních testů.
  Stav 0.9.1: hotovo (E0011 pro neukončený komentář).
- [x] **0.9.1:** Umožnit zaokrouhlit a oseknout (truncate) počet desetinných míst
  u Float. Dnes `math.round` vrací jen celé číslo a žádný přímý zápis pro
  počet míst neexistuje; běžné formátování typu „{x:.2f}" v LSL chybí.
  Cíl: jeden srozumitelný mechanismus (např. `round(x, digits)` a/nebo
  přesnost v interpolaci) s jasně definovanou sémantikou — matematické
  zaokrouhlování včetně záporných čísel a polovin a odděleně oseknutí
  bez zaokrouhlování; podpora záporného počtu míst (desítky, stovky),
  `digits = 0`, neceločíselného či jinak neplatného počtu míst
  s srozumitelnou diagnostikou a chování pro NaN/Infinity. Doplnit
  dokumentaci a regresní testy včetně interakce s Float formátováním.
  Stav 0.9.1: `math.round/trunc(x, digits)` na desetinném zápisu, záporné digits, Int zůstává Int, NaN/Infinity bez digits ValueError.
- [x] **0.9.1:** Zpřístupnit opravené streamování z `aikit` také v instalované nativní
  knihovně přes `load ai`. Vyřešit přednost vestavěného modulu tak, aby šlo
  používat `lsl update ai` bez aktualizace celého LSL a bez aliasu
  `load aikit as ai`. Spolu s knihovnou aktualizovat `lsl man ai`; ověřit
  výběr správné verze, původ knihovny a kompatibilitu existujících skriptů.
  Stav 0.9.1: `load ai` použije novější `~/.local/lib/lsl/stdlib/aikit.lsl` (hlavička `# AI X.Y.Z`); `lsl install|update|origin ai` míří na balíček aikit; `lsl man --plain ai` vypíše aktivní knihovnu.
- [x] **0.9.0 BETA — oddělení zdrojů dokončeno:** Oddělit web a webové manuály (`docs/developer_guides` včetně index.html
  a man stránek knihoven) od samotného LSL do vlastního repozitáře s vlastním
  deployerem, aby šlo web aktualizovat nezávisle na commitech do LuxAI/LSL
  main a bez čekání na vydání kompilátoru. Dnešní stav: oprava manuálu
  (aikit 1.1.0, nový shell) vyžaduje commit do LuxAI/LSL; při aktivním
  vývoji mainu vznikají konflikty s přepsanou historií a `lsl man` stejně
  dostane nové stránky až s příštím vydáním, protože se kompilují do binárky.
  Cíl: webový obsah v samostatném repu (např. LuxAI/LSL-Web) s atomic deploy
  po vzoru lsl.lux-ai.cz, publikovaný z jeho main bez dotčení LuxAI/LSL;
  vydání LSL si man stránky přebírá z jediného zdroje (bez dvou kopií,
  které by se rozjely). Zachovat přesměrování, hlavičky a routovatelná
  jména stránek; po přesunu ověřit web, offline `lsl man` i instalaci
  balíčků z registru.
  Stav 11. 10. 2026: samostatný projekt
  [LuxAI/LSL-Web](https://git.lux-ai.cz/LuxAI/LSL-Web), obsah v `public/`,
  vlastní atomický deployer s rollbackem a připnutý zdroj offline manuálů.
  Původní přesměrování, hlavičky, stažené archivy a stabilní kanál 0.8.9
  jsou zachované. Dokončení oddělení zdrojů neznamená dokončené nasazení
  na produkční hosting: to čeká na přístupové a provozní údaje.
- [x] **0.9.1 / provozní dokončení webu:** Napojit vlastní main webového
  repozitáře na produkční hosting, nasadit atomický deploy a na živém webu
  ověřit routy, hlavičky, offline manuály a instalaci balíčků z registru.
  Zachovat podepsaný stabilní aktualizační kanál 0.8.9; BETA jej automaticky
  nenahrazuje. Tato produkční ověření zatím nejsou označena jako PASS.
  Stav 11. 10. 2026: web z LuxAI/LSL-Web main je nasazený na lux-server s automatickým atomickým deployem (timer `lux-lsl-deploy.timer`).
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
- [ ] **0.9.2:** Volitelně rozšířit syntetický fault injection na obtížně vyvolatelné fork/wait/read větve.
- [ ] **0.9.2:** BUG: převod desetinného textu na Float není správně
  zaokrouhlený (`__lsl_parse_float` sčítá číslice do Floatu a násobí po
  mocninách deseti). Fuzz 11. 10. 2026 proti Pythonu: 1 194 z 8 000 běžných
  sedmnáctimístných čísel a 1 462 z 3 115 náhodných doublů se načte o 1–2 ulp
  vedle (např. `0.49999999999999994` → `0.5`, `1.7976931348623157e308` →
  `…153e308`). Formátovač je s parserem konzistentní, LSL→LSL round-trip
  platí, výměna s jinými jazyky ne. Prototyp přesného převodu (velká čísla
  v čistém LSL, round-half-even, nejbližší nejkratší zápis) dal 0 neshod,
  ale byl 40× pomalejší (`String(Float)` 545 µs místo 12 µs), proto nebyl
  zařazen. Cíl: Eisel-Lemire s tabulkou 128bitových mocnin pěti
  a s rezervou přes velká čísla, stejný převod v nativním
  `runtime_float_candidate_bits`; regrese proti Pythonu a výkonový limit.
- [ ] **0.9.2:** Volitelný worker pool / vlákno na spojení pro `httpserver`,
  aby pomalý nebo streamovaný požadavek neblokoval další klienty.
- [ ] **0.9.2:** Doplnit do běhových typových chyb očekávaný i skutečný typ
  (např. `sequence index must be Int, got String`).
- [x] Ověřit 0.7.0 přes full suite, čistou instalaci, instalovaný fixed
  point, config, reálný loopback HTTP/HTTPS smoke test a audit generovaných ELF.
- [x] Povýšit 0.7.0 na release, reprodukovat binárky a vytvořit archivy, tag
  a webový manuál.
- [x] Doplnit valid-source frontend fuzz, strict JSON malformed/round-trip corpus, generativní config corpus a GC cycle/deep/reuse stress.
- [x] Změřit a zrychlit compiler bez změny deterministického výstupu; doplnit near-native IntArray/FloatArray kernely a packed ByteArray.

### Nahlášeno z provozu 2026-10-09 — LUX AGENTS (LSL 0.8.9), plán oprav 0.9.1

Kontext: agentní konzole (~3000 řádků LSL, HTTP server v produkci za Caddy
+ CDN), marketplace v LSL a pět sellerů; jazyk použit i na podepisované
kanonické JSON payloady. Všechny body níže jsou ověřené na 0.8.9; spustitelné
reprodukce jsou v `~/Downloads/lsl-bugreport/` (README.md + `*.lsl`), zde
jsou kvůli soběstačnosti uvedené i v tělech položek.

- [x] **0.9.1:** BUG: `httpserver` vrací 400 na **duplicitní request hlavičku**
  (`stdlib/httpserver.lsl:404-405`):
  Stav 0.9.1: opakované hlavičky se slučují čárkou (Cookie středníkem); Content-Length, Transfer-Encoding a Host dál 400; testy v `httpserver_conformance`.

  ```lsl
  if name in headers:
      return error_request(400, "Bad Request", "duplicate header: " + name)
  end
  ```

  Reprodukce (server s handlerem vracejícím 200):

  ```
  1) běžná žádost:                 200
  2) dva řádky Via:                400  duplicate header: via
  3) dva X-Forwarded-For:          400  duplicate header: x-forwarded-for
  ```

  Reálný dopad: za CDN + reverse proxy (WEDOS CDN → Caddy) dorazí `Via`
  dvakrát a konzole odmítala **všechny** requesty; workaround
  `header_up -Via` v Caddy. Stejně padá `X-Forwarded-For` s více skoky,
  `Accept-Encoding` od klienta i proxy apod. Podle RFC 9110 §5.2 se
  opakované field-lines slučují čárkou; tvrdě odmítat má smysl jen
  `Content-Length`, `Transfer-Encoding` a `Host` (request smuggling).
  Oprava: seznamové hlavičky sloučit `", "`, zmíněné tři dál odmítat.
  Pozor: duplicitu hlaviček dnes **nepokrývá žádný test**
  (`tests/http_security_conformance.lsl`, `tests/httpserver_conformance.lsl`),
  takže chování nejspíš není zamýšlené — doplnit conformance i negative test.

- [x] **0.9.1:** BUG: `json.encode` kazí Floaty (`stdlib/json.lsl`, `encode_value()`,
  větev `value_type == 6` → `__lsl_float_string(value)`). Dvě oddělené vady:
  Stav 0.9.1: ověřeno, že 0.9.0 už používá shortest round-trip a velké Floaty nekazí. Nový nález viz položka o převodu Float níže.

  ```
  String(1.0)      = 1.0                  <- správně (shortest round-trip)
  String(2.50)     = 2.5                  <- správně
  String(1e21)     = 1.0e+21              <- správně

  json.encode({"a":1.0,"b":2,"c":1e21,"d":0.1+0.2})
    = {"a":1.000000,"b":2,"c":-9223372036854775808.775808,"d":0.300000}
                         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ INT64_MIN
  Python: {"a": 1.0, "b": 2, "c": 1e+21, "d": 0.30000000000000004}
  ```

  1. Floaty se formátují na pevných 6 desetinných míst (`1.0 → 1.000000`,
     `1e15 → 1000000000000000.000000`) místo shortest round-trip jako
     `String()`; pro byte-shodnou serializaci s jiným jazykem (podepsané
     payloady, hashe, kanonická JSON) nepoužitelné — v marketplace jsem
     kvůli tomu psal vlastní kanonický encoder a čas bral ze SQLite
     `strftime`.
  2. Od ~`9.223e18` (2^63) vzniká z Floatu **INT64_MIN** místo čísla;
     round-trip pak ztrácí data i obrací znaménko:

     ```
     orig = 9.3e18
     encode: {"v":-9223372036854775808.775808}
     decode: {'v': -9.2233720368547768e+18}      <- jiná hodnota
     ```

  `json.decode` je v pořádku (zvládá `1.0`, `1e+21`, `3e-7` i velká celá
  čísla), takže jde o lokální opravu encoderu: použít formatter
  `String(Float)` a konverzi na Int64 ošetřit (nad 2^63 exponentový tvar
  nebo `JsonError`); nikdy nevypsat INT64_MIN. Doplnit regresi
  v `tests/json_fuzz_conformance` a round-trip test velkých Floatů.

- [x] **0.9.1:** CHOVÁNÍ: **tichý shadow globálu** — zápis do globálu z funkce se tiše
  neprovede (žádná chyba, žádné varování):
  Stav 0.9.1: `global x` a varování W2004 při zápisu bez deklarace.

  ```lsl
  counter = 1
  function bump():
      counter = 2        # vypadá jako zápis do globálu
      return counter
  end
  print(bump())          # 2
  print(counter)         # 1  <- globál se nezměnil
  ```

  Při čtení před přiřazením compiler chybu hlásí správně
  (`error[E2002]: variable 'y' may be read before assignment`), takže
  polovina kontroly už existuje. Dopad: v konzoli mi tři hodiny tiše
  nefungovaly aktualizace stavu, než jsem na to přišel; náhrada je držet
  stav v holder dictu nebo `IntArray`. Návrh: buď explicitní deklarace pro
  zápis do vnějšího rozsahu (`global x`, případně `outer x`), nebo aspoň
  varování/chyba, když funkce přiřazuje jméno existujícího globálu
  (obdoba `-Wshadow`). Tichý no-op zápis je nejhorší varianta.

- [x] **0.9.1:** BUG (nepodařilo se zminimalizovat): `gc()` vedle běžícího workeru
  poškodil alokace **SSE parseru modelu**. Podle dokumentace
  (`docs/developer_guides/11-performance-and-optimization.md`, řádek ~593)
  je volání z hlavního vlákna bezpečné („zastaví workery přes `SIGUSR1`,
  projde jejich zásobníky a po sweepu je probudí"), v provozu to ale
  rozsypalo proud. Náhrada v kódu:
  Stav 0.9.1: na backendu LuxIR nereprodukováno (12×300 událostí přes capture_stream a 15×400 SSE událostí přes http.post_stream při ~30 000 voláních gc()); přidán test `tests/gc_stream_worker_conformance.lsl`. Příčina v 0.8.9 neověřena.

  ```lsl
  # chat_server.lsl:1260
  # gc() smí běžet jen bez aktivního pracovního vlákna: při běžícím tahu
  # poškodí alokace stream parseru modelu.
  if not busy_now():
      call gc()
  end
  ```

  Cesta v produkci: hlavní vlákno (accept loop) + worker, který čte odpověď
  modelu proudem (`http.post_stream` → curl podproces → `on_chunk` → parser
  v `stream_codec.lsl`). Minimální repro se nepovedlo (worker 400×
  `json.encode`+`decode` velkého dictu, hlavní vlákno 300× `gc()`:
  0 špatných výsledků) — podezření míří na kombinaci s **byte buffery,
  fd handles podprocesu nebo chunk callbacky** v druhém vlákně. Chce to
  cílený conformance test (`capture_stream` + `gc()` ve smyčce) a dohledat,
  co v root setu/registrech STW nezachytí; do té doby platí workaround výše.

- [x] **0.9.1:** DROBNOST: `IntArray(1)` končí hláškou
  `IntArray cast requires an existing IntArray`, která neřekne, co je
  špatně (správně `IntArray()` + `append`, viz
  `docs/developer_guides/04-collections.md:377`). Doplnit do chyby nápovědu.
  Stav 0.9.1: hláška radí `X()` a `append`.

- [x] **0.9.1:** PŘIDAT: **ISO-8601 / strftime v `time`** — modul má jen `time()`,
  `now()`, `monotonic()`, `perf_counter()`, `sleep()`. Kanonické časové
  značky (`2026-10-09T04:01:53.833305+00:00`) do podepsaného payloadu jsem
  musel vyrábět dotazem do SQLite (`strftime`).
  Stav 0.9.1: `time.utc`, `iso8601`, `strftime`, `parse_iso8601` (UTC).

- [x] **0.9.1:** PŘIDAT: **streamovaná odpověď v `httpserver`** — odpovědi se bufferují
  (`Content-Length` + `close`), takže nelze poslat SSE. Kvůli tomu LSL port
  marketplace vypustil relay průběhu sellerů (konzole zobrazí až hotový
  job). Stačil by write handle / chunked režim.
  Stav 0.9.1: `stream` v odpovědi handleru, `stream_write`, `sse_event`; chunked pro HTTP/1.1.

- [x] **0.9.1:** ROBUSTNOST: **zámek přežije výjimku** — `lock()`/`unlock()` nad
  `IntArray` uvolní zámek jen explicitně, takže výjimka mezi nimi drží
  spinlock navždy (v provozu tvrdý hang celé konzole na ~48 % CPU, dokud
  jsem to nenašel). Bloková konstrukce (`lock x: … end`) nebo automatické
  uvolnění při zániku vlákna by to řešily. Navazující přání: **viditelná
  diagnostika, když workeři umře výjimka** — tichý zánik vlákna se ladí
  velmi těžko.
  Stav 0.9.1: blok `lock zamek[, slot]: ... end` a hlášení `LSL worker error: ...` při pádu vlákna.

- [x] **0.9.1:** DOKUMENTACE/DEPLOY: přepsání běžící binárky končí `ETXTBSY`;
  řeším `stop → kopie → start`. Není to chyba jazyka, ale pár řádků
  v dokumentaci (nebo `lsl deploy` s atomickým replace) by ušetřilo
  překvapení. Zároveň: accept loop `httpserveru` je jednovláknový
  (dokumentováno) — jeden pomalý request zdrží ostatní a klienti musí
  volat sekvenčně; volitelný worker pool / per-connection vlákno by
  serializaci frontendu odstranily.
  Stav 0.9.1: atomická výměna popsána v kapitole 13 webu. Worker pool pro httpserver zůstává otevřený (0.9.2).

- Co naopak funguje a nestojí za „opravu": diagnostika compileru
  (`E2002` včetně `help:`), moduly a nativní kompilace, HTTP klient přes
  curl včetně `post_stream`/`on_chunk` a přenosu binárních dat přes
  `curl -o`, hardening `httpserveru` (limit 16 KiB, folded hlavičky,
  validace `Content-Length`), `sqlite` 1.0.0 v produkci jako nezávislá
  kontrola ledgeru, GC i alokátor pod tisícovkami requestů.

- Nabídka: k prvním dvěma bodům (duplicitní hlavičky, `json.encode`)
  můžu připravit patche a regresní testy ve stylu
  `tests/*_conformance.lsl` + `.out` a `*_negative.lsl`.

## Feature scope 0.5 bez GPU

Feature scope je implementovaný: self-host compiler/runtime, jazyk a collections, config lazy/default/provenance, AI retry/cancellation/SSE + live transport chunks, process JSON ABI, structured stdout/stderr/status, zero-copy CPU Tensor a omezený in-process CPU ET_DYN ABI v1.

## Zbývá hardening/bugfix/audit — plán 0.9.1

Následující otevřené body patří do plánu 0.9.1; výslovně volitelné
jazykové a ABI změny nejprve vyžadují návrh rozsahu. Historické odkazy
na scope 0.5/0.7 ponecháváme pro kontext, nejde o testový důkaz 0.9.0.

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
