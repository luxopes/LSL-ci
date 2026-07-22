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
odkazoval na neexistující modul; přidán `stdlib/lux.lsl` (`version` = "0.7",
`name`, `identity`/`clamp`/`is_empty`) a zaregistrován v installeru — showcase
teď běží celý včetně `LSL 0.7`. Config systém je funkční: `lsl config ENTRY`
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

Přesný další krok: poslední raw-Int/live-pointer kolize přes jednoznačný scalar
tag ABI a pure-LSL in-process zero-copy tensor/shared-object loader. Izolované
process plugin ABI je hotové, ale není vydáváno za zero-copy náhradu.

## Roadmap k "kompletní 1" (17 okruhů)
Uživatel zadal 17 produkčních okruhů (tagged ABI, numerika, Tuple/RealArray,
collections, GC robustnost, syscall I/O, native/tensor ABI, AI vrstva,
NixOS config, arita/builtiny, fuzz/bench/determinismus/audit, cleanup, docs).
Postup je inkrementální: každý krok = konkrétní defekt → oprava → nový
conformance test → ověřený self-host fixed point. Hotovo z okruhu 2: validace
`Int(String)` a dynamické `Int(Any)` konverze; opravená Float `**` mocnina;
NaN/Infinity výpis a `String()`; IEEE-754 NaN comparisons; bezpečný
`INT64_MIN // -1` / `% -1` (místo SIGFPE pádu). Z okruhu 6: partial-write smyčka
(`runtime_write_all`) a CRLF strip v `input()`. Z okruhu 10: arita validace
builtinů i metod (dříve compiler segfaultoval na `len()` / `list.append()`).
Z okruhu 4: rekurzivní repr kolekcí v `print`/`String()` (dříve raw pointer);
`List + List` concatenation a `String * Int` repetition (dříve garbage). Zbývá zbytek okruhu 2 (float
round-trip formatting; obecný kontrolovaný integer overflow vyžaduje oddělit
wrapping interní aritmetiku od checked uživatelské — větší sémantický zásah,
protože `bytes.little` záměrně spoléhá na `*` wraparound) a okruhy 1, 3–17.
