# Pure-LSL migration

## Aktuální vydání 0.8.1 — 6. 9. 2026

`sorted(iterable)` vrací stabilně seřazený List; `dedup(list)` zachovává
první výskyty i vstup. Nový heap typ Set (16) má GC, render, rovnost bez
pořadí, iteraci, členství a množinové metody. Implementace je pouze LSL;
Set používá lineární lookup. `sorted` zatím nemá `key`/`reverse`.

Přegenerovány compiler, CLI, installer, configure a runner. Fixed point je
bitově shodný, plná sada včetně GTX 1650 a nových Any/pointer-collision testů
prošla. Compiler: `88863cc28498de4b4c032253bb2931fd098c9f9eb9e5e377eb74edd053a7de23`.
CLI: `2d76856112faeb7158ea4ad2f376f3724af109388db23fb328fa07ebfe6c51b2`.
Optimalizační fixture má 105 140 bajtů; nový limit 105 500 ponechává těsnou
rezervu nad záměrně rozšířeným runtime. Podrobnosti: `docs/release-0.8.1.md`.

## Vydání 0.8.0 — 6. 9. 2026

Barevné CLI a diagnostika, list/search/check, validovaný katalog knihoven,
TUI správce balíčků a offline manuál všech 17 webových kapitol. Embedded
`help()` / `help("TOPIC")` pracuje i se String proměnnou v samostatném ELF.
Implementace i nové conformance testy jsou pure LSL. TUI čte klávesy přes
buffer a poll, obnovuje terminál a neprovádí instalace bez potvrzení.
Podrobnosti: `docs/release-0.8.0.md`.

Stage 2/3 jsou bitově shodné; nástroje vznikly sériově pod 2 GiB. Plná
regresní sada včetně GTX 1650 prošla s limitem 4 GiB. Nápověda se linkuje
jen při použití; optimalizační fixture zůstává pod limitem 98 000 bajtů.
Compiler: `f34c2e2bb08e85149b3c932a1f93eb5d42390d530d9036a10e394bc751ab3bc7`.
CLI: `c414a69d56d449d947e202dc4bdebc04745e9edf25fdc35dffbe5f56c6c668e4`.

Závěrečný test skutečné 0.7.8 odhalil raw-ABI Int(0) v tar readeru, který
veřejný testovací driver maskoval. Oprava používá kontrolované interní Int
rozbalení; testy nyní explicitně pokrývají CLI ABI. Nový installer podporuje
atomický přechod ze staré instalace i přeinstalování spravované generace.

## Vydání 0.7.8 — 6. 9. 2026

Pure-LSL `random`: MT19937 a SHA-512 seedování, Random/SystemRandom,
stav, vážené výběry, shuffle/sample, BigInt a běžná rozdělení. Přidány
list/dict comprehensions s hygienickými proměnnými, vnořením a filtry,
immutable default argumenty a pojmenovaná volání. Nové negativní testy
kontrolují i safe/unsafe hranice uvnitř comprehensions. Detaily a limity
jsou v `docs/random.md` a `docs/release-0.7.8.md`.

Vydání zahrnuje dříve dokončený podepsaný self-updater a produkční registry.

Stage 2/3 jsou bitově shodné; všechny nástroje sestaveny sériově pod 2 GiB.
Compiler: `00743c98334cc8014f709a4204fe556e69ecc61450441a4f2ed64deaa66bf9bc`.
CLI: `a810cb486e6041e1ad214f6943129b1509e2af62bdb17a72aa0e00dd603b9149`.

## Vydání 0.7.7 — 5. 9. 2026

CUDA doplněna o persistentní session ABI 2, přímý binární Unix socket,
device buffery, Float64 elementwise operace a transpozici, DeviceTensor a
explicitní upload/download/free/close. CPU session má stejné rozhraní.
Opraveny work/element limity matmul, vysoké gridy, předání indexu zařízení,
fallback po vadném workeru a materializace tensorových pohledů. Starší ABI 1
a jednorázové kernely zůstávají dostupné. Veřejný rozsah a limity:
`docs/cuda.md`; obecné dtype a uživatelské GPU kernely jsou mimo tento rozsah.

Compiler zachovává instanční typ `self` při inferenci návratových hodnot;
regrese `class_method_return_conformance` funguje i s uniklými callbacky.
Stage 2 a 3 jsou bitově shodné, všechny nástroje vznikly sériově pod 2 GiB.
Plná sada včetně hardwarové CUDA prošla. Čistá instalace reprodukuje compiler
bitově, config odpovídá golden souboru, instalovaný příklad z `/tmp` vrací
stejný výsledek na CPU a GPU. Audit static PIE a hardeningu CUDA workeru prošel.

HTTP/GC stress z 0.7.6 potřebuje přibližně 2,6 GiB: suite byla ověřena
s 4 GiB limitem. Klientský timeout je 30 s místo 5 s a test má 180 s alarm,
aby při selhání klienta nezůstával neomezeně blokovaný listener.

SHA-256:

- compiler: `5b5b3d89adf580e98fc7b042102b1489099ef44d22ddf46aa8686524947d9fa7`;
- CLI: `ea86d1313917cec0e44ada41cdf534be96c17c363d41b09f5da67b5eaa6ee1ec`;
- runner: `d9954fa52b5c7b73b30510cca3bbb97419c2e8b37733846861bd55885f099e31`;
- CUDA worker: `e6822df1ceff1df15ab9b21502e1fb9a14038801638d0a0162b5ac8032c90016`.

GTX 1650 / CC 7.5, CUDA 13.3, 512×512: medián pěti běhů CPU 0,04325 s,
persistentní CUDA včetně downloadu 0,02228 s (1,94×), start/upload 0,319 s.
Všech deset výsledků má checksum 134217728. Benchmark je
`tests/cuda_session_benchmark.lsl`.

## Goal
Produkční compiler a host runtime musí mít pouze LSL zdroje: žádný C/C++
backend, runtime, libc, assembler, linker, Python ani shell launcher. Compiler
napsaný v LSL zapisuje přímo Linux ELF64 a výsledky používají přímé Linux
syscalls. Volitelný skutečný CUDA backend je izolovaný foreign worker v
`cuda/`, nikoli součást compileru nebo self-host řetězce. Chyby vždy uvádějí
soubor, řádek, sloupec, výřez, caret, kód chyby a podle možnosti nápovědu.

## Target / definition of done
- První podporovaný target: Linux x86_64 (host ověřen jako `x86_64`).
- `lslc` je ELF vytvořený předchozím `lslc`, jeho jediný udržovaný zdroj je LSL.
- Runtime a standardní knihovna jsou LSL moduly; compiler je překládá a linkuje.
- Compiler přímo zapisuje ELF a nastaví executable mode přes syscall; žádné `cc`,
  libc, assembler ani externí linker.
- Stage N přeloží `compiler/pure/lslc_direct.lsl` na bitově shodný stage N+1.
- Compiler, host runtime a jejich testy neodkazují na `.c`, Python ani shell;
  samostatný volitelný CUDA worker používá `.cu`.
- Conformance a config testy běží pouze přes LSL ELF seed a LSL programy.

## Plan
- [x] Potvrdit host/počáteční target Linux x86_64.
- [x] Zapsat zákaz cizího backendu jako tvrdou architektonickou podmínku.
- [x] Implementovat v LSL první diagnostický engine se source spans, kódem, caret výpisem a help textem (`compiler/pure/diagnostics.lsl`).
- [x] Implementovat v LSL první ELF64 writer a x86_64 syscall encoder bez assembleru/linkeru (`compiler/pure/elf64.lsl`).
- [x] Dokončit vertikální řez: literal `print`/`exit` -> samostatný statický syscall-only ELF (`compiler/pure/hello.elf`).
- [x] Rozšířit bootstrap writer o arbitrary-byte materializer pro plný x86_64 encoder (ověřeny bytes 0, 1, 127, 128, 129, 200, 255).
- [x] Implementovat samostatný Unicode lexer s token spans a strukturovanými lexical errors (`compiler/pure/lexer.lsl`).
- [x] Implementovat parser s token spans pro specifikaci 0.5 včetně linked-module source path/line/source anotací.
- [x] Implementovat první nativní scalar/control-flow/function codegen: Int/Bool, locals, aritmetika, comparisons, if/while/loop/for-rang, break/continue, SysV calls, recursion.
- [x] Implementovat recursive compile-time module linker s namespace prefixing a selective imports.
- [ ] Přenést allocator, String a kolekce z C runtime do LSL/runtime modulů. (Hotovo: `brk` allocator+GC; UTF-8 String; growable List metody; Tuple/RealArray základ; Dictionary metody; boxed Bool/None; boxed IEEE-754 Float literals, arithmetic, comparisons, Int/String konverze, JSON a printing. Zbývá jednotné tagování všech dynamických scalar hran a plné Tuple/RealArray enforcement.)
- [x] Přenést classes, exceptions, GC, JSON, filesystem, process a HTTP hranici. (Classes/instances, error propagation, čistý JSON, syscall filesystem/process, conservative stack/global-root mark-sweep GC s free-list reuse, `capture`, `env` a bezpečný argv HTTP/HTTPS transport přes systémový curl.)
- [x] Implementovat přímý modulový linker a config evaluator na čistém runtime.
- [x] Jednorázově vytvořit transition host (historický krok; host byl po fixed pointu odstraněn).
- [x] Dosáhnout čistého direct-ELF stage fixed pointu bez C-derived runtime ve stage N→N+1 cestě.
- [x] Nahradit launchery/build/install/test LSL programy (`lsl`, `compiler/lslc`, `lsl-cli`, `lsl-configure`, `lsl-install`, `lsl-test`).
- [x] Ověřit diagnostické negative testy, conformance, determinismus a instalaci.
- [x] Po potvrzení odstranit starou C/Python/shell implementaci a artefakty.

## Notes / decisions
- „Jen LSL“ znamená zdrojový jazyk implementace. CPU přirozeně vykonává strojový
  kód; ten compiler generuje jako data přímo z LSL. ELF seed je binární trust root,
  nikoli zdroj v jiném programovacím jazyce.
- Přenos musí být inkrementální. Starý self-hostovaný ELF lze použít právě jednou
  k vytvoření prvního direct-backend compileru; nesmí zůstat v produkční cestě.
- Žádné tvrzení o dokončení před syscall-only self-host fixed pointem.
- Povolená transition fáze historicky vytvořila první direct ELF. Po ověření
  čistého fixed pointu uživatel výslovně schválil odstranění staré C/Python/shell
  cesty; transition host, seed i artefakty byly odstraněny.
- První přímý výstup `hello.elf` má statický ELF64 program header, žádný dynamic
  interpreter/libc a provádí pouze Linux `write`/`exit` syscalls.
- Paměťový limit je tvrdý požadavek: žádné paralelní bootstrapy; testovací procesy
  běží sériově pod `ulimit -v`. Původní direct materializer měl O(n²) alokace a
  spolu s 16 MiB rezervou na každý `readfile` způsobil vyčerpání RAM/restart PC.
  Desetinný/unrolled meziformát se proto odstraňuje z finální cesty.
- GC metadata používají 32-byte stavový blok rezervovaný přes `brk`; RBX drží
  jeho adresu. ELF `PT_LOAD` proto zůstal pouze RX a `readelf` ověřil absenci
  RWX segmentu i po zapnutí collector/free-list runtime.

## State
Historická transition fáze se souhlasem uživatele vytvořila první direct ELF a
18. 7. 2026 dosáhla prvního čistého fixed pointu
`2106296ed5b5f5239ae5d5aa3e791d6d37a21f685967258cef86da0d7a6c9582`.
Od tohoto bodu všechny iterace, runtime moduly, buildy a testy běžely pouze přes
LSL-generované ELF, sériově pod paměťovým limitem. Transition host, decimal
materializer, C seed a staré produkční launchery byly po finálním souhlasu
odstraněny.

