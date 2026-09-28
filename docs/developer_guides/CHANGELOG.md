# Changelog

Na této stránce jsou uživatelsky významné změny vydaných verzí. Stabilní
manuály a soubory ke stažení zůstávají dostupné v
[historii vydání](/releases/).

## 0.8.8 — 27. 9. 2026, aktualizováno 28. 9. 2026

- Rychlejší vstup a výstup: `input()` čte soubor po 64 KiB (nepřečtený
  zbytek vrací potomkům i při ukončení), `print` do souboru, roury nebo
  `/dev/null` se bufferuje a vyprazdňuje před vším, kde záleží na pořadí
  (vstup, fd, syscally, sleep, fork, vlákna, stderr, exit). Terminál se
  chová jako dosud.
- Bufferovaný `input()` zachovává pozici také při střídání s `fd.read`,
  `fd.seek` a přesměrování stdin.
- Alokátor rezervuje haldu po 1 MiB; rozpočet GC už nepočítá surová data
  typovaných polí.
- `split` s jednoznakovým oddělovačem a `Int(String)` jsou nativní.
- Původní instalaci 0.8.8 je třeba přeinstalovat z nového archivu;
  `lsl update` při shodném čísle verze změnu neinstaluje.
- Opraven chybný překlad, když proměnná dostane dynamickou hodnotu až
  později v kódu (např. `zbytek = zbytek // p` a teprve potom
  `for p in seznam`): typy se nyní rozšiřují až do fixpointu. Dřív mohl do
  celočíselné proměnné dostat ukazatel (nesmyslné hodnoty, zacyklení).
- Diagnostika `E1119` pro čárku před `for` v comprehension
  (`[0, for x in rang(3)]`).
- Manuál: kapitola 11 doporučuje `IntArray` místo `List` pro velké
  číselné tabulky (síto na 1 000 000: 2,5 s → 0,03 s).

## 0.8.7 — 27. 9. 2026

- `rang(...)` funguje i mimo `for` jako hodnota: `List(rang(2, 101))`,
  `print rang(4)`, `len(rang(0, 10, 3))`. Smyčky `for` dál nealokují.
- `List.find(hodnota)` (i Tuple a RealArray) vrátí pozici nebo `-1`;
  `find` na runtime hodnotě rozliší String a List.
- Manuál: knihovny a `sudo` (per-user knihovny nejsou vidět pod `sudo`).

## 0.8.6 — 27. 9. 2026

- Jazyk: `load os, time` načte více modulů najednou; `load time, os as a`
  sdílí alias pro všechny uvedené moduly (člen se hledá v pořadí).
- Lux String: uvozovky uvnitř interpolace bez escapování, `l"{"a" * x}"`,
  včetně vnořených závorek a vnořených l-stringů.
- Interaktivní `lsl`: zvýrazňování syntaxe, historie, barevné prompty a
  automatické odsazení bloků.
- `lsl --tui [SOUBOR]`: terminálový editor ve stylu Vimu se zvýrazňováním.
- `lsl man` formátuje Markdown; `lsl about [KNIHOVNA]` a popisy knihoven
  v `help("knihovna")`, včetně nainstalovaných registrových balíčků.
- `lsl-install` a `lsl update` zobrazují průběh v procentech.

## 0.8.5 — 25. 9. 2026

- Rychlejší compiler: emit vrstva a ELF obraz v `ByteArray`, lexer nad
  UTF-8 bajty bez jednoznakových Stringů, úklid v codegenu po dávkách
  funkcí úměrných velikosti programu. Self-host build je ~1,4× rychlejší.
- Generovaný kód, runtime ani jazyk se nemění; binárky z 0.8.4 a 0.8.5 jsou
  pro stejný zdroj shodné a není nutné je znovu překládat.
- Přeplněné („overlong“) UTF-8 sekvence ve zdroji už nejsou přijímány jako
  znaky identifikátoru; hlásí se jako `E0006 unexpected character`.

## 0.8.4 — 22. 9. 2026

- Automatický GC podle alokovaných bajtů, nikoli pouze při formátování Float;
  herní smyčky nepotřebují ruční `gc()`.
- Adaptivní rozpočet a opětovné použití paměti, nealokující číselné smyčky
  bez GC kontrol.
