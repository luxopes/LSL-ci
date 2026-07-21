# Pure-LSL migration

## Goal
Produkční LSL musí mít pouze LSL zdroje: žádný C/C++ backend, runtime, libc,
assembler, linker, Python ani shell launcher. Compiler napsaný v LSL zapisuje
přímo Linux ELF64 a výsledky používají přímé Linux syscalls. Chyby vždy uvádějí
soubor, řádek, sloupec, výřez, caret, kód chyby a podle možnosti nápovědu.

## Target / definition of done
- První podporovaný target: Linux x86_64 (host ověřen jako `x86_64`).
- `lslc` je ELF vytvořený předchozím `lslc`, jeho jediný udržovaný zdroj je LSL.
- Runtime a standardní knihovna jsou LSL moduly; compiler je překládá a linkuje.
- Compiler přímo zapisuje ELF a nastaví executable mode přes syscall; žádné `cc`,
  libc, assembler ani externí linker.
- Stage N přeloží `compiler/pure/lslc_direct.lsl` na bitově shodný stage N+1.
- Po přechodu produkční strom/testy neodkazují na `.c`, Python ani shell.
- Conformance a config testy běží pouze přes LSL ELF seed a LSL programy.

## Plan
- [x] Potvrdit host/počáteční target Linux x86_64.
- [x] Zapsat zákaz cizího backendu jako tvrdou architektonickou podmínku.
- [x] Implementovat v LSL první diagnostický engine se source spans, kódem, caret výpisem a help textem (`compiler/pure/diagnostics.lsl`).
- [x] Implementovat v LSL první ELF64 writer a x86_64 syscall encoder bez assembleru/linkeru (`compiler/pure/elf64.lsl`).
- [x] Dokončit vertikální řez: literal `print`/`exit` -> samostatný statický syscall-only ELF (`compiler/pure/hello.elf`).
- [x] Rozšířit bootstrap writer o arbitrary-byte materializer pro plný x86_64 encoder (ověřeny bytes 0, 1, 127, 128, 129, 200, 255).
- [x] Implementovat samostatný Unicode lexer s token spans a strukturovanými lexical errors (`compiler/pure/lexer.lsl`).
- [x] Implementovat parser s token spans pro specifikaci 0.7 včetně linked-module source path/line/source anotací.
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
`compiler/pure/lsl-test` následně bez shellu/Pythonu spustil přes syscall-only
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

Přesný další krok: odstranit poslední teoretickou raw-Int/live-pointer kolizi
jednoznačným scalar tag ABI, doplnit zbývající RealArray numerické metody a
navrhnout pure-LSL in-process zero-copy tensor/shared-object loader. Izolované
process plugin ABI je hotové, ale není vydáváno za zero-copy náhradu.

## Roadmap k "kompletní 1" (17 okruhů)
Uživatel zadal 17 produkčních okruhů (tagged ABI, numerika, Tuple/RealArray,
collections, GC robustnost, syscall I/O, native/tensor ABI, AI vrstva,
NixOS config, arita/builtiny, fuzz/bench/determinismus/audit, cleanup, docs).
Postup je inkrementální: každý krok = konkrétní defekt → oprava → nový
conformance test → ověřený self-host fixed point. Hotovo z okruhu 2: validace
`Int(String)` a dynamické `Int(Any)` konverze; opravená Float `**` mocnina;
NaN/Infinity výpis a `String()`; IEEE-754 NaN comparisons. Zbývá zbytek okruhu 2
(float round-trip formatting, kontrolovaný integer overflow) a okruhy 1, 3–17.