Následný čistý fixed point po doplnění UTF-8 runtime měl SHA-256
`2eba023daae3a427033f305bd08721e23ffc43faa841e4ce5057da17933a36cf`.
Fixed point po doplnění exceptions měl SHA-256
`9005bd7fe6b02d9946b5aa149f14b4ea17576dc8f39cc1804c1572df3dcd1162`.
Fixed point po doplnění classes, globálních proměnných ve funkcích a
first-class Function pointerů/callback volání měl SHA-256
`0318d6e109fa26fb3cf4a73b7b310ab30dd4514fbad80f533c363c0ffb793d63`.
Fixed point po kolekcích, boxed Bool/None v kolekcích, Dictionary iteraci,
`printl` interpolaci a čistém JSON měl SHA-256
`0f14b3f24ccdecb024319d834d1e0889a1f4e13bb715ebff1174dc6395984394`.
Fixed point po dynamické Dictionary iteraci a obecném String membership
dispatchingu měl SHA-256
`d2c6e96ceb232d44b52fa5f1ce7c627602a1de59240e85f2d76fccc0ef344a44`.
Fixed point po čisté Linux `fork`/`execve`/`wait4` process hranici měl SHA-256
`cb6db73d75d808dadd3238f4aee8ff9aa465ff78ca7b7c2dd8ba4db1d9bf75b3`.
Fixed point s bezpečným missing-argv handlingem měl SHA-256
`4af4d35d20b90928fece3a0f0def48d9591fce507bd4ec61e4d196c14ae91741`.
Fixed point s první verzí mark-sweep cycle GC měl SHA-256
`2e43af5dc3b32be902f5cfb2a50a88266eeb055da5d85a9ae63f5b1730d07a09`.
W^X fixed point přesunul writable GC stav z ELF image do `brk` heapu a měl
SHA-256 `6a62377be08c7549d0d87af473f4f8ea38e5555073350945e9a95b55ad32bd06`.
Fixed point s `capture`, `getenv` a HTTP/AI runtime hranicí měl SHA-256
`d85e87c27d34b1a61bb0544f6ac31f62d12ab14ed95defec5cc2a25e7c503800`.
Fixed point s boxed IEEE-754 Float runtime měl SHA-256
`c1ce25da09dbe1f37ec1a95ba14e0ad841b5891811f6aefe7a412737f4524a47`.
Fixed point s tagged Tuple/RealArray, fixed-collection checks, private module
class lowering, chained comparisons a Int power měl SHA-256
`dff47a713a2f418257d459d7626db08ed74eba51c7dc9a4de788ad95c9ba4f27`.
Relocatable-install fixed point s `executable_path`, resource lookup, `mkdir` a
`unlink` měl SHA-256
`279350c88493cb32dbd92f62ccb018f386548e77ad725e129fc078d6ddd191a7`.
Fixed point s přesnými linked-module codegen spans měl SHA-256
`233adbde6aa4864fdbfc1464a8c1ba854a0b7776c54317b06357511462a2a9ea`.
Fixed point s direct function/initializer arity validation měl SHA-256
`e815fba2779823a555bfb480410ed7153a6bd36eb6e8f39c4413a7159d9920a1`.
Fixed point s checked sequence indexing, catchable/fatal `IndexError`,
catchable/fatal `ZeroDivisionError`, skutečným floor `//` a modulo semantics a
přesnějším uncaught-error výpisem měl SHA-256
`d6b3fe268071c6d0e19cf4f677cf70ec0f15f58a3e5df35f6d4643b5d410e0c0`.
Fixed point s decimal exponent Float literals, strukturovaným `E0004` pro
malformed exponent a `Float(String)` exponent parsingem měl SHA-256
`ca5cebf14464b575a0609c8024b9c16fbafadac2f15b7b35a1fb7f00a0d72bca`.
Fixed point, který odstranil `0x400000` cutoff přes exact 16M-entry allocation
registry a 64K-entry String intern cache, měl SHA-256
`e8d127bbdcac39adadbdadf5ce45395c8386313f97baacf9502427206761f21d`.
Fixed point s Int/Float-only RealArray runtime enforcement měl SHA-256
`973d87f816c90fc05d3ebf27d6d6e94be56c06572f7da89c4b4f775a85395bb8`.
Fixed point s validací Float String gramatiky a dynamickou `Float(Any)` konverzí
měl SHA-256
`6a591be461fc72faf1aeafc2672d618162ec3a47e22947bc566f858bac0dce33`.
Fixed point s catchable `readfile` `FileError` měl SHA-256
`e05c7a9517b7939c691d0f4b780ec068498771f9554750c4d71e8667892fe8d4`.
Fixed point s catchable `writefile`/`writebytes` chybami měl SHA-256
`721189e674e8af87a11c3587d51cd59c14c480c94888b134b41402957efcce17`.
Fixed point s catchable záporným Int exponentem měl SHA-256
`fad995fa35534c96679a9a68de22c5d3194337d57218070e27b9e76472d5a204`.
Fixed point s catchable `dictionary[key]` `KeyError` měl SHA-256
`7cb3d3e6f9342206e9c6cd246311cd658a6edfeecc1fc58f7d73a0383612cc7b`.
Fixed point s přesnými collection `.pop`/`.index` errors měl SHA-256
`2d727c4e4c12d75cc1571668c78358b87f357f17d69f473e21c0bec74f156d1a`.
Aktuální fixed point přidává syscall-only `input(prompt)`, `appendfile` s
catchable `FileError` a monotonic boxed-Float `clock()`. Má SHA-256
`cb7a479bd9caef705c1b12b9ed32a3dd6fbe3cf9d8327de13978802b1a4ec3c1`
a je uložen jako `compiler/pure/lslc-direct`. Dvě po sobě jdoucí čisté stage
byly bitově shodné;
jediný `PT_LOAD` má flags `R E`, nikoli RWX. Ověřeno: `len`, indexování, záporné indexy, slicing, `chr` a
`ord` pracují s Unicode code points (`ž`, `ť`, `č`, `😀`), zatímco interní
String payload a syscall I/O zůstávají UTF-8 bytes. ASCII scalar/function,
dynamické String/List, Dictionary, String metody a filesystem smoke testy po
změně znovu prošly. Navíc prošly callbacky (`120 24 6 Function`), lokální
`Counter` class (`2 native-counter 5 5`) a modulová public class
(`12 Class Instance`). Celý `tests/selfhost_conformance.lsl` se nyní čistým
compilerem přeloží, skončí s kódem 0 a jeho stdout je bitově shodný s
`tests/selfhost_conformance.out` (15 řádků včetně callbacks, collections,
exceptions, Unicode, classes, modules a JSON). Čistě LSL `stdlib/configure.lsl`
navíc vygeneroval evaluator pro `examples/config/system.lsl`; jeho výstup je
bitově shodný s `tests/config_expected.json`, včetně recursive merge priorit,
List concatenation, `mkForce`, options a assertions. Čistý
`tests/lsl-test` následně bez shellu/Pythonu spustil přes syscall-only
`run` scalar smoke, celý selfhost conformance a fixed-point byte comparison;
skončil 0 s `pure LSL tests passed`. `compiler/pure/lsl-cli` navíc čistě
zvládá usage/exit 2 bez argumentů, `compile SOURCE OUTPUT`, compile-and-run s
předáním argv a `config ENTRY`; config CLI výstup znovu přesně odpovídal
`tests/config_expected.json`. GC smoke ověřil uvolnění self-cycle po `del`,
zachování živých lokálních i globálních Listů a následné znovupoužití obou
uvolněných heap bloků; plný selfhost conformance zůstal přesně shodný.
`capture` lokálně ověřil stdout a exit bez shellu, `env` rozlišil present/missing
secret, `http.get(file://...)` vrátil strukturované `status/text/ok` a
`examples/ai_client.lsl` se čistě nativně přeložil (síťový request se bez
výslovného požadavku nespouštěl). Float smoke ověřil decimal literal/parser,
SSE2 `+ - * /`, ordered/equality comparisons, mixed Int/Float, zápornou nulu,
`Int`, `Float(String)`, `String(Float)`, List dynamic dispatch a valid JSON
čísla; je součástí čistého `lsl-test`. Další smoke ověřil `2 ** 10`, chained
Int/Float comparisons, oddělené runtime tagy Tuple/RealArray, JSON arrays,
RealArray copy/mutation a strukturované odmítnutí Tuple mutace. Public module
class zůstala funkční a private class už z namespace nejde zkonstruovat.

Veřejné `lsl` a `compiler/lslc` jsou nyní přímo pure-LSL ELF soubory. Strom
neobsahuje žádné `.c`, `.h`, `.py` ani `.sh` soubory. `lsl-install` byl ověřen
v `/tmp/lsl-prefix`; instalované `lsl`/`lslc` fungovaly z jiného pracovního
adresáře, config výstup byl přesně shodný a instalovaný compiler znovu vytvořil
bitově shodný fixed point. Negative modulový test nyní správně ukázal
`/tmp/moderr/badmod.lsl:3:10`, skutečný source řádek, caret a help namísto root
souboru. Arity negative test `add(1)` proti `add(a, b)` ukázal přesný span a
`help: pass exactly 2 arguments`; selfhost i config conformance zůstaly shodné.
`tests/runtime_error_conformance.lsl` navíc ověřuje negative/too-large index,
dělení nulou a znaménkově správné floor division/modulo. Pure test runner nyní
porovnává stdout selfhost, runtime/I/O-error, Float exponent/conversion,
dynamic-value, RealArray a process-plugin conformance přesně s `.out` soubory.
I/O conformance navíc přesně ověřuje write+append+read, `clock() > 0.0` a
append failure; interaktivní input smoke přijal `Lux\n` a vypsal
`name: hello Lux`. Process plugin ABI v1 používá čistý `fork`/`execve`, jeden
JSON argv request a JSON stdout
response, validuje `abi`/`ok` a propaguje `PluginError`; server i klient v testu
jsou LSL-generované ELF. `lsl-install` kopíruje `stdlib/plugin.lsl`; instalovaný
compiler z jiného cwd přeložil server i klienta a jejich output byl přesně
shodný. Dynamic-value test ověřuje Int hodnoty `5000000`, `-5000000` a `9000000000` uvnitř List/Dictionary, equality, sum a
smíšený String dispatch; starý cutoff by tento test rozbil.

Fixed point s validovanou `Int(String)`/`Int(Any)` konverzí má SHA-256
`497482d6c2ceece5a0ab4d990764050aaf356f2e0e6f48c2a1966aee27ac2e7f` a je uložen
jako `compiler/pure/lslc-direct`. `Int(String)` nyní dispatchuje na čistou LSL
`__lsl_parse_int` (znaménko, prázdný/sign-only řetězec i ne-číslice → catchable
`ValueError: invalid Int String`); dřívější `runtime_string_to_int` bez validace
vracel garbage (`Int("abc")` → `5451`). `Int(Any)` dispatchuje přes
`__lsl_int_any` (Int→self, String→parse, Float→truncate přes nový intrinsic
`__lsl_float_to_int`, Bool→unbox, jinak catchable `TypeError`). Změna proběhla
disciplinovaným dvoufázovým bootstrapem: fáze A přidala jen rozpoznání intrinsiku
`__lsl_float_to_int` (fixed point `59966431…`), fáze B teprve stdlib funkce a
`Int` reroute (fixed point `497482d6…`, B2==B3). Celý toolchain
(`lsl`, `compiler/lslc`, `lsl-cli`, `lsl-configure`, `lsl-test`, `lsl-install`)
byl přegenerován deterministicky (každá binárka 2× bitově shodná). Nový
`tests/int_conversion_conformance.lsl`/`.out` je zapojen do `lsl-test` a celý
suite je zelený; catchability ověřena přes `safe` i `try/else`.