- Iterativní průchod hlubokých a cyklických kolekcí bez alokace či rekurze.
- Bezpečné rozlišení raw bufferů, zachování kořenů a výjimek při úklidu.
- GC pokračuje během `thread_join()`; interní signál nezpůsobuje falešné
  chyby `run()` / `capture()` při čekání na podproces.
- Samostatné dříve zkompilované programy je nutné znovu přeložit.

## 0.8.3 — 21. 9. 2026

- Opraveno čtení neinicializovaných lokálů, které mohlo vracet obsah zásobníku
  nebo způsobit SIGSEGV. Statická kontrola E2002 nezavádí běhové kontroly lokálů.
  Globály čtené z funkcí mají kontrolovanou inicializaci a zachytitelný NameError.
- Typové deklarace `Int(x) = 10` kontrolují i další zápisy; známé správné typy
  nemají dodatečné běhové kontroly. Prefixové i postfixové `++`/`--` jsou
  samostatné příkazy, nikoli hodnotové výrazy.
- Vestavěné `system()` odpovídá `os.run()` a nespouští shell.
- **Změna návratového typu:** `clock()` vrací `YYYY-MM-DD HH:MM:SS UTC`.
  Pro intervaly použijte `monotonic()` nebo `time.monotonic/perf_counter`.
- Importní chyby E3001/E3002 vysvětlují chybějící či nečitelnou knihovnu.
- X11 zvládá částečné zápisy, EAGAIN a zavřený socket; přidán příklad Snake.
  Před upgradem spusťte `lsl update x11`, pokud máte X11 nainstalované.
  Nové X11 funguje také s 0.8.2 a již nepočítá s číselným `clock()`.

## 0.8.2 — 18. 9. 2026

- `safe` a `try` zachytí neznámé volání/proměnnou, neexistující metodu
  a podporované statické chyby typů a argumentů; chyby probublávají z funkcí.
- Opravený úklid zásobníku po selhání složeného výrazu. Známá volání
  a úspěšná cesta `safe` nemají nové kontroly ani instrukce.
- `last_error()` vrací použitelný String i pro nativní chybové zprávy.
- Barevná runtime diagnostika a zvýrazněné zdrojové chyby; `NO_COLOR`,
  `TERM=dumb` a `FORCE_COLOR=1/0` s konzistentní prioritou.
- Opravená příliš dlouhá fontová tabulka `gfx`, včetně české diakritiky.
- `gfx`, `x11`, `wayland`, `display`, `input`, `ui`, `css` jsou volitelné
  balíčky. Ověřené závislosti se instalují automaticky; základní instalace
  je neobsahuje. Grafické zdroje používají explicitní `unsafe`.

## 0.8.1 — 6. 9. 2026

- `sorted(iterable)` vrací stabilně vzestupně seřazený nový List.
- `set()` / `set(iterable)` vytváří nový typ Set s unikátními prvky,
  členstvím, iterací, GC a základními množinovými metodami.
- `dedup(list)` zachovává pořadí prvních výskytů i původní seznam;
  podporuje strukturální porovnání vnořených kolekcí.

## 0.8.0 — 6. 9. 2026

- Barevná nápověda, stavové výpisy a diagnostika; prostý text pro pipes a NO_COLOR.
- `lsl list` a `lsl check NAME`: offline inventář bundled/user knihoven.
- `lsl search [QUERY]`: validovaný produkční katalog s verzemi a popisy.
- `lsl install --tui`: filtrování, označení balíčků a potvrzená instalace.
- `lsl man`: offline TUI manuál se všemi 17 webovými kapitolami a referencí.
- `help()` i `help("TOPIC")`, včetně runtime témat a samostatných ELF programů;
  také `lsl help TOPIC`.
- TUI nezahazuje rychlé klávesy, dekóduje UTF-8 a dělené escape sekvence,
  obnovuje terminál po ukončení i zachycené chybě.
- Odstraněny staré soubory BUG*.md a netlify.toml; historie Gitu se nemění.
- Opraven nulový offset tar readeru v raw ABI CLI; `lsl-install` umí
  bezpečně migrovat i přeinstalovat aktivní generaci. Z 0.7.8 je potřeba
  jednorázový přechod přes instalační archiv, viz návod níže.

Podrobnosti: [CLI a balíčky](17-cli-and-packages.md).

