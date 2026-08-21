# Changelog

Na této stránce jsou uživatelsky významné změny vydaných verzí. Stabilní
manuály a soubory ke stažení zůstávají dostupné v
[historii vydání](/releases/).

## Nevydáno

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

- [LSL 0.6 — manuál a soubory ke stažení](/releases/0.6/)
- [LSL 0.5 — historický manuál a soubory ke stažení](/releases/0.5/)