Fixed point s Float `**` (mocnina) má SHA-256
`b48df85b691527f045767d2ffbbb548fa37d09b02343b06c91e9f7b9fb9428e3`. Dříve
`infer_expression_type` neměla větev pro `**`, takže `2.0 ** 53` bylo inferováno
jako Int a šlo přes `runtime_int_power`, který bral boxed-Float pointer jako Int
(výsledek `0`/garbage). Inference nyní promuje `**` na Float, pokud je kterýkoli
operand Float; nový `runtime_float_power` počítá exact repeated multiplication
(SSE2) a pro záporný exponent vrací reciproký. Float báze vyžaduje Int exponent;
Float exponent je odmítnut čitelným compile errorem místo tiché truncation.
`runtime_float_power` je runtime label, takže stačila jednofázová iterace do
fixed pointu (fp2==fp3). Toolchain přegenerován deterministicky; nový
`tests/float_power_conformance.lsl`/`.out` je v `lsl-test`.

Fixed point s NaN/Infinity výpisem měl SHA-256
`99547d0e086fc56d61db4d0451fab55600ff87f561ac098090f35f50087e7978`. Dříve
`runtime_print_float`/`runtime_float_to_string` volaly `double_to_int` (cvttsd2si)
i na NaN/Inf, kde vrací INT64_MIN → garbage (`1.0/0.0` → `-9223…775808`). Obě
funkce nyní z IEEE-754 bitů detekují special values (`abs == 0x7FF0…` → Inf podle
znaménka, `>` → NaN) a vypisují/klonují interned `inf`/`-inf`/`nan`; `String()`
používá static String layout + `runtime_string_clone`.

Fixed point s IEEE-754 NaN comparisons má SHA-256
`07ba33b962d0bf85…`. `ucomisd` při NaN nastaví ZF=PF=CF=1, takže původní
`sete/setb/setbe` vracely při NaN chybně `True` a `setne` chybně `False`. Nové
helpery `set_condition_ordered` (`setcc ∧ setnp`) a `set_condition_unordered`
(`setcc ∨ setp`) filtrují parity flag: `== < <=` jsou při NaN `False`, `!=` je
`True`, `> >=` byly už korektní. Ověřeno 15 případů včetně `NaN != NaN == True`;
rozšířeno `tests/float_special_conformance`. Známý zbývající bug: `1e300`/`1e20`
výpis je stále `0.000000` — korektní řešení je shortest/exponenciální formatting
(Ryū/Grisu), velký samostatný algoritmus, ne bugfix; není označeno za hotové.

Fixed point s bezpečným `INT64_MIN // -1` / `% -1` má SHA-256
`be536ee3245d9271…`. `idiv` dělitelem `-1` přetéká kvocient na `+2^63` → CPU #DE →
SIGFPE tvrdý pád procesu. Codegen `//`/`%` nyní dělíč `-1` řeší speciálně:
kvocient = `neg(a)` (wrapuje, `INT64_MIN`), zbytek = `0` — konzistentní s 2's-
complement wrapping s�mantikou Int (`a+1` už wrapuje) a se sémantikou Pythonu
mimo nereprezentovatelný 2^63. Žádný pád, definovaný výsledek; floor
division/modulo pro ostatní případy beze změny. Rozšířen
`tests/runtime_error_conformance`.

Fixed point s partial-write smyčkou má SHA-256 `3b21bc515297d442…`.
`writefile`/`appendfile`/`writebytes` dříve dělaly jediný `write` syscall a při
partial write (pipe, velký buffer) tiše ztratily data. Nový sdílený
`runtime_write_all` loopuje `write` dokud nejsou všechny bajty odeslané (rdi/rsi/
rdx syscall zachovává), s error větví. Ověřeno zapsat+přečíst 256000 bajtů
bitově shodně + append; compiler sám jím píše vlastní několikasetkilobajtový
ELF, takže fixed point tuto cestu validuje.

Fixed point s CRLF strip v `input()` má SHA-256 `71d331262bcadb7a…`.
`runtime_input` dříve strippoval jen `\n`, takže `Lux\r\n` (CRLF, Windows/DOS
vstup) zanechal koncový `\r` (délka 4). Po tomto kroku strippoval i koncový
`\r`; pozdější fixed point `f4330810…` odstranil i tehdejší pevný 4096B limit.

Fixed point s arita validací builtinů má SHA-256 `c283131172fd71ed…`. Dříve
`len()`, `chr()`, `Int()`, `String()` (a další) bez argumentů **shodily samotný
compiler** (SIGSEGV při přístupu na `arguments[0]`), a `len("a","b")` /
`ord("a","b")` tiše ignorovaly extra argumenty. Codegen nyní na začátku name
dispatch validuje aritu builtinů proti tabulce (0: `gc clock arg_count
last_error executable_path`; 1: `Bool Int Float String List Tuple RealArray len
chr ord abs sum type exit input readfile getenv mkdir unlink exists`; 2: `min
max run capture writefile appendfile writebytes check`) a místo pádu vydá
strukturovaný compile error se span a help. `tests/builtin_arity_negative.lsl`
je zapojen jako require_failure.

Fixed point s arita validací metod má SHA-256 `66aa3dada53c4ee7…`. Stejná třída
bugu jako u builtinů, ale pro metody: `list.append()` bez argumentu **shodil
compiler** (SIGSEGV na `arguments[0]`), `"x".upper(5)` a `s.replace("l")` tiše
ignorovaly/doplňovaly garbage. Codegen validuje aritu metod s pevnou aritou
(0: strip/lstrip/rstrip/lower/upper/title/sort/copy/keys/clear; 1: append/
startswith/endswith/find/count/split/join/extend/remove/index/update; 2:
replace/insert; proměnné pop/get/setdefault vynechány) pro ne-Class receivery.
`tests/method_arity_negative.lsl` je require_failure. Známá samostatná mezera
(pre-existing): `print`/`String()` List/Tuple/Dictionary vypisuje raw pointer
místo obsahu.

Fixed point s repr kolekcí má SHA-256 `ef02708447547506…`. Dříve `print` /
`String()` List/Tuple/RealArray/Dictionary spadly na `runtime_print_int` /
`runtime_int_to_string` a vypsaly **raw pointer** místo obsahu. Nová rekurzivní
čistě-LSL `__lsl_render(value, quote)` (a `__lsl_str_value`, `__lsl_int_to_string`)
formátuje `[..]` / `(..)` / `![..]` / `{k: v}`, vnořené Stringy s `'..'`, a
codegen `print`/`String()` kolekcí i `Any` přesměrovává sem. Při tom se odhalila
přímá instance okruhu-1 kolize: `__lsl_type_code(raw 0)` vrací 5 (None), protože
integer 0 a None sdílí raw reprezentaci; render proto nejdřív přes nový intrinsic
`__lsl_is_heap` (dvoufázový bootstrap) rozliší raw scalar (→ Int) od boxed
hodnot (→ type_code), takže `[0]`→`[0]` a `[None]`→`[None]`. Selfhost conformance
zůstal beze změny; nový `tests/collection_repr_conformance` je v `lsl-test`.
Známé omezení: raw Bool vs raw Int stejnou kolizi sdílí (`String(True)` mimo
kolekci dá `1`), plně to řeší až tagged ABI (okruh 1).

Fixed point s `List + List` a `String * Int` má SHA-256 `15521a0c7647442c…`.
Dříve obě operace chyběly v `infer_expression_type`, spadly na `Int` a sečítaly
raw pointery (garbage). Inference nyní vrací `List` pro `List + List` a `String`
pro `String * Int` / `Int * String`; codegen přesměrovává na čistě-LSL
`__lsl_list_concat` a `__lsl_str_repeat` (obě runtime labely, bez bootstrapu).
Ověřeno `[1,2]+[3,4]`, `[]+[1]`, `"ab"*3`, `3*"xy"`, `"a"*0`;
`tests/sequence_ops_conformance` je v `lsl-test`.

Tři pilíeře jazyka (config / AI / běžné programy) ověřeny end-to-end.
Dodaný `examples/showcase.lsl` se dříve NEpřekládal: používal neuvozený
víceslovný Unicode text v `Error(Kind: ...)` (lexer padl na `á`), což není
kanonická forma — stdlib vždy uvozuje. Oprava: zprávy uvozeny. Navíc `load lux`
odkazoval na neexistující modul; přidán `stdlib/lux.lsl` (`version` = "0.5",
`name`, `identity`/`clamp`/`is_empty`) a zaregistrován v installeru — showcase
teď běží celý včetně `LSL 0.5`. Config systém je funkční: `lsl config ENTRY`
produkuje výstup bitově shodný s `tests/config_expected.json`; přidán usage guard
do `configure.lsl` (chybějící argument → usage/exit 2 místo matoucího FileError).
Compíler fixed point beze změny; toolchain (lsl-configure, lsl-install)
přegenerován.

Fixed point s `del(list[i])` a Python truthiness má SHA-256
`f6f0f8a77fd7d084…`. (1) `del(beta[0])` (v definici jazyka) dříve fungoval jen
pro Dictionary; nyní `del(list[i])` přes čistě-LSL `__lsl_delete_at` (shift +
pop_last, catchable IndexError, záporné indexy), Tuple/RealArray odmítnuty jako
fixed. (2) `runtime_truth` dříve vracel True pro **jakoukoli** ne-None/Bool/Float
heap hodnotu, takže `Bool("")`, `if []:`, `if {}:` byly chybně truthy; nyní
String/List/Dictionary/Tuple/RealArray testují length/count na offsetu 8 (prázdné
→ falsy jako Python). Fixed point dr=ží i po změně truth sémantiky (compiler
nespoléhal na truthy prázdné kolekce). `tests/del_conformance` a
`tests/truthiness_conformance` přidány.

Fixed point s `help()` a `min`/`max(iterable)` má SHA-256
`e1824f525b0f4e6d…`. `help()` (v definici jazyka) dříve chyběl — nyní vypisuje
krátký přehled funkcí/typů. `min`/`max` přijmou buď 2 hodnoty, nebo 1 iterable
(čistě-LSL `__lsl_min`/`__lsl_max`, catchable `ValueError` na prázdné sekvenci);
dříve arita validace `max([..])` chybně odmítala (a předtím crashovala).
`tests/minmax_help_conformance` přidán.

Výkon: self-compile zrychlen z **273 s na 1,9 s (~142×)**, `print "hi"` z 2,9 s
na 0,09 s, celý test suite z 348 s na 4,3 s; scaling je nyní lineární místo
O(n²). Fixed point `3be80c9e902652cc…`, celý toolchain deterministický,
config conformance bitově shodný. Tři O(n²) příčiny odstraněny:
1. **Dictionary** byl asociační seznam (lineární scan v get/set/contains) →
   přidán open-addressing hash index (djb2) vedle insertion-order polí.
2. **String indexace/`for-in` je O(n)** (skenuje UTF-8 od začátku), takže
   index-based lexer byl O(n²). Přidán native `runtime_string_chars`
   (String→List[1-char] jedním O(n) průchodem, intrinsic `__lsl_string_chars`,
   dvoufázový bootstrap); lexer nyní indexuje List (O(1)).
3. **`__lsl_split` byl O(n²)** (`text[i]` v loopu) a `source.split(chr(10))` se
   volá 3× na celý zdroj (link 2×, codegen 1×) — dominantní náklad. Split nyní
   převeden na char-list, O(n).