## 0.7.8 — 6. 9. 2026

- Nová pure-LSL knihovna [random](16-random.md): Random/SystemRandom,
  MT19937, SHA-512 seedy, snapshot stavu, BigInt, vážené výběry,
  shuffle/sample a běžná rozdělení včetně binomial.
- [List/dict comprehensions](04-collections.md): vnoření, filtry, rozbalení
  a izolované proměnné; výchozí immutable a pojmenované argumenty funkcí.
- Podepsaný self-updater: `lsl update` pro LSL a `lsl update NAME` pro knihovnu.
  Produkční registry, Ed25519, kontrola archivu a atomická instalace s rollbackem.
- Referenční random vektory, thread/GC a compiler bezpečnostní regrese.

## 0.7.7 — 5. 9. 2026

- Persistentní CUDA session drží kontext a device buffery mezi příkazy.
  Přímý binární Unix socket nahrazuje nové procesy u opakovaných výpočtů.
- Float64 buffery podporují sum, dot, AXPY, matmul, sčítání, odčítání,
  násobení, dělení, scale, fill, ReLU a transpozici. DeviceTensor přidává
  tvarovou kontrolu, reshape a explicitní přenosy do/z host Tensoru.
- Výběr zařízení se správně předává i přes prázdné process environment.
  Matmul odlišuje pracovní jednotky od limitů polí a podporuje vysoké matice.
- CPU fallback i GPU mají kontrolovanou životnost session a bufferů, snapshot
  přenosy a limity. Binární transport zachovává signed zero, NaN a Infinity.
- Tensorové operace respektují offset a strides; prázdné tensory a nulová
  vnitřní dimenze matmul fungují. Compiler zachovává návratový typ řetězených
  metod přes `self` i bez call-site specializace.
- Přidány CPU/GPU session regrese, vadný worker, ownership, use-after-free,
  hardwarové limity a benchmark s kontrolními součty. Podrobné API v kapitole
  [CUDA a GPU tenzory](15-cuda.md).

## 0.7.6 — 30. 8. 2026

Segregované volné seznamy odstranily lineární průchody alokátorem po velkých
HTTP požadavcích. Vydání zahrnuje opravy HTTP body a `String.split` z 0.7.2–0.7.5.

## 0.7.1 — 28. 8. 2026

Stabilizační a bezpečnostní vydání bez nové syntaxe.

- Safe/unsafe průchod nyní kontroluje i třetí výraz kroku slice. Linker
  rozlišuje relativní moduly podle vyřešeného souboru, takže dva adresáře se
  stejně pojmenovaným `helper.lsl` nesdílejí chybný cache záznam.
- Interní raw ABI už není odvozeno z textu `compiler/pure/` v cestě. Self-host
  trust core používá explicitní `# lsl: internal-abi` a AST provenance;
  obyčejný projekt se stejně pojmenovaným adresářem zůstává ve veřejném
  kontrolovaném tagged Any ABI.
- `lsl origin NAME` pod zámkem ověřuje aktuální zdroj proti zaznamenanému
  SHA-256. Instalace a update serializují commit, odmítají symlink/special-file
  lock a při dvoufázovém zveřejnění preferují starý ověřený zdroj před novým
  zdrojem se zastaralým provenance.
- HTTP parser přijímá deklarovaný limit 64 hlaviček, vyžaduje neprázdný Host a
  statický server odmítá FIFO i ostatní nesoubory bez zablokování. Chyba
  aplikačního handleru je izolována na odpověď 500 a server obslouží další
  požadavek.
- Config purity kontrola nově blokuje i procesový `check` a `printl`.
  CLI vytváří dočasný ELF až po úspěšném codegenu a uklízí chybové cesty
  configu i sandboxu.
- Opraveno rozlišení samostatné modulové funkce `origin()` od receiveru
  `origin.method()` pro volání metody předka. Doplněny cílené regrese a plná
  lokální suite prochází.

## 0.7.0 — 27. 8. 2026

- `lsl server` nyní spouští omezený statický HTTP server; s certifikátem a
  klíčem deleguje HTTPS systémovému nginx/OpenSSL. Původ registru se přesunul
  do `lsl origin [NAME]` a install/update zapisuje ověřený provenance sidecar.
