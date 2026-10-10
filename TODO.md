# LSL TODO

Přesný průběžný stav, hashe a důkazy jsou v `PURE_LSL_PROGRESS.md`. Aktuální handoff, pořadí blockerů a ověřovací příkazy jsou v `COMPLETION_PLAN.md`.

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

## Aktivní plán

- [ ] Zpřesnit statickou kontrolu přiřazení pro prokazatelně neprázdné
  smyčky, aby přijala čtení proměnné po smyčce, pokud přiřazení proběhne
  na každé cestě vedoucí k tomuto čtení. Bez dodatečných běhových kontrol
  a bez automatické inicializace nulou či `None`. Analýzu omezit na bezpečně
  prokazatelné případy; zohlednit `break`, `continue`, větvení, změny kolekce
  přes aliasy i vedlejší účinky volání. Pokud důkaz chybí, zachovat současné
  odmítnutí. Doplnit pozitivní i negativní regrese (včetně prázdných či
  vyprázdněných kolekcí) a změřit dopad na čas a paměť překladu; ověřit,
  že nevzniká dodatečná běhová režie ani oslabení paměťové bezpečnosti.
- [ ] FIX: Opravit zdrojové pozice diagnostiky výrazů v interpolacích.
  Reprodukce v 0.8.9: E2002 při čtení `chyba` v
  `printl "Epocha: {epocha} loss: {chyba}"` nesprávně ukazuje na první
  řádek `load random`. Chyba musí označit skutečné použití `chyba`
  v původním souboru, se správným řádkem a sloupcem. Zachovat původní
  pozice při parsování interpolovaných výrazů a doplnit regresní testy
  pro `printl`, l-stringy a importované moduly.
- [ ] Opravit čítače vnořených `for` smyček se stejným jménem proměnné:
  oddělit interní stav iterace od uživatelské proměnné, aby vnitřní `for i`
  neměnil počet iterací vnějšího `for i` ani nezpůsoboval zacyklení.
  Reprodukce v 0.8.9: vnější `rang(3)` s vnitřním `rang(2)` provede jen
  jednu vnější iteraci místo tří; kombinace `rang(100)` / `rang(10)` se
  zacyklí. Doplnit regrese pro oba případy, přiřazení do proměnné v těle,
  `break` a `continue`.
- [ ] Sjednotit výpisy běhových chyb s obvyklým formátem diagnostiky LSL.
  Místo holého `LSL runtime error: TypeError: sequence index must be Int`
  zobrazit `error[...]`, typ a srozumitelný popis chyby, soubor, řádek,
  sloupec, příslušný zdrojový kód s označením chybného výrazu a vhodné
  `help:` s návodem k opravě; u typových chyb uvést očekávaný i skutečný typ.
  Zachovat správné zdrojové pozice včetně interpolací, funkcí a importů,
  barevný výstup dle stávajících pravidel terminálu a `NO_COLOR`.
  Pokrýt běh přes `lsl` i samostatné zkompilované binárky regresními testy;
  zachycené chyby v `try`/`safe` nesmí samovolně vypisovat diagnostiku.
- [ ] Přidat výchozí hodnoty parametrů uživatelských funkcí po vzoru Pythonu,
  například `function f(x = 10):`. Vynechaný argument použije deklarovanou
  výchozí hodnotu, explicitně předaný argument ji nahradí. Doplnit pravidla
  pro povinné/volitelné parametry, dokumentaci a regresní testy.
- [ ] Opravit hlášené chování `help("nonexist")`: neexistující téma má vypsat
  srozumitelnou anglickou zprávu, například `No help available for topic: nonexist.`,
  nikoli vyvolat chybu či ukončit program. Zachovat `help()` i známá témata
  a pokrýt všechny tyto případy regresními testy.
- [ ] Doplnit volitelný druhý argument `Dictionary.get(key, default=None)`
  po vzoru Pythonu. `.get(key)` vrátí existující hodnotu, při chybějícím klíči
  `None`; `.get(key, default)` místo toho vrátí zadanou výchozí hodnotu.
  Odstranit hlášené selhání při jednom argumentu; nesprávný počet argumentů
  musí mít srozumitelnou diagnostiku, nikdy pád runtime. Přidat dokumentaci
  a regrese včetně uložených hodnot `None`, `False` a `0`.
- [ ] Pro další vydání doplnit rozbalování položek v běžném `for`, například
  `for x, target in data:` pro seznam dvojic. V LSL 0.8.9 tento zápis končí
  E1210 (`expected in after loop variable`), přestože comprehensions
  rozbalování podporují. Sjednotit chování, přidat srozumitelnou chybu při
  nesprávném počtu hodnot, dokumentaci a regresní testy včetně uvedené
  vnořené trénovací smyčky s výpočty Int/Float.
- [ ] Přidat raw řetězce `r"..."` (r-string) bez interpretace escape sekvencí,
  interpolace a jiných automatických úprav. Doplnit `printr` pro výpis
  přesného obsahu bez přidaného odřádkování či oddělovačů; popsat syntaxi
  v dokumentaci a ověřit chování regresními testy.
- [ ] Přidat podporu blokových komentářů `/* ... */`, včetně více řádků,
  diagnostiky neukončeného komentáře, dokumentace a regresních testů.