Konstantní faktory (po O(n) fixu): self-compile 1,9 s → ~1,3 s. `chr(10)`
hoistnut z lexer smyček (alokoval na každý znak); lazy dict hash index (malé
dicty jako tokeny/AST nodes bez index overheadu, velké zůstávají O(1));
per-volani ASCII intern v `runtime_string_chars` (~60k alokací → ~80, sdílené
pointery aktivují pointer-eq fast path v `string_equal`).

Codegen kvalita (rychlost generovaného kódu): čtyři optimalizace naivního
stack-machine kódu, všechny bitově fixed-point + config shodné:
1. `if`/`while` podmínky vynechávají `runtime_truth` (call + is_heap_object
   probe), když výraz už dává 0/1 (compare, and/or, not, Bool).
2. Int binární operace: literal/proměnný leaf operand se načte přímo do
   registru místo push/pop spillu (komutativní +/* i leaf vlevo).
3. Ordered comparisons (`< <= > >=`): stejný leaf trik místo push/pop.
4. `if`/`while` s ordered Int compare větví přímo na flagy (`cmp` + invertovaný
   `jcc`) místo `setcc; movzx; cmp 0; jcc` — 3 instrukce z každé podmínky pryč.
5. `//` a `%` mocninou dvou: strength reduction na `AND (2^k-1)` / aritmetický
   `SAR k` místo `idiv` — přesně Python floor sémantika i pro záporná/INT64_MIN.

Férové srovnání s C (fold-resistant benchmarky, průměr 3 běhů; `-O2` zde foldí
uzavřený vzorec, LSL ne, proto -O0):
- add/mul: C -O0 106 ms vs LSL **104 ms** (0,98× — na úrovni C).
- div/mod 2^k: C -O0 235 ms vs LSL **146 ms** (0,62× — pod C, díky AND místo idiv).
- div/mod odd: C -O0 357 ms vs LSL 754 ms (2,1× — `idiv` dominuje; hardwarové
  dělení + Python floor korekce, neobejditelné bez změny sémantiky).

Integer-bound smyčky bez dělení jsou tedy nyní na úrovni `gcc -O0`. Zkoušená 5.
optimalizace (vypustit zero/-1 guard u konstantního děliče) se v šumu ztratila,
protože `idiv` (20-40 cyklů) dominuje nad pár dobře predikovanými branchemi —
vrácena (neplatící se komplexita). Požadovaných „do 5 % od `-O2`“ není
dosažitelné: `-O2` dělá algoritmické transformace (uzavření smyčky do vzorce,
vektorizace, LICM), ne konstantní faktor — to je samostatný optimalizující
backend (SSA, register allocation, loop passes), vícedenní práce, není hotové.
Další reálná páka konstantního faktoru: držet horké lokální proměnné v
registrech namísto stack slotů (skutečný register allocator).

Fixed point s indexed augmented assignment má SHA-256
`3b07b7f9bbe00802796b3a93846229a67a4400e6681f4767d5c16539ebc4d513`.
`list[i] +=`, `RealArray[i] -=` a `dictionary[key] *=` nyní používají stejný
dynamický numerický/String dispatch jako běžné výrazy; nový exact-output test
ověřuje Int, Float, String a všechny tři mutable collection druhy. Tři čisté
stage jsou bitově shodné, celý toolchain byl 2× deterministicky přegenerován,
`lsl-test` a config conformance procházejí.

Fixed point s dynamickým `rang` krokem má SHA-256
`a6d15858fb69fe33ffe334e14790e2cc3b3133a45b7b985f0d7b2d00159b19ff`.
Start, stop i step jsou vyhodnoceny právě jednou; Int proměnné a Any parametry
fungují pro kladný i záporný krok. Nulový krok propaguje catchable `ValueError`
s path/line a dynamický ne-Int krok `TypeError`. Exact-output conformance, tři
fixed-point stage, celý deterministicky přegenerovaný toolchain, `lsl-test` i
config conformance procházejí.

Fixed point s round-trip Float formattingem má SHA-256
`d0690d53f31e76f23b6889afd30548bd368202ba9b838880fc0adddadc3937b5`.
`print`, `String(Float)` i Floaty uvnitř kolekcí používají společný čistě-LSL
formatter: zachovává `-0.0`, NaN/±Infinity, používá pevný nebo exponentový tvar,
opraví počáteční decimal-scaling drift porovnáním IEEE bits a zkracuje digits,
dokud `Float(text)` zůstává bitově shodný. Conformance pokrývá běžné hodnoty,
1e±300, minimum normal, minimum subnormal, max finite, 1/3 a velkou hodnotu s
frakcí; všechna finite kola hlásí `True`. Očekávané výstupy starších testů byly
záměrně změněny z nepřesného fixed-6 formátu (`1.199999`) na round-trip tvar
(`1.2`). Tři stage a dvakrát generovaný toolchain jsou bitově shodné, suite i
config procházejí.

Fixed point s dokončenými dokumentovanými collection metodami má SHA-256
`3403a93cac60c303965afd69afb8b28a405500c04cd114b52d28f297c88e6e82`.
List nyní umí `reverse`, `pop(index)` a missing `remove` propaguje `ValueError`;
Dictionary umí `values/items/copy/clear/pop(key[, default])`, po clear lze znovu
vkládat bez stale hash indexu a `Dictionary(iterable)` validuje dvojice. String
má Unicode-aware `capitalize`. Exact-output test pokrývá mutation, copy
nezávislost, chyby a insertion order. Tři stage, dvakrát generované nástroje,
celý suite i config jsou shodné.

Fixed point s `del(instance.member)` má SHA-256
`56ed96ad3a00533a05bc5403ea306fa28f73f2b19e129160b61eabce5112bfc2`.
Dokumentovaná member deletion nyní maže Dictionary-backed field a následný
přístup propaguje `KeyError`; `del(name)` navíc korektně obsluhuje globální
sloty a unknown name je compile error. Self-host stage i suite procházejí.

Fixed point s neomezeným řádkovým `input()` má SHA-256
`f433081048b83607163fde29ff5932506865f78a75147cbd28f32c21108d0f63`.
Runtime čte přesný jeden řádek po bajtu, buffer roste 2× od 256 B, EOF/LF/CRLF
mají přesnou sémantiku a následující řádek zůstává pro další `input`. Manuální
exact-output conformance ověřila 5000bajtový řádek a druhé čtení; tři stage,
deterministické nástroje i celý suite procházejí.

Fixed point s neomezeným `capture()` stdout má SHA-256
`343cc72d1dda37a188d8b31a90e076fe47ba6acf731de90976308623db02ee7e`.
Původní pevný 1MiB buffer je nahrazen 2× rostoucím String payloadem; parent při
zaplnění alokuje, překopíruje a pokračuje ve čtení pipe až do EOF. Pure-LSL
conformance vytvoří 2MiB soubor, child jej vypíše a parent přesně ověří délku,
první/poslední byte a newline. Fixed point, deterministické nástroje i suite
procházejí.

Fixed point s širokým class initializer ABI má SHA-256
`a147d1366d6528103e6bffe486eea467e917ca513494dfb4513c7983094b1dd7`.
Konstruktor už není omezen na pět user argumentů: prvních šest hodnot včetně
`self` jde registry a zbytek standardním stack ABI, se správným cleanupem před
error propagation. Conformance ověřuje osm argumentů konstruktoru a sedm
argumentů bound metody. Fixed point i suite procházejí.

Tagged ABI fáze 3 má fixed point
`1b529bd1e2ac92b6399170969f0d8c81fdccea2cdea38b9837fa7a35a2311333`.
Staticky známé Int hodnoty jsou type 9 v List/Tuple/RealArray, Dictionary values
a instance fields včetně mutací; augmented assignment numerický výsledek znovu
otaguje. `type(Any)` a config type schema rozpoznají type 9 jako Int. Self-host
vyžadoval explicitní unbox register tabulek a byte outputu; tři boxed-collection
stage jsou nyní bitově shodné. Conformance pokrývá 0/1, min/max, JSON, mutace,
Tuple, RealArray a Dictionary; celý suite a config jsou zelené.

Tagged ABI fáze 4a má fixed point
`b939f8c171dc086ff3794fdda5f2a163468097c23eed223c5f4414c6b42cbbd3`.
Staticky známé Int/Bool/None argumenty se boxují před direct, indirect, method i
initializer voláním v registrech i na stacku. Identity return zachová tagy;
conformance ověřuje 0/1, min/max, Bool/None a class init/method. Self-host,
suite a config jsou zelené.

Tagged ABI fáze 4b-infrastruktura má fixed point
`19ec5a02e266f918b2eee6dc4fc0d67771a9042401c2e9bbdfb46f2792376548`.
Heap type 10 boxuje Function code pointer, generic type/truth/equality/render jej
znají a indirect call bezpečně přijímá raw i tagged callable při zachování všech
argument registrů. Explicitní conformance ověřuje callback v List, identity,
equality a přežití GC. Veřejné automatické Function boxování je hotové ve fixed pointu
`f876b40dbd1c030d3c7cd48a8b97da7b8e41745b677579e551327327c0070c84`.
Audit opravil lexikální shadowing a oddělil self-host backend jako interní typed
raw trust core (`compiler/pure/`), aby jeho encoder nikdy nepoužil heap pointer
jako scalar. Běžné user moduly automaticky používají type 10; callback/List,
identity, equality, GC, Float smoke, celý suite a config jsou zelené.

Config evaluator nyní materializuje chybějící option defaults do nested
výsledku, validuje jejich typ a detekuje import cycles s celou cestou. Targeted
conformance pro defaults, cycle i existující system config prochází.

Allocator fixed point `4c248ff1a45cf8477f7338d6fe22e1e8df452ddb6b1fee65bceedfee93635424`
kontroluje počáteční i každé následné `brk` a úplný object-registry probe.
Vyčerpání končí deterministickým `MemoryError`/status 70; ověřeno spuštěním pod
64MiB limitem. Fixed point, deterministická regenerace nástrojů a config jsou
zelené. Následující fixed point
`dfc81ddfd9fa0f57f3f86c12465891fd24003b752e6420769134f6405eea17e6`
doplnil stejnou full-probe ochranu 64K String intern cache.

Restricted native CPU ABI fixed point
`42fd3c59427ff6552d926bdaf7ad029eca2ce7e5a619522bcd6e85d7f5fd04c1`
mapuje self-contained Linux x86_64 ET_DYN přes syscalls, validuje ELF a section
bounds, hledá SHT_DYNSYM symboly a volá je in-process s nejvýše šesti Int64.
Opaque type 11/12 neodhalují LSL heap. Conformance v LSL vyrobí vlastní ET_DYN,
zavolá `add(19,23)`, ověří missing symbol, malformed image a catchable
use-after-close `NativeError`.

Pure-LSL `tensor` module poskytuje dense CPU Tensor nad sdíleným RealArray,
shape/strides/offset/dtype, bounds-checked get/set, reshape a zero-copy views.
Conformance dokazuje sdílenou mutaci a shape errors; installer jej distribuuje.
Foreign shared-object/GPU ABI tím není nahrazené. AI vrstva navíc validuje OpenAI SSE events a doručuje content chunks callbacku
s cancellation. Fixed point
`f89961f12aecdce45c5772a138133b8b39fbd36a91f13c1f6638217faaf16524`
přidal `capture_stream`: raw stdout chunks jsou callbacku předávány už během
read loop, callback errors jsou catchable a curl `--no-buffer` je vystavuje přes
`http.post_stream`/AI `transport_chunk`.

AI standard module nyní poskytuje OpenAI-compatible request, timeout, retry pro
transport/408/429/5xx, cancellation callback, validaci provider JSON,
`AIProviderError`/`AICancelled` a bezpečný content accessor. Conformance používá
syntetické responses bez sítě; example i installer jsou aktualizované. Skutečný
curl token streaming zůstává samostatná transportní mezera.

Tagged return fixed point
`74077a0e7531f139cf4cd9adcaa41c8d1f61a52e613c518f0696398b51f8cb35`
boxuje raw numerický výsledek Any binary výrazu před návratem z user funkce;
staticky typed returny zůstávají raw fast path. Conformance ověřuje dynamické
`2 + -2` jako type 9 po návratu. Selfhost, callback, AI a tagged targeted testy
procházejí.

Generic `sum()` Int výsledek je od fixed pointu
`33ffa38bd74330dfb994e3381b1175260e7edb640ead157d50864d9ef6b31784`
na public Any hranici type 9; Float sum zůstává boxed Float. Targeted tagged
conformance pro nulu prochází.

Dictionary key ABI je explicitní ve fixed pointu
`ca68c11434a74c88fcbc4f71c478f67e658a6454caf8889affb11fbdc010705d`:
String/Int/Bool/None/Float/Function jsou tagované hashable scalar keys; mutable
collection/Dictionary/Class/Instance keys compiler odmítá s E2001. Positive i
negative targeted conformance prochází.

Process `run` fixed point
`caae0d045066544451443ec7c79e44840bab8004cfcb63b91fcde74d5a8ac61f`
dekóduje normální exit, signal jako `128+signal`, exec failure 127 a fork/wait
failure 126. Targeted process status conformance ověřuje exit 7 a missing exec.

Option descriptors nyní nesou declaration-file provenance a missing/type
chyby vypisují zdrojový modul; targeted invalid-type conformance prochází.

Config podporuje `config.lazy(thunk)` s rekurzivní materializací a aktivním
Function stackem; opakovaný thunk končí `ConfigCycleError`. Positive lazy
conformance, manual negative cycle a existující system config procházejí.

Structured capture fixed point
`500691c46d6c7a21a77e2076dbaeefef63183387fe0ff887b5d026302e4ec495`
uchovává dekódovaný status posledního capture v runtime state.
`process.capture_result` vrací `{stdout,status,ok}` a `process.check` propaguje
`ProcessError`; module je v installeru. Následující fixed point
`26f66960353e889aec2fee0dee4862773763cdaa5b6129c58f2c8eb7ef88a727`
zachytává také neomezené stderr přes anonymous memfd (bez pipe deadlocku) a
vrací `{stdout,stderr,status,ok}`. Conformance ověřuje stdout, uncaught stderr a
exit 1.

Input-syntax compatibility fixed point
`d3657e13366ccdad3e601a11da4614b35b405b9c29400ef0427eecf4931f32e0`
obnovuje původní výrazovou syntaxi `input "prompt"` jejím snížením na stejný
call AST jako `input("prompt")`. `hello.lsl`, stdin-fed process conformance,
full suite, config a installed fixed point prošly.

Fault-injection/fuzz fixed point
`e3bb05e634d2ffbd2e4d7efff2ce71236b59191868fd47f1e4582572ceedf5e3`
přidává test-only RLIMIT_NOFILE/memfd fault helper. Full runner skutečnými kernel
failures ověřuje pipe failure i stav, kdy pipe uspěje a stderr memfd selže,
včetně catchable `ProcessError`, status resetu a fd cleanup. close(2) cleanup je
dokumentovaný best-effort bez EINTR retry. Generativní config corpus navíc
ověřuje 100 defaults/overrides, 25 force priorit, List merge a assertions přes
strict JSON checker. Rozšířený full suite (včetně fuzz a GC stress) běží 15,0 s,
fast 4,2 s a fixed-point 3,7 s; všechny skončily 0.

Fuzz/GC hardening fixed point
`bd640ff9bd6e5f08dd657b3be7ef88e7025cffd227859c7c9801718b988e88cd`
přidává 1000 deterministicky generovaných lexer/parser programů, 200 JSON
round-trip případů, 24 malformed JSON vstupů a standalone GC stress s 10000
cykly, 3000-uzlovým grafem a reuse sérií. JSON decoder nyní bounds-checkuje,
odmítá trailing data, invalidní number/escape/surrogate gramatiku, přijímá
Float exponenty a správně skládá surrogate pairs. Deep equality má identity
fast path a visited-pair ochranu, takže self/cross-cyclic List/Dictionary grafy
neskončí stack overflowem. Rozšířený full suite skončil 0.

Process-I/O hardening fixed point
`80ce6a7a62242bc2197c86335c4be64865cb0f2ed9a2d93c24711d42cf4635a0`
kontroluje capture pipe/memfd/fork, parent read/wait/lseek a child dup2 chyby,
čistí všechny již otevřené deskriptory a propaguje catchable `ProcessError`.
`executable_path()` kontroluje readlink failure/truncation. Nový
`capture_input(program, args, text)` používá seekable memfd místo stdin pipe,
takže se nezablokuje na velkém vstupu; `process.capture_input_result` a
`process.check_input` poskytují structured API. Conformance posílá 100000B řádek,
ověřuje stdout/stderr/status i exec failure a je součástí agregovaného full
suite. Child dup/close pořadí je navíc ověřené s předem zavřenými fd 0, 1, 2
i všemi třemi současně. Full/fast/fixed-point, deset dalších fixed stages a
config prošly.

Výkonnostní a deterministický fixed point
`d986f572c3bb82734222af7ace3de2ce2c526ed94cc5be0841258accffdd4615`
přidává raw-or-boxed Int normalizaci v byte encoderu, lexer-validované Int tokeny
parsuje přímým trust-core runtime helperem a uchovává jejich hodnotu v AST.
Odstranil tak vzácnou (přibližně 1/10–1/30 high-memory self-host běhů) záměnu
boxed payloadu při dynamickém `bytes.little`; 30 + 10 následných fixed-point
reprodukcí bylo bitově shodných. Self-host compile klesl z 3,951 s na 3,615 s a
peak RSS přibližně z 809 MiB na 764 MiB.

Pozitivní testy jsou nyní linkované v `tests/full_conformance.lsl` do jednoho
ELF. Linker kvůli tomu správně namespacuje i module-level proměnné uvnitř
control-flow bloků, respektuje parameter/local shadowing a transformuje `del`.
Výstup agregátu je přesnou konkatenací původních `.out`. Plný runner klesl z
23,205 s na 9,425 s (−59 %), `fast` běží 3,667 s a `fixed-point` 3,610 s;
všechny tři režimy skončily 0. Config conformance zůstává bitově shodný.

Finální předvýkonnostní hardening fixed point
`0177dfcf593825157b60ea0f2962b7a6d39f4b4eaab8992d7e8eda7b0670706a`
opravuje partial-read smyčku `readfile`, kontroluje lseek/read/input errors a
opravuje type-flow augmented assignment tak, aby dynamický Float výsledek nebyl
znovu boxován jako Int. Celý `tests/lsl-test` skončil 0 s `pure LSL
tests passed`; config output je bitově shodný, všechny udržované ELF mají jediný
RX `PT_LOAD` bez `INTERP`, produkční strom nemá `.c/.h/.py/.sh`. Installer byl
ověřen v `/tmp/lsl-final-prefix`: nainstalovaný compiler z jiného cwd přeložil
selfhost conformance a z relativního instalovaného source rootu vytvořil bitově
shodný fixed point. Následuje měřená optimalizace.

Scalar ABI fixed point
`6dac5db225ab61f87c28837c03c20d7c390b7c61cbebfcca6a9df5df544459ef`
metadata-taguje Int/Bool/None/Function callback returns, taguje polymorfní Any
branches a normalizuje všechny dynamic arithmetic/equality boundaries. Audit
intrinsic vytvoří raw Int bitově shodný s adresou živého List objektu; přes
function/List/Dictionary/GC zůstává type 9 a nikdy se nerovná objektu.
Object registry i String intern cache se při zaplnění zdvojnásobí a rehashují;
test je zmenší na 8 slots a vynutí několik růstů.

Feature scope LSL 0.5 bez GPU je tímto uzavřený: omezený foreign CPU ABI,
zero-copy CPU Tensor, live process/HTTP chunks, AI SSE/retry/cancellation,
structured process results a lazy/provenance config jsou implementované.

Další fáze je hardening/bugfix: dokončit zbývající raw Any callback return,
dynamický růst tabulek, úplné syscall failure paths, odstranit raw fallback a
dokázat nemožnost live-pointer kolize; potom full suite/audit a zrychlení. Následuje pure-LSL in-process
zero-copy tensor/shared-object loader.

Výkonnostní fixed point
`29d717fde4b57517291ef30c92606e73e6e0cbb4c059e39197db42bbeb794f7a`
redukuje self-host z 3,713–3,749 s / 782100 KiB na 1,804–1,830 s / 376236
KiB (přibližně −51 % času a −51,9 % peak RSS). Compiler-internal ABI drží
typované Int/Bool/None a vybrané Any hranice raw; lexer/parser/linker/codegen
materializují source lines pouze při diagnostické chybě; x86 encoder zapisuje
little-endian immediate přímo do cílového Listu a počáteční dynamicky rostoucí
object registry má 8M místo 16M slots. Registry sleduje počet unikátních adres a
roste před překročením 50% obsazení; allocation benchmark tím odhalil a odstranil
patologický linear-probe běh 4M varianty. Tři self-host stages jsou bitově shodné,
regenerovaný full suite prošel za 8,843 s, fixed-point režim za 1,831 s, config
je bitově shodný a nainstalovaný compiler reprodukuje tentýž hash. Všechny
udržované ELF mají jediný RX `PT_LOAD` bez `INTERP`, `DYNAMIC` a RWX.

Native-performance fixed point
`25f26c531189d54e3659093dab3d81f6a10572e36661c34408e34962ff84ab37`
přidává explicitní `IntArray`: mutable contiguous pole raw signed Int64 bez
per-element heap objektů. Indexace a iterace jsou staticky `Int`, append/set
odmítají jiné typy, slicing zachovává typ, GC značí backing bez interpretace raw
slotů a rendering/equality/List conversion jsou pointer-collision safe. Původní
200000-prvkový/10-pass benchmark klesl z mediánu 785331 us / 189472 KiB na
9070 us / 9780 KiB; GCC 15.3 `-O3` má 1850 us / 3240 KiB. Rozdíl je tedy přibližně
4,9× čas a 3,0× RSS místo 425× / 58,5× dynamického Listu. Regenerovaný full suite
(8,923 s), fixed point (1,824 s), config, installer a ELF audit prošly. Další
native-performance kroky jsou `FloatArray`/Tensor kernels a `ByteArray`.

Dokončený native-memory fixed point
`b54092549bf5e5a651e8295172009c6e3d69816c66d21a43ae2e6a64c2ade94a`
přidává raw contiguous `FloatArray`, packed `ByteArray`, přímé binary
`readbytes`/`writebytes`, Float64 `sum`/`dot`/`axpy`/`matmul` kernely a Tensor
data wrappers. 200k×100 dot je přibližně 1,2× C při nižším RSS; 64×64 matmul
(20 průchodů) 2,3× C při srovnatelném RSS. IntArray benchmark po malém mmap
registry klesl na 8288 us / 3584 KiB (4,5× C / 1,1× RSS) a tiny program na
přibližně 1776 KiB. Packed byte scalar loop je stále 21,5× C, ale bulk file I/O
zapisuje/čte backing přímo bez per-byte objektů či kopie. Object registry nyní
začíná u běžných programů na 64K mmap slots, roste při 50% obsazení a starou mapu
vrací přes `munmap`; compiler profil si ponechává 8M start kvůli rychlosti.
Opraveno i shadowing lokálního `left`/`right` proti stejně pojmenovaným globálním
typům a class-return inference pro modulové Tensor konstruktory. Regenerovaný full suite (9,744 s), fixed point (2,020 s), config,
installed fixed point, ELF a pure-production audit prošly.

Cleanup fixed point
`02c4b72be6fc33b87ed763bb164d85109893b5d1998171b8fff2772a6ed4e54b`
soustřeďuje veškeré testy, fixtures, smoke drivery i LSL-generovaný runner pod
`tests/`; příklad je v `examples/hello.lsl`. `compiler/pure/` nyní obsahuje
výhradně 18 produkčních LSL modulů/entrypointů a 4 generované release ELF.
Linker umí testům dohledat compiler moduly bez jejich kopírování. Full suite
(13,421 s), fixed point (2,094 s), config, installer a ELF audit prošly.
Produkční implementace (`compiler/pure/*.lsl` + `stdlib/*.lsl`) má 12454 fyzických
řádků, z toho 11728 neprázdných nekomentářových řádků.

Optimalizující-codegen fixed point
`15ef7f3e07e65e3d78ad30dee2aa016caa34c0cc9de684318afd83d9dd703ae5`
přidává signed-correct kompaktní MOV/immediate/disp8/prologue encoding, Int
constant folding, constant branch/loop pruning, terminal dead-code elimination,
immediate scalar aritmetiku/compare/branch, přímou statickou equality,
deduplikaci String templates a guarded specializaci neunikajících přímých
funkcí. Callbacky a introspekční programy zůstávají na tagged Any ABI; pointer
collision corpus prochází. Compiler ELF klesl z 857964 na 669920 B (−21,92 %),
tiny ELF z 71977 na 53634 B (−25,48 %) a 2M volání triviálního helperu z mediánu
2,976 s na 0,006 s. Pětiběhový self-host medián je 2,030 s proti 2,136 s; peak
RSS je 420436 KiB proti 406200 KiB. Full suite (10,056 s), fixed point (2,024 s),
config, installed fixed point, ELF i pure-tree audit prošly. Produkční LSL
implementace má nyní 13237 fyzických / 12482 neprázdných nekomentářových řádků.
Praktický programming guide a compiler/release guide jsou v `docs/programming.md` a
`docs/compiler-development.md`.

Time/stdin fixed point
`de2318717ddad01786b49adabe50041b0fb717f0b35ebd3b5424e50f8b908b47`
přidává standardní `time.time`/`now` (CLOCK_REALTIME),
`monotonic`/`perf_counter` (CLOCK_MONOTONIC) a EINTR-safe syscall-only
`time.sleep`. No-argument `lsl` přes `ioctl(TCGETS)` rozliší TTY od pipe,
načte společný `<stdin>` zdroj do přesného řádku `exit` nebo EOF a jednou jej
přeloží/spustí; pipe/heredoc nevypisuje prompty. Interní input EOF marker nyní
rozlišuje prázdný řádek od skutečného EOF. Full suite testuje terminated stdin,
EOF, `exit` vs `exit(7)`, stdlib lookup, realtime/monotonic/sleep i config zákaz
ambientního času. Full (12,785 s), fixed point (2,059 s), config, installed
fixed point z kanonické relativní source cesty, installed stdin/time, ELF a
pure-tree audit prošly. Produkční implementace má 13403 fyzických / 12633
neprázdných nekomentářových LSL řádků.

OS/stdin fixed point
`7822a3a60e3361ce05ecbfdc2890a0bb538d1c01de0dfe402acb6d026b1928a8`
přidává standardní pure-LSL `os` modul s command String/List tokenizerem,
quotes/backslash, PATH lookup, přímým `execve`, run/capture/result/check a argv
variantami. Modul nikdy nepouští `/bin/sh -c`; shell metaznaky jsou obyčejné
argumenty a config režim `load/from os` i interní process aliasy odmítá. Corpus
ověřuje quoted/empty argumenty, PATH `ls`, inherited stdout, capture stdout/stderr,
status, check, missing executable 127 a parse errors. Pipe dokumentace nyní končí
jen EOF a heredoc jen jedním shellovým `EOF` markerem bez vnitřního `exit`; TTY
si ponechává `exit`/Ctrl-D. Full (15,850 s), fixed point (2,135 s), config,
installed fixed point/os/stdin, ELF, markdown links a pure-tree audit prošly.
Produkční implementace má 13550 fyzických / 12768 neprázdných nekomentářových
LSL řádků.

LuxOS package helper zachovává fixed point
`7822a3a60e3361ce05ecbfdc2890a0bb538d1c01de0dfe402acb6d026b1928a8` a
přidává běžný imperativní standardní modul `system`, nikoli nový config jazyk.
`system.install/update/remove(name)` nejprve spustí přímým argv `lux` a při
nenulovém statusu použije `apt`, případně `apt-get`; explicitní `*_with`
varianty podporují custom cesty/chroot a hermetické testy. Apt update jednoho
balíčku používá `install --only-upgrade`. Jména jsou validovaná, shell se nikdy
nespouští, chyba posledního backendu je `PackageError` a čistý `lsl config`
modul `system` odmítá. Mock Lux/apt corpus, full (13,448 s), fixed point
(2,068 s), legacy config, installer/installed modul+fixed point, ELF, markdown
a pure-tree audit prošly. Produkční implementace má 13648 fyzických / 12852
neprázdných nekomentářových LSL řádků.

LuxOS system completion zachovává fixed point
`7822a3a60e3361ce05ecbfdc2890a0bb538d1c01de0dfe402acb6d026b1928a8` a
rozšiřuje normální LSL modul `system` o APT refresh, hostname/timezone/locale,
systemd enable/disable/restart/status, idempotentní groups/users, bezpečné
mazání, mktemp+rename atomické soubory, directories, mountpoint-aware mounty a
wrappery existujících LuxOS check/apply/status/generations/rollback operací.
Externí příkazy jsou vždy přímé argv a explicitní `*_with` varianty umožňují
custom paths/chroot i hermetický corpus bez zásahu hosta. Přímé operace nejsou
předstírány jako atomická transakce; generation boundary je `lux apply` a
`rollback`. Lux package katalog/exists protokol je po potvrzení uživatele
odložen na další krok. Full (15,159 s), fixed point (2,071 s), config,
installer/installed system corpus+fixed point prošly. Produkční implementace má
14176 fyzických / 13316 neprázdných nekomentářových LSL řádků.

Lux archive manifest support zachovává fixed point
`7822a3a60e3361ce05ecbfdc2890a0bb538d1c01de0dfe402acb6d026b1928a8` a
přidává pure-LSL strict codec `lconf` pro budoucí `.lux/config.lconf` dependency
zdroje `apt`, `lux` a `lsl`. Parser podporuje opakované řádky a comma lists,
vrací vždy tři Lists, odmítá unknown sources, invalid/empty names a duplicity a
udržuje přesné path:line diagnostiky. Encoder zapisuje deterministicky po jedné
dependency. Dokumentovaný rezervovaný `.lux` layout je POSIX tar s `ABOUT`,
`config.lconf` a jedním executable; katalog/signatures/server jsou záměrně
odložené. Full (14,832 s), fixed point (2,086 s), config a fresh installed
lconf/fixed point prošly. Produkční implementace má 14259 fyzických / 13392
neprázdných nekomentářových LSL řádků.

Per-user registry fixed point
`dc25f32f18a8f3544e659366f4aee332ab050ec6c57dd322624b81282088999c`
přidává `lsl install NAME` pro jednosouborové knihovny z dočasného HTTPS
registru. Klient validuje jméno/URL, limituje curl protokoly a velikost, ověřuje
lowercase SHA-256, používá content-addressed staging, zkušební compile, mód 0644
a atomický move do `~/.local/lib/lsl/stdlib`. Built-in/system moduly mají před
uživatelskou cestou přednost. Hermetický corpus pokrývá úspěch, hash mismatch,
path jméno a precedence; skutečný Netlify download `textkit` i `statkit`, tři
shodné self-host stages, full suite, config, fresh installed fixed point a ELF/
pure-tree audit prošly. Diskless LuxOS může bez curlu použít certificate-checking
BusyBox wget pouze pro přesný dočasný Netlify origin; cílený skutečný download i
opakovaný full suite prošly. Finální CLI hash je
`f0a3f68ad0a33c0fb52277aa6a69176185960b5539510a3fc12477e4fd58ece3`.

Package update/config zachovává compiler fixed point
`dc25f32f18a8f3544e659366f4aee332ab050ec6c57dd322624b81282088999c` a
přidává `lsl update NAME` přes stejnou hash/compile/atomic cestu a
`lsl install --config FILE`. Config nejprve validuje celý nejvýše 64KiB/256
položkový seznam, komentáře, jména a duplicity. Hermetické update/config/negative
testy, skutečná Netlify instalace dvou knihoven a update, tři shodné stages,
full/fixed-point/config/installed-prefix a ELF audit prošly. CLI hash je
`a6865be3e25faeff295bfc2b31830d50fc5f10f6bb529e17fd8a4f334fe12109`.

GUI základ přidává stdlib `gfx` (IntArray Surface, rasterizace, 8x16
bitmapový font s českou diakritikou, PPM výstup) a `display` (32bpp XRGB
framebuffer přes /sys mode a writebytes present), oboje čisté LSL bez
runtime změn. Runtime nově emituje raw fd builtins `__lsl_fd_open`,
`__lsl_fd_read` (read count clampovaný na payload délku), `__lsl_fd_write`,
`__lsl_fd_seek` a `__lsl_fd_close` pro device I/O (/dev/input, trvalý
framebuffer fd); vracejí surový syscall výsledek a chyby zvedá stdlib
wrapper. Tři shodné stages, full suite, fixed-point, config a ELF audit prošly.

Následující fixed point opravuje tři chyby a mění environment API. Obě
execve cesty (run i capture) nyní předávají rodičovské envp z r15 místo
NULL, takže `./lsl program.lsl` i os/process children vidí environment.
`__lsl_parse_float` škáluje exponent exaktními mocninami deseti (10^22 je
největší přesný double) v jednom násobení/dělení na chunk, čímž je
převod monotónní; korekční smyčka formatteru navíc detekuje přemostění
cíle a bere bližší stranu, takže `FloatFormatError` už nemůže nastat
(DBL_MIN/DBL_MAX řádky v `float_format_conformance.out` mají přesnější
digity). Veřejný builtin `getenv` je odstraněn; environment čte pouze
modul `env` (`get`/`has`/`require`) přes interní `__lsl_getenv` a
bootstrap proběhl dvoufázově (přechodná registrace obou jmen). Tři
shodné stages, full+fast suite, fixed-point, config, installed-prefix a
ELF audit prošly. Compiler fixed point je
`9f731ff25ef998a9eba45b4e23a18c7148c42aaaaa0ad0c364c0546b76f44b7e`,
CLI hash je
`8381ddb576d021966cb09e9277278e4a32c3efbfe1eee1126ff8a2de2805a65f`.

Následující fixed point přidává okenní GUI. Runtime dostal socket
builtiny `__lsl_fd_socket` (41) a `__lsl_fd_connect` (42) a `__lsl_fd_write`
je přepsán na vlastní smyčku, která opakuje na EAGAIN, aby velký zápis do
nonblocking socketu dojel. Nad tím stojí čistě-LSL X11 klient
(`stdlib/x11.lsl`): unix socket, MIT-MAGIC-COOKIE-1 handshake, jedno okno,
ZPixmap PutImage po pruzích, WM_DELETE_WINDOW a normalizované události.
`stdlib/display.lsl` je sjednocený `Display` s backendy x11/framebuffer za
jedním present/poll/should_close API (klávesové kódy jsou pro oba backendy
linuxové/evdev). `stdlib/gfx.lsl` byl refaktorován na volné `raster_*`
funkce nad raw pixel bufferem, na které Surface metody delegují a které
používá i nový `stdlib/ui.lsl` (label/button/checkbox jako Dictionary,
`process`/`paint`, callbacky přes sdílený state Dictionary). Návrh je
vynucený tím, že LSL volá metody jen na staticky typovaných lokálech nebo
`self`, ne na parametrech ani vnořených memberech — proto jsou display/
gfx operace dostupné i jako volné funkce a event loop vlastní aplikace.
Compiler fixed point (stdlib změny ho nemění, socket builtiny ano) je
`511a0027d7f062cd31c8212a704936ffcc043ef86f5fd4ef1dc15de53aadadae`,
CLI hash je
`a0e4234b2b3deef46dfc307bf9734cdad8c653275c6296c748626bc2cb3c748f`.
Odhalený codegen bug (zatím neopravený, workaround: cast na typovaný
lokál): `bytearray.append(vypočtená hodnota)` na Any-typed parametru
zapíše poškozenou hodnotu; `ByteArray(param)` cast to obejde.

Liquid glass GUI (pouze stdlib, compiler beze změny): `gfx` má compositing
v celočíselném fixed-pointu (alpha blending, diagonální gradient,
anti-aliased zaoblené obdélníky s alpha a měkkým feather stínem, AA
škálovaný text) — naivní float verze byla ~450x pomalejší a boxovala.
`stdlib/css.lsl` parsuje podmnožinu CSS (barvy, linear-gradient,
border-radius) pro deklarativní vzhled. `examples/gui_glass_calc.lsl` je
kalkulačka v macOS „liquid glass" stylu s rekurzivním vyhodnocením výrazu.
Odhalená vlastnost konzervativního GC: v render smyčce falešně drží
krátkodobé snímkové buffery (stale ukazatele na zásobníku), takže paměť
rostla ~200 MB/s; `display.present` proto volá `gc()` každý snímek (paměť
je pak konstantní) a `display.wait_frame` stropuje FPS odděleně od
present. put_image/read_events používají znovupoužitelné buffery. Přesnější
GC (stack mapy) je budoucí runtime úloha.

Následující fixed point přidává nativní rastrové kernely — per-pixel
smyčky GUI stacku přesunuté do runtime: `__lsl_raster_fill(arr, off,
count, value)` (souvislý IntArray fill), `__lsl_raster_copy(dst, src,
dst_off, src_off, count)` (řádková kopie IntArray→IntArray, dopředná) a
`__lsl_raster_pack(src, dst, src_off_px, dst_off_bytes, count_px)`
(0xRRGGBB → little-endian BGRX; jeden 64bit load + 32bit store na pixel,
nový encoder `x86_64.store_dword_indexed`). Všechny tři ověřují heap type
code (13/15) a clampují offsety/počty na skutečné délky polí, takže špatné
volání je no-op, ne poškozená paměť; skalární argumenty jdou přes
`runtime_unbox_dynamic_int` (Any i raw). `display.present`/`present_rect`
balí řádky přes pack kernel, `gfx` `raster_clear`/`raster_hline`/
`raster_fill_rect`/`raster_fill_circle`/`raster_blit` volají fill/copy a
přibyl `gfx.raster_copy_rect` (obnovení výřezu z cache pozadí — kurzor).
Měřeno na 1920x1080 (LSL_FB_DEV soubor, medián): present 24.2→6.3 ms,
raster_clear 6.2→3.7 ms, raster_blit 9.8→5.6 ms, fill_rect 640x360
0.63→0.18 ms. Konformance `tests/raster_kernel_conformance.lsl` pokrývá
clamp, Any hranici i type-mismatch no-op. Tři shodné stages, full suite,
fixed-point, config, installed-prefix i ELF audit prošly. Compiler fixed
point je
`8ec9ff3760004e9ca77e8be21ec8124b5a8ef6a045ea94e82e7fb64707bbe839`,
CLI hash je
`f06e37ef0d9a42f5c523a6d7e60e9cfa4544390e6caeae0e954d60b9aa0afb18`.

CLI metadata fixed point přidává `lsl --help`, `lsl version` a
`lsl --version`; všechny veřejné verze jsou sjednocené na 0.5. Vývojářský
web chrání inline kód před Markdown emphasis/table parserem, takže se
operátory `*`, `**` a typy obsahující `|` vykreslují beze ztrát. Tři shodné
stages, full suite, fixed-point a Chromium DOM kontrola prošly. Compiler
fixed point je
`6a2a423a5f89955d260f44388b922876e9be82ad7090855e2918d67867fd414d`,
CLI hash je
`30e57d16ac3a938811130f5cd66af982e05ae1bac72ad99497535660ba1e7712`.

LSL 0.6 mění operátor mocniny z `**` na pravostranně asociativní `^`
(stará syntaxe má negative test), přidává first-class Lux String
`l"text {expression}"` s doslovnými `{{`/`}}`, kompatibilní lowering `printl`
a statický alias celého modulu `load module as alias`. Interpolace se linkuje
už jako běžný AST, takže uvnitř fungují module namespaces i vlastní funkce.
Codegen skládá konstantní String concat, malé Int mocniny 0–4 emituje inline
a Lux String staví vyváženě. Nový `stdlib/cuda.lsl` implementuje testovaný
process worker profil pro devices/sum/dot/axpy/matmul, politiku
auto/required/off a CPU fallback; Tensor jej používá automaticky. Full i fast
suite, fixed-point, installed-prefix fixed-point a audit všech tracked ELF
(jeden `R E LOAD`, bez INTERP/DYNAMIC/RWE) prošly. Compiler fixed point je
`86e96b8c67d6dfc4c1972ce3cc845550f5abf88fd73d577a88300519ceb8f42f`,
CLI hash je
`86cee21b92956f0adc7f664942902b77b5c23f2fb209cb889fb966a50c9a98a1`.

CUDA follow-up nahrazuje pouhý protocol profil bundlovaným skutečným NVIDIA
CUDA Runtime workerem. Probe i sum/dot/AXPY/tiled-matmul spouštějí device
kernely; FloatArray přenos používá raw binární stdin/stdout. Hardware
conformance, Compute Sanitizer memcheck/racecheck, full suite, fixed point a
instalovaná kopie prošly na GeForce GTX 1650 (CC 7.5). Compiler fixed point je
`615736f5a850871e397338ae5600fec09fcb702779158adfc7f8363f5c11c3d7`,
CLI hash je
`ad9a8d6b0011138f9907129ee155849592922a43e25d3f2d65625c403eacc5c0`
a stripped CUDA worker hash je
`bb41ff31291efdf01312067d44d079898ea1b6cd1ce97bf25d8ba0aaf125721b`.

LSL 0.6.3 přidává přímé short-circuit Boolean větvení, statický Bool hot path,
levnější první argument, 32bytové zarovnání funkcí a přímé/hoistované
`IntArray` operace. Lumen perft-5 je proti 0.6.2 přibližně 1,59× rychlejší.
Full suite, fixed point, config, instalovaná kopie a ELF audit prošly. Finální
compiler fixed point je
`f852f3d7b6b1d131ec45f7af2799664e961016d236e7944bd271ef17438c46e1` a
CLI hash je
`c8cbfee17d838c3150f96bab1220eb178791af6985d025a09747335d42414c61`.

Po 0.6.3 přibyla sdílená vlákna (`thread_runtime.lsl`: futex mutexy,
`clone`-based `thread_spawn`/`thread_join`, `CLONE_CHILD_CLEARTID` status,
SIGUSR1 stop-the-world handler pro `gc()` se scanem worker zásobníků) a SSE2
vektorizace FloatArray kernelů (`float_sum`/`float_dot` dvouakumulátorově,
`float_axpy`/`float_fill`/`float_matmul` bitově shodně; matmul i-k-j). Zámek
allokátoru je guardovaný příznakem prvního spawnu (bez vláken jen načtení
příznaku, self-host compile přibližně o 2 % pomalejší).
`tests/thread_conformance.lsl` je ve full suite. Full suite, fixed point,
config, instalovaná kopie a ELF audit prošly; compiler fixed point je
`4f1db957d5942d736d98700239665bd401829071185b465d25737fecafecfa95`.
Vydání 0.6.4 (verze v CLI, `help()`, `lux.version`, release note) má finální
compiler fixed point
`f57a02a58a7fba00a78f8dbfe8e2384f1acc1cf4491455524551eb35a8e03e57` a CLI hash
`e8ef227843a680123b969b363c7407bcddf5824fa63fae4e5d18472e424c14c4`.

Vydání 0.6.5 dokončuje optimalizaci `String(Float)`: odstranilo heapové sestavování a parsování
desetinného kandidáta z korekční i zkracovací smyčky: intrinsic nyní vytvoří
platný kandidát ve stackovém bufferu, úzký nativní parser vrátí raw IEEE-754
bity a porovnání neboxuje Float ani pomocné Stringy. Veřejný `Float(String)`
mutuje jeden privátní Float akumulátor místo dvou nových boxů na číslici, při
bitově shodném výsledku a diagnostice. Post-format kolekce se spustí teprve
při kombinaci 256 formátování a 4 096 nových adres v objektovém
registru, takže dlouhé smyčky mají omezenou paměť bez globální GC pauzy v
krátkém smíšeném programu. Původní reprodukce 60 000 převodů skončila bez
chyb s maximálním RSS 31 900 KiB místo přibližně 5,1 GiB; optimalizační ELF má
63 842 B pod limitem 64 000 B. Nový samostatný allocation conformance, fast i
full suite a fixed point prošly. Release 0.6.5 má compiler fixed point
`84adb2928bdb9115a4949906319b7845e111c165eb1f075c38754f7f3def3fca` a CLI hash
`b76b88da7bd434006c5b63a9f84efb7b6ef719d9982107a774d9533b663b06ae`.

Následná optimalizace `for` smyček odstranila zastaralé vyloučení jejich
skalárních řídicích proměnných z alokace registrů. Analýza nyní započítává i
syntetická čtení/zápisy čítače, indexu a explicitního kroku a složené
přiřazení počítá jako čtení i zápis. `rang(stop)` a `rang(start, stop)` mají
přímou kladnou větev s inkrementem o jedna bez zásobníkového step slotu a
testu znaménka. Na 1 000 000 000 iteracích se zachovaným checksumem klesl
medián aritmetické `rang` smyčky z 2,13 s na 0,83 s; jednoduchý součet
čítače z 1,67 s na 0,58 s a user CPU self-host kompilace z 2,09 s na 1,97 s.
Regrese pokrývá `rang` i `IntArray` iteraci. Tři stage dosáhly bitového fixed
pointu, fast/full suite, instalovaná kopie, config a audit všech regenerovaných
ELF prošly. Release audit navíc odstranil ASLR-závislou kolizi: staticky známý
raw Int se na tagged hranici boxuje přímo a už se předem neklasifikuje jako
možný heap pointer. Deterministická regrese používá číslo bitově shodné s
adresou živého boxovaného Intu; Float/String stress i opakovaný agregovaný
corpus zůstaly stabilní. Ve vydání 0.6.6 je compiler fixed point
`326db5b802778fefc6fd6e81f1741544c542446811ca9f32d5d2cf28d02f434b` a CLI hash
`821c00d035cfd9941e95eafcc898a392c1cf2a3aa5831e0485413653a2f594aa`.

Vydání 0.6.7 převádí všechny generované executable na statické PIE `ET_DYN` s
nulovou bází, jediným RX `PT_LOAD` a explicitním RW `PT_GNU_STACK`; opakovaná
spuštění mají rozdílný ASLR load bias. HTTP request config včetně secrets a
těla jde curlu přes stdin, vzdálené URL vyžadují HTTPS a hlavičky mají striktní
validaci. `capture_input_stream` kombinuje stdin se stream callbackem;
`plugin.request` používá JSON stdin, kontroluje exit status a argv transport je
jen explicitní legacy varianta. Native loader kontroluje map bounds a odmítá
relocation/dynamic či nekonzistentní section/symbol data. Test runner i CLI
používají per-process scratch cesty; dva paralelní fast suites, full suite,
fixed point, čistá instalace, živý loopback curl test a ELF audit prošly.
Compiler fixed point je
`d4dd94ec7fa3f491a58ff4cf84e49a04a399363b9aa513394c2472fe9269e894`, CLI
hash je
`305f1a00d50566a76422e2a8388a4f31d6eb9619c9f94a0fd8efac44efa93e1a`.

Vydání 0.6.8 je čistě bezpečnostní hardening. Alokátor, kolekce a všechny raw
I/O/memory hranice kontrolují overflow, typy, životnost objektů a rozsahy;
GC/equality mají fail-safe depth limity a worker stacky guard page. Process
helpery validují argv, zavírají zděděné deskriptory, omezují výstupy a umějí
prázdné prostředí; řízené capture endpointy si zachovají 0/1/2 přes `execve`
i když rodič vstoupil se zavřenými standardními deskriptory. HTTP vypíná
ambientní curl config i redirecty, omezuje
velikosti a dovoluje plain HTTP jen na numeric loopback. JSON, config, BigInt,
lexer, parser, linker a package vstupy mají resource limity. Dictionary hash
je per-process seedovaný. Native loader používá W^X, ownership přes GC a
serializovaný close/call; samotný kód běží v krátkodobém child procesu s
uzavřenými deskriptory, alarmem, `no_new_privs` a strict seccomp. Threat model
výslovně uvádí, že běžný LSL ani `__lsl_*` ABI nejsou sandbox a fork izolace
není confidentiality boundary. Resource resolver navíc odmítá stale
`prefix/lib` mimo skutečný `prefix/bin` install a používá kanonická source
jména, takže fixed point nezávisí na cestě executable. CUDA worker navíc
validuje celý JSON protokol a ABI, omezuje stdin, nesting, pole a device
buffery a je sestavený jako hardened PIE s full RELRO/NOW. Fast i full suite,
tři self-host stage, instalovaný fixed point a ELF audit prošly. Finální
compiler fixed point je
`8dcb2f2ec042f755413b3cc8c7c33a72726b5d073ea48b4bf498795feafe8d8a` a CLI
hash je
`c6af0ad2fa9058b38d6bbfbd7328a36275ac434fc76f96e8f4131fcd8e63ac00`;
stripped CUDA worker má SHA-256
`56334b8eee4363f1886bb5f0e66fcbcfbb86ef5ab2c0ca23dd35358629ef7114`.

Vydání 0.6.9 uzavírá audit veřejného dynamického ABI. Kolekce,
typed arrays, numerika, konverze, metody a I/O kontrolují runtime typy na Any
hranici; veřejné skalární výsledky se boxují bez odhadu podle heap adresy.
Opravené pointer-collision případy zahrnují `+`, `*`, `//`, `%`, `sum`,
`min` a `max`. `ByteArray` má slicing, Dictionary mazání chybějícího
klíče vrací `KeyError` a compiler odmítá chybné receivery i aritu metod,
`arg()` a privátních intrinsiců strukturovanou diagnostikou. Samostatné
boundary testy brání vyčerpání objektové tabulky agregovaného corpusu.
Tři self-host stage jsou bitově shodné; fixed-point, fast/full suite, config,
čistá instalace a ELF audit prošly. Compiler fixed point je
`f535e20469dd299bb05eee47020fd82d0c2298850816ddde502e627efa7564ce`, CLI
hash je
`957040c2a491918e7e08220a8d6996d5e8520ec112bbf8d152773a4b1fe6f69a`;
CUDA worker zůstal bitově beze změny s hashem
`56334b8eee4363f1886bb5f0e66fcbcfbb86ef5ab2c0ca23dd35358629ef7114`.

Vydání 0.7.0 odděluje původ balíčků od serverového příkazu:
`lsl origin [NAME]` čte striktní provenance sidecar a `lsl server` spouští
omezený syscall-only GET/HEAD HTTP server. Statické cesty jsou připnuté přes
directory fd a otevírané `openat2` s beneath/no-symlink policy; HTTPS deleguje
TLS 1.2/1.3 systémovému nginx/OpenSSL bez plaintext fallbacku. Nový
`lsl sandbox` používá bubblewrap namespaces, čisté prostředí, explicitní
read/write bind capabilities, systemd cgroup a prlimit/timeout limity.

Parser/linker/codegen současně přidávají lexikální `unsafe:`. Veřejný CLI
kontroluje celý uživatelský importní graf a bez bloku odmítá raw `__lsl_*`,
native a `thread_spawn`; sandbox překlad unsafe kód odmítá vždy. Nejde o plný
Rust borrow checker. Opravena byla hranice interního raw ABI compilerových
nástrojů vůči veřejnému tagged Any ABI modulů, včetně regresního případu
`Int(0)` versus `None`, a přibyla skutečná šestargumentová syscall brána.

Tři nové self-host stage byly bitově shodné. Fast i finální full suite,
`lsl config`, čistá instalace, installed-prefix fixed point, audit sedmi
pure-LSL ELF a reálné loopback HTTP/HTTPS smoke testy prošly. Audit čisté
instalace odhalil a uzavřel regresi důvěryhodného generovaného config wrapperu;
nový CLI test ji hlídá. Následný serverový audit nahradil socketový `write`
úplnou `sendto(MSG_NOSIGNAL)` smyčkou; TCP-reset regrese prošla 10/10 a brání
ukončení celého serveru přes `SIGPIPE`. Compiler fixed point je
`d19fbb95f937344a74118b4ab7dfc0a9c0d9c2398ede44705899757ea33094fa`, CLI
hash je
`942e5fc4dd93e492309cb1f4bffacdbdaef720ad2f80f73b497a139f7caf436b` a test
runner má
`4ad8b40fd02d146693a03dd62d91e7b6915bbc2a028037bf4bb77399516d72cf`.
Vydání obsahuje reprodukovatelné binární a zdrojové archivy, nový snapshot
manuálu 0.7 a tag `v0.7.0`.

Vývoj 0.7.1 stabilizuje hranice přidané v 0.7 bez nové syntaxe. Safe validator
nově prochází i slice step; linker cachuje relativní moduly podle vyřešené
cesty a používá nekolidující graph-order prefix. Modulová funkce `origin()` se
už nezaměňuje za receiver `origin.method()`. Interní raw ABI je explicitní AST
provenance z markeru `# lsl: internal-abi`, nikoli substring source path, takže
uživatelský adresář `compiler/pure/` nemůže vypnout veřejné tagged kontroly.

Package install/update a `lsl origin NAME` sdílejí per-package `flock`, lock
odmítá symlink i special file a origin znovu ověřuje instalovaný SHA-256.
HTTP přijímá přesně 64 polí, vyžaduje neprázdný Host, otevírá statické soubory
nonblocking a po `fstat` odmítá FIFO/device/socket; chyba handleru se izoluje na
500 a odpověď je omezená na 8 MiB. Config denylist doplnil `check` a `printl`.
CLI materializuje dočasný ELF až po úspěšném codegenu a uklízí config/sandbox
chybové cesty.

Finální 0.7.1 fixed point, fast i full suite, čistá instalace, fixed point
instalovaného compileru, config diff a ELF audit prošly. Compiler hash je
`b907fc2b8d68b55ae94d2838531bf705e8ab663f0e22002695840ecec64eb899`, CLI
hash `d11dc6cb2cd26273555c64d807d53e640588f3cd4d2720f2e89967b3f87fbb57` a
test runner hash
`43c012844351f5449e881ee3900c75c0aa5cc567916a3064b177480f939615fd`.
Vydání obsahuje reprodukovatelné binární a zdrojové archivy a tag `v0.7.1`;
živý manuál je aktualizovaný bez nového kopírovaného snapshotu.

## Roadmap k "kompletní 1" (17 okruhů)

Produkční okruhy (tagged ABI, numerika, kolekce, GC robustnost, syscall I/O,
native/tensor ABI, AI vrstva, config, diagnostika, fuzz/bench/determinismus,
cleanup a dokumentace) jsou pro aktuální Linux x86-64 scope uzavřené.
Další targety, syntetická fault injection a případná změna definované
two's-complement Int overflow sémantiky jsou navazující práce, ne známé
blockery vydání 0.7.0. Aktuální seznam je v `TODO.md`.

Vydání 0.7.2 přidává request body dynamického HTTP serveru (`body`,
`body_text`, `Expect: 100-continue`, bounded čtení do 8 MiB) a prošlo
bitově shodným fixed pointem, plnou suite, config diffem a ELF auditem.
Compiler hash je
`cfe35706540168443f7a95982d3cac6f90a40d0775fcedd2cee00bc7a3b9de71`, CLI
hash `3e21c4e05838d374c756bbb7b48c2d571d1e2b87d7cdda03c4a2744487b60bcb` a
test runner hash
`d91aebca46bc75b07796c62c75bce02881ec10024385efa56a89c28ccf42ab59`.

Vydání 0.7.3 ruší pevný 8MiB body limit dynamického HTTP serveru
(`set_body_limit`, výchozí bez limitu, growth-buffer čtení) a prošlo
fixed pointem, plnou suite, config diffem a ELF auditem. Compiler hash je
`de0097e8921d217af1b74d18c8b0d22e6588b6cdf5243396b81c16da2a7275b3`, CLI
hash `5b39893f4f5245e28591814553fae799241b7b1af65fbc07dc60f4513a188f02` a
test runner hash
`1cb44cb88ebed259a754dc79004a8ebd7b5a06e3b5b122e699c396b0a6fba434`.

Vydání 0.7.4 opravuje `String.split` (byte-přesné kousky, lineární čas) a
prošlo fixed pointem, plnou suite včetně nové split konformance, config
diffem a ELF auditem. Compiler hash je
`b96874ce0c3c729c4111297491ba418506d81639ca1fe710bb5adeafd0ff8296`, CLI
hash `b730d9d8a9d1e9032b67bf1f7481a4720838cdcc91494ba94d02404c9c66fb83` a
test runner hash
`f184a95393d0e1786d3867f099dc2773032c31a3a7a99fc56ff4b4321a996770`.

Vydání 0.7.5 přidává per-request `gc()` do `serve_listener` (dlouhoběžící
listener už nevyčerpá alokátor; endurance konformance v child procesu) a
dokumentuje známý gc+thread deadlock s reprodukcí v `tests/known_issues/`.
Compiler hash je
`3fd701c3c850ec94ae9c7944b359ccea55038883968e3146edaab49b63bca837`, CLI
hash `07f13c9331cf3f57e8813d0b2decaa3204e956340f23c337ca7da7b7e039305b` a
test runner hash
`1117f3d14be4a5d7dff251774fb8baa9739d850abeda37d3e5b13003f7a9a81d`.

Vydání 0.7.6 nahrazuje jediný first-fit volný seznam 136 segregovanými
seznamy (přesné 8B biny do 1 KiB, class-ceiling 2K..1M, first-fit jen nad
1 MiB): alokace je O(1) a gc+thread "deadlock" z 0.7.5 (ve skutečnosti
lineární kolaps alokátoru) je opraven; reprodukce je povýšena na
konformanci. Compiler hash je
`828f1b56cc4020e3c850ce29aa129fc7c3ba2198ea008b333dbab10bd597e776`, CLI
hash `ebc29e380ad01880bd09337e35dd2d63204d0cd59d9ae1437ad9a7c02437ae0f` a
test runner hash
`d613672eb70c905c4c2ea912e54b3ecaf242e757dfc9559c15d1c6ebb647a31a`.