- `lsl sandbox` spouští safe-compiled worker přes bubblewrap namespaces,
  explicitní read/write capabilities, systemd cgroup, prlimit a timeout.
- Nový `unsafe:` blok ohraničuje privátní runtime/native/thread operace.
  Výchozí CLI kontroluje celý uživatelský importní graf; sandbox unsafe kód
  odmítá. Unchecked IntArray vyžaduje `lsl compile --unsafe`.
- Přibyla šestargumentová syscall brána, oprava tagged Any hranice mezi
  interním compiler ABI a veřejnými stdlib funkcemi a HTTP/sandbox/ABI
  regrese. HTTP socket writes používají `MSG_NOSIGNAL`, takže reset klienta
  neukončí server přes `SIGPIPE`.

## 0.6.9 — 27. 8. 2026

Stabilizační vydání veřejného dynamického ABI bez změny syntaxe.

- Dynamická indexace, zápis, mazání, iterace a kolekční metody ověřují runtime
  typ receiveru, indexu i hodnoty. Typed arrays a ByteArray se na Any hranici
  správně boxují; ByteArray nově podporuje slicing.
- Dynamické `+`, `*`, `//`, `%`, porovnání, `sum`, `min`, `max` a `sort`
  kontrolují kompatibilitu typů a zachovávají tagovaný výsledek. Opravena je i
  kolize Int výsledku s adresou živého heap objektu a Bool numerika.
- `List + List`, `String * Int`, konverze kolekcí a metody nad uniklými
  callbacky fungují stejně jako jejich staticky typované varianty; neplatné
  vstupy vracejí zachytitelnou `TypeError`.
- String, filesystem, process a binary-I/O builtiny kontrolují dynamické
  argumenty. `writebytes(List)` validuje každý prvek a self-host writer používá
  oddělený raw entrypoint.
- Chybějící Dictionary klíč při `del` vrací `KeyError`. Compiler kontroluje
  receivery i aritu metod, `arg()` a interních intrinsiců a zachovává source
  span v diagnostice.
- Přibyly boundary a negative regrese, pointer-collision testy i pevný limit
  velikosti optimalizovaného ELF. Fixed point, fast/full suite, instalace a ELF
  audit prošly.

## 0.6.8 — 27. 8. 2026

Čistě bezpečnostní vydání bez změny syntaxe jazyka.

- Heap, kolekce, I/O a raw memory hranice validují typy, živé handly, rozsahy
  i násobení velikostí; GC a rekurzivní equality mají fail-safe depth limit.
- Worker vlákna dostala guard page a fail-closed inicializaci. Dynamické
  callbacky musí být živé Function objekty a tisk Function už nezveřejňuje
  adresu kódu.
- Native ET_DYN volání běží v krátkodobém child procesu s uzavřenými file
  descriptory, alarmem, `no_new_privs` a strict seccomp. Loader používá W^X,
  serializuje `symbol`/`call`/`close` a GC zachovává ownership knihovny.
- Process/capture hranice validují argv, zavírají zděděné descriptory, omezují
  stdout/stderr a mají clean-environment varianty. Kontrolované endpointy
  zachovají fd 0/1/2 přes `execve` i po vstupu se zavřeným stdio. Zápis souborů blokuje
  symlink targety; fd, mmap a Unix socket API kontrolují typy a délky.
- HTTP nepoužívá ambientní curl config ani redirecty, omezuje URL, hlavičky,
  tělo a odpověď; plain HTTP přijímá jen `127.0.0.1` a `[::1]`. JSON, config,
  BigInt, lexer, parser, linker a package manager mají pevné, pro zdroje
  byte-přesné resource limity; stejně se počítají argv, cesty a integrační
  payloady, takže UTF-8 nemůže deklarované limity obejít. Config omezuje i celý
  importní graf.
- Dictionary používá per-process seed proti předpočítanému collision DoS.
  Celočíselná mocnina je logaritmická a dynamický záporný exponent končí
  řízenou chybou.
- CUDA worker validuje celý JSON objekt a ABI, odmítá duplicity a omezuje
  vstup, hloubku, pole i device buffery. Release worker má PIE, full RELRO,
  NOW binding, stack protector a neproveditelný stack.
- Resource resolver používá `prefix/lib/lsl` jen pro skutečný `prefix/bin`
  install. Dočasný compiler už nemůže potichu načíst starý `/lib/lsl` a
  kanonické source jméno drží fixed point nezávislý na cestě executable.