- [ ] Umožnit zaokrouhlit a oseknout (truncate) počet desetinných míst
  u Float. Dnes `math.round` vrací jen celé číslo a žádný přímý zápis pro
  počet míst neexistuje; běžné formátování typu „{x:.2f}" v LSL chybí.
  Cíl: jeden srozumitelný mechanismus (např. `round(x, digits)` a/nebo
  přesnost v interpolaci) s jasně definovanou sémantikou — matematické
  zaokrouhlování včetně záporných čísel a polovin a odděleně oseknutí
  bez zaokrouhlování; podpora záporného počtu míst (desítky, stovky),
  `digits = 0`, neceločíselného či jinak neplatného počtu míst
  s srozumitelnou diagnostikou a chování pro NaN/Infinity. Doplnit
  dokumentaci a regresní testy včetně interakce s Float formátováním.
- [ ] Zpřístupnit opravené streamování z `aikit` také v instalované nativní
  knihovně přes `load ai`. Vyřešit přednost vestavěného modulu tak, aby šlo
  používat `lsl update ai` bez aktualizace celého LSL a bez aliasu
  `load aikit as ai`. Spolu s knihovnou aktualizovat `lsl man ai`; ověřit
  výběr správné verze, původ knihovny a kompatibilitu existujících skriptů.
- [ ] Oddělit web a webové manuály (`docs/developer_guides` včetně index.html
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

### Nahlášeno z provozu 2026-10-09 — LUX AGENTS (LSL 0.8.9)

Kontext: agentní konzole (~3000 řádků LSL, HTTP server v produkci za Caddy
+ CDN), marketplace v LSL a pět sellerů; jazyk použit i na podepisované
kanonické JSON payloady. Všechny body níže jsou ověřené na 0.8.9; spustitelné
reprodukce jsou v `~/Downloads/lsl-bugreport/` (README.md + `*.lsl`), zde
jsou kvůli soběstačnosti uvedené i v tělech položek.

- [ ] BUG: `httpserver` vrací 400 na **duplicitní request hlavičku**
  (`stdlib/httpserver.lsl:404-405`):

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

- [ ] BUG: `json.encode` kazí Floaty (`stdlib/json.lsl`, `encode_value()`,
  větev `value_type == 6` → `__lsl_float_string(value)`). Dvě oddělené vady:

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

- [ ] CHOVÁNÍ: **tichý shadow globálu** — zápis do globálu z funkce se tiše
  neprovede (žádná chyba, žádné varování):

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

- [ ] BUG (nepodařilo se zminimalizovat): `gc()` vedle běžícího workeru
  poškodil alokace **SSE parseru modelu**. Podle dokumentace
  (`docs/developer_guides/11-performance-and-optimization.md`, řádek ~593)
  je volání z hlavního vlákna bezpečné („zastaví workery přes `SIGUSR1`,
  projde jejich zásobníky a po sweepu je probudí"), v provozu to ale
  rozsypalo proud. Náhrada v kódu:

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

- [ ] DROBNOST: `IntArray(1)` končí hláškou
  `IntArray cast requires an existing IntArray`, která neřekne, co je
  špatně (správně `IntArray()` + `append`, viz
  `docs/developer_guides/04-collections.md:377`). Doplnit do chyby nápovědu.

- [ ] PŘIDAT: **ISO-8601 / strftime v `time`** — modul má jen `time()`,
  `now()`, `monotonic()`, `perf_counter()`, `sleep()`. Kanonické časové
  značky (`2026-10-09T04:01:53.833305+00:00`) do podepsaného payloadu jsem
  musel vyrábět dotazem do SQLite (`strftime`).

- [ ] PŘIDAT: **streamovaná odpověď v `httpserver`** — odpovědi se bufferují
  (`Content-Length` + `close`), takže nelze poslat SSE. Kvůli tomu LSL port
  marketplace vypustil relay průběhu sellerů (konzole zobrazí až hotový
  job). Stačil by write handle / chunked režim.

- [ ] ROBUSTNOST: **zámek přežije výjimku** — `lock()`/`unlock()` nad
  `IntArray` uvolní zámek jen explicitně, takže výjimka mezi nimi drží
  spinlock navždy (v provozu tvrdý hang celé konzole na ~48 % CPU, dokud
  jsem to nenašel). Bloková konstrukce (`lock x: … end`) nebo automatické
  uvolnění při zániku vlákna by to řešily. Navazující přání: **viditelná
  diagnostika, když workeři umře výjimka** — tichý zánik vlákna se ladí
  velmi těžko.

- [ ] DOKUMENTACE/DEPLOY: přepsání běžící binárky končí `ETXTBSY`;
  řeším `stop → kopie → start`. Není to chyba jazyka, ale pár řádků
  v dokumentaci (nebo `lsl deploy` s atomickým replace) by ušetřilo
  překvapení. Zároveň: accept loop `httpserveru` je jednovláknový
  (dokumentováno) — jeden pomalý request zdrží ostatní a klienti musí
  volat sekvenčně; volitelný worker pool / per-connection vlákno by
  serializaci frontendu odstranily.

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