- Odstraněn nepoužívaný historický soubor `-o`, starý ET_EXEC artefakt mimo
  aktuální PIE toolchain.
- Přibyl výslovný [bezpečnostní model](security.md): běžný LSL a privátní
  `__lsl_*` ABI nejsou sandbox; nedůvěryhodný native kód patří do externího
  `exec` workeru bez secrets.
- Fixed point, fast/full suite, instalovaný compiler a audit statických PIE
  artefaktů prošly. Nové regrese pokrývají overflow alokací, deep GC/equality,
  native race, dědění descriptorů, symlinky a vstupní resource limity.

## 0.6.7 — 26. 8. 2026

Integrační a bezpečnostní hardening bez změny syntaxe jazyka.

- Generované programy jsou statické PIE (`ET_DYN`) s ASLR, jediným RX LOAD a
  explicitním RW/non-executable `PT_GNU_STACK`.
- HTTP posílá curl config včetně těla a hlaviček přes stdin, ne argv; vzdálené
  URL vyžadují HTTPS a validace blokuje header/control-character injection.
- Přibyl kombinovaný `capture_input_stream`; `plugin.request` používá JSON
  stdin, ověřuje exit status a starý argv režim je jen `request_argv`.
- Native loader dělá bounds kontroly před čtením mapování a odmítá relocation,
  dynamic a nekonzistentní symbol/section data. Native kód zůstává pouze pro
  důvěryhodné kernely; nedůvěryhodné komponenty patří do process workeru.
- Testy i CLI scratch soubory mají per-process cesty. Dva souběžné fast suites
  prošly; agregovaný mismatch nyní uvádí byte/length a ukládá oba artefakty.
- Linux x86-64 zůstává jediný release target. Databáze, TLS/OIDC a auditní
  control plane jsou výslovně odpovědností zralého hostitelského runtime.

## 0.6.6 — 26. 8. 2026

Výkonnostní patch kompatibilní s jazykem a manuálem 0.6.5.

- `for`/`rang` řídicí proměnné už nejsou vyřazené z alokace registrů;
  analýza započítává syntetické přístupy k čítači, indexu a explicitnímu
  kroku.
- Složené přiřazení lokálu se pro výběr registru správně počítá jako čtení i
  zápis, takže horké akumulátory typu `total += value` nezůstávají na stacku.
- `rang(stop)` a `rang(start, stop)` mají specializovanou větev s krokem
  `+1`, bez step slotu a opakovaného testu znaménka.
- Medián miliardové aritmetické smyčky klesl z 2,13 s na 0,83 s (−61 %),
  jednoduchého součtu čítače z 1,67 s na 0,58 s (−65 %) a user CPU self-host
  kompilace z 2,09 s na 1,97 s (−5,7 %). Checksumy zůstaly shodné.
- Přibyly regrese pro `rang` a `IntArray` iteraci; bitový fixed point, celý
  test suite, instalovaná kopie, config a audit statických ELF prošly.
- Installer nyní přibalí také `thread_runtime.lsl`, který importuje codegen;
  compiler v rozbaleném binárním balíku tak má úplnou self-host zdrojovou sadu.
- Staticky známý `Int` se na tagged hranici boxuje přímo bez pointerové
  klasifikace. Tím je odstraněna ASLR-závislá kolize s adresou živého
  boxovaného `Int`, která mohla náhodně poškodit číselné formátování; nový
  test tuto kolizi vytváří deterministicky.

## 0.6.5 — 26. 8. 2026

Výkonnostní a stabilizační vydání zaměřené na celočíselný codegen a
paměťovou náročnost převodů Float.

- `String(Float)` ověřuje a zkracuje desetinné kandidáty přes nativní
  stackový buffer a porovnání raw IEEE-754 bitů, bez dočasných heapových
  Float/String objektů pro každý pokus. Omezovaná post-format GC se spustí až
  po 256 formátováních a růstu registru o 4 096 adres, takže dlouhé konverzní
  smyčky drží paměť, ale krátké smíšené programy nedostanou globální GC pauzu.
  Veřejný `Float(String)` navíc mutuje jeden privátní akumulátor místo dvou
  nových Float boxů na číslici, při zachování původních IEEE bitů a chyb.
  Původní reprodukce (60 000 převodů) klesla z přibližně 5,1 GiB na 31 MiB;
  nový `float_format_allocation_conformance` hlídá správnost i růst tabulky.
- `cpu_count()`: počet CPU v affinity masce procesu (`sched_getaffinity`), pro dimenzování worker poolů.
- Posuny s proměnným počtem (`x << n`, `x >> n`) jsou součástí registrového
  emitoru: jedna bezznaménková kontrola `n > 63` na horké cestě, záporný
  počet dál vyhodí ValueError, široký posun dává 0 / saturuje na 63. Lumen
  perft dalších −4 %.
- Unchecked `IntArray` složené přiřazení s čistou pravou stranou používá ALU
  operaci s paměťovým cílem (`add/sub/and/or/xor [r10+r11*8], rcx`) a fast
  path ukládání/RMW přijímá libovolný čistý Int index i hodnotu. Lumen perft
  dalších −4 %.
- Globální proměnné programu leží ve state bloku za runtime hlavičkou a
  adresují se přes `rbx` místo rámce `main` v r12; r12 je tím volný jako
  čtvrtý registr pro lokály. Lumen perft 0,43 → 0,37 s (−13 %).
- Registrové lokály sdílejí registr podle živých intervalů (statement clock,
  smyčky rozšířené na celý rozsah), takže se do r13–r15 vejde víc lokálů s
  disjunktní životností; smyčkový microbenchmark dalších ~11 %.
- Registrový emitor čistých `Int` výrazů: stromy z literálů, `Int` jmen,
  unchecked `IntArray` čtení a `+ - * & | ~ << >>` / unárního `-`/`~` se
  překládají Sethi–Ullmanovým přidělením registrů rax/rcx/rdx/rsi/rdi/r8/r9
  bez `push`/`pop`, s imm32 formami a s hoistingem datového ukazatele
  nejčastěji indexovaného pole; přiřazení do registrového lokálu jde přímo do
  jeho registru. Smyčkový microbenchmark dalších ~18 %.
- Alokace registrů pro lokály: až tři staticky `Int`/`Bool` lokály (včetně
  parametrů) s nejvyšším váženým počtem použití (smyčky 4× za úroveň) žijí ve
  funkci v r13/r14/r15; ukládají se v prologu do rámce a obnovují na jediném
  návratovém labelu, takže chybové cesty i rekurze zůstávají korektní.
  Smyčkový microbenchmark ~19 % rychleji, Lumen perft ~5 %; compile time
  beze změny. Test `tests/register_locals_conformance.lsl`.
- Stav výjimek a vrchol zásobníku vlákna se přesunuly z registrů r13/r14/r15
  do thread-local bloku adresovaného přes `fs` (`arch_prctl(ARCH_SET_FS)`,
  u workerů `CLONE_SETTLS`; hlavní vlákno state+160, workery druhá polovina
  64bytového záznamu v tabulce vláken). Uvolňuje tři callee-saved registry
  pro budoucí alokaci registrů lokálům; chování programů se nemění.
- `popcount(x)` a `trailing_zeros(x)` builtiny (POPCNT/TZCNT nad raw Int;
  `trailing_zeros(0)` je 64). Test `tests/bit_builtins_conformance.lsl`.
- Peephole v assembleru: `cmp r64, 0` → `test r64, r64`. Eliminace
  store→load a skoků na další instrukci byly změřeny jako o 8–10 % pomalejší
  (perft i self-host) a záměrně nejsou zapnuté.
- Inference parametrů běží ve dvou fázích: rekurzivní volání `f(ply + 1)`
  uvnitř `f` už neoznačí parametr jako `Any` dřív, než compiler uvidí vnější
  volající; teprve nerozřešené parametry se rozšíří na `Any` a všechna volání
  se pozorují znovu. Inference návratových typů vidí typy globálů, takže
  funkce vracející hodnotu z globálního `IntArray` vrací staticky `Int`.
  Test `tests/parameter_inference_conformance.lsl`.

## 0.6.4 — 21. 8. 2026

Vydání se sdílenými vlákny a SSE2 FloatArray kernely.

### Jazyk a runtime

- `thread_spawn(function)` a `thread_join(tid)`: sdílená vlákna přes
  `clone(CLONE_VM|CLONE_THREAD|…|CLONE_CHILD_CLEARTID)` s 8 MiB mmap
  zásobníky, tabulkou až 127 workerů a futex join; kernel nuluje status slot
  po skutečném ukončení vlákna, takže join a opětovné použití zásobníku nikdy
  nezávodí s dobíhajícím workerem.
- Allokátor je chráněn tříhodnotovým futex mutexem (bez syscallu, dokud není
  kontendován), který se zapne až prvním `thread_spawn`; jednovláknové
  programy mají stejnou alokační cestu jako dřív.
- `gc()` z hlavního vlákna zastaví workery signálem `SIGUSR1`
  (`SA_RESTORER` handler, `rt_sigreturn`), konzervativně projde jejich živé
  zásobníky od uloženého `rsp` po vrchol mapování a po sweepu je probudí přes
  futex gate; ve workeru je `gc()` no-op.
- `atomic_add`/`atomic_xchg`/`atomic_cas`/`atomic_pause` jsou zdokumentované
  jako synchronizační primitiva pro sdílené `IntArray` sloty.
- Nové `tests/thread_conformance.lsl`: čtyři atomické čítače, workery
  alokující během `gc()` a slot reuse.

### Výkon

- FloatArray kernely `float_sum`, `float_dot`, `float_axpy`, `float_fill` a
  `float_matmul` používají SSE2 packed double (dvě lane, skalární ocas).
  `float_matmul` běží v pořadí i-k-j s vysíláním `A[i,k]` a je bitově shodný
  se skalární verzí; 256×256 je přibližně 4,5× rychlejší. `float_sum` a
  `float_dot` sčítají ve dvou akumulátorech.
- Self-hostovaný compiler zůstává bitově reprodukovatelný ve fixed pointu.

## 0.6.3 — 21. 8. 2026

Výkonnostní vydání zaměřené na řízení toku a celočíselné hot pathy.

### Compiler a výkon

- Složené Boolean podmínky `and`/`or`/`not` se větví přímo z CPU flags a
  zachovávají short-circuit sémantiku bez mezilehlých `setcc` hodnot.
- Volání nepřelévá první argument zbytečně přes zásobník; vstupy funkcí jsou
  zarovnané na 32 bytů.
- Staticky známý návratový `Bool` nepoužívá obecný runtime truthiness helper;
  stabilní velikost bloku zachovává jeden vícebytový NOP.
- Unchecked `IntArray` složená přiřazení používají přímý read-modify-write a
  čisté výrazy se dvěma či více přístupy do stejného pole načtou jeho datový
  ukazatel pouze jednou.
- Lumen `perft 5` je proti 0.6.2 přibližně 1,5× rychlejší při totožném počtu
  4 865 609 uzlů; přesné měření je v reportu enginu.
- Self-hostovaný compiler zůstává bitově reprodukovatelný ve fixed pointu.

## 0.6.2 — 21. 8. 2026

Výkonnostní vydání pro numerické a vyhledávací programy.

### Compiler a výkon

- Typované čtení, zápis a iterace přes `IntArray` po zachování kontroly mezí
  přistupují přímo k raw Int64 bufferu bez runtime helper `call`/`ret`.
- Inference parametrů používá známé typy volajících jako počáteční bod pro
  rekurzivní funkce; známý `Int` nebo `IntArray` už rekurzivní volání nerozšíří
  na dynamické `Any`.
- Opt-in direktiva `# lsl: unchecked-intarray` dovoluje ověřeným numerickým hot
  pathům vypnout kontroly mezí typovaných `IntArray`; výchozí režim je nadále
  bezpečný a zachovává `IndexError`.
- Unchecked `IntArray` přístup s jednoduchým celočíselným indexovým výrazem
  neprovádí obecný zásobníkový spill cílové kolekce.
- Self-hostovaný compiler zůstává bitově reprodukovatelný ve fixed pointu.

## 0.6.1 — 21. 8. 2026

Údržbové vydání, které doplňuje práci s bity.

### Jazyk

- Bitové operátory `&`, `|`, `~` (XOR), `~x` (NOT), `<<` a `>>`. XOR je `~`,
  protože `^` už znamená mocninu — stejné rozdělení má Lua.
- Složená přiřazení `&=`, `|=`, `~=`, `<<=` a `>>=`.
- Celočíselné literály s prefixem `0x`, `0o` a `0b`. Redukují se modulo
  `2^64` jako desítkové, takže `0xFFFFFFFFFFFFFFFF` je `-1`.
- Priorita odpovídá Pythonu: `<<`/`>>` jsou volnější než `+`, ale těsnější
  než porovnání, takže `x & 1 == 1` znamená `(x & 1) == 1`.
- Posuny jsou definované v celém rozsahu: záporný počet je `ValueError`,
  posun o 64 a více bitů dává `0`, u `>>` pro záporné číslo `-1`.
- Operand jiného typu než `Int`/`Bool` je chyba překladu; dynamická hodnota
  skončí `TypeError` místo čtení bitů živého pointeru.

### Compiler

- Konstantní posuny se skládají už při překladu a jinak se emitují jako
  immediate `shl`/`sar`; proměnný posun používá `CL` s explicitní kontrolou
  rozsahu, ne maskování procesorem.
- `lsl-install` nově kopíruje i moduly `math` a `bigint`, které `help` už
  uváděl.
- Self-hostovaný compiler zůstává bitově reprodukovatelný ve fixed pointu.

## 0.6 — 29. 7. 2026

Druhé archivované self-hosted vydání LSL.

### Jazyk

- Operátor mocniny je `^`; původní `**` je odmítnuté syntaxí.
- Přibyly first-class Lux Stringy, například
  `text = l"Jmenuji se {name}"`.
- `printl` zůstává kompatibilní a používá stejnou interpolaci.
- Celý modul lze importovat pod aliasem: `load test as t`.

### Compiler a výkon

- Konstantní String concat se skládá už při překladu.
- Malé konstantní mocniny se emitují inline.
- Lux String s více výrazy používá vyvážený concat strom.
- JSON encoder a binární FloatArray transport se vyhnou kvadratickému
  skládání velkých payloadů.
- Self-hostovaný compiler zůstává bitově reprodukovatelný ve fixed pointu.

### Skutečná NVIDIA CUDA

- Vydání obsahuje `lsl-cuda-worker` postavený pomocí CUDA Runtime.
- Na GPU běží ověřovací kernel, Float64 `sum`, `dot`, AXPY a tiled matmul.
- `cuda.available()` vrací True až po úspěšném device kernelu.
- Velká pole používají raw binární stdin/stdout místo JSON serializace.
- Politiky `auto`, `required`, `off`, výběr zařízení a CPU fallback jsou
  součástí veřejného modulu `cuda`.
- Hardware conformance a benchmark byly ověřeny na NVIDIA GeForce GTX 1650,
  compute capability 7.5.

### Distribuce a dokumentace

- `lsl --help`, `lsl version` a `lsl --version` hlásí 0.6.
- Installer přidává CUDA worker vedle LSL binárek.
- Web obsahuje samostatné stabilní manuály 0.5 a 0.6, historii vydání,
  zdrojové archivy, binární balíky, offline manuály a SHA-256 součty.

## 0.5 — 29. 7. 2026

První veřejné self-hosted vydání LSL.

- Compiler je napsaný v LSL a sám sebe překládá do bitově shodného výsledku.
- Přímý backend zapisuje statický Linux x86_64 ELF bez libc, assembleru a
  linkeru.
- Runtime používá Linux syscalls a obsahuje garbage collector, String,
  kolekce, Float, moduly, třídy a strukturované chyby.
- Standardní knihovna zahrnuje JSON, konfiguraci, procesy, HTTP, AI,
  Tensor/FloatArray, GUI a správu systému.
- CLI přidalo funkční `--help`, `version` a `--version`, všechny s verzí 0.5.
- Vyšel první český dvanáctidílný vývojářský manuál a kompletní reference.

## Odkazy na stabilní manuály

- LSL 0.6.9 aktualizuje živý manuál; 0.6.5 zůstává poslední neměnný snapshot.
- LSL 0.6.6 používá [manuál 0.6.5](/releases/0.6.5/).
- [LSL 0.6.5 — manuál a soubory ke stažení](/releases/0.6.5/)
- [LSL 0.6 — manuál a soubory ke stažení](/releases/0.6/)
- [LSL 0.5 — historický manuál a soubory ke stažení](/releases/0.5/)
