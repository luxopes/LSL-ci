# Pure-LSL native runtime ABI

Stav: interní Linux x86_64 ABI vydání 0.8.4. Není to veřejné plugin ABI.

## Strojová hranice

Compiler generuje SysV-like volání: prvních šest argumentů je v `rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9`, další argumenty jsou na zásobníku a výsledek je v `rax`. `r12` až `r15` jsou callee-saved registry pro statické Int/Bool lokály. `rbx` drží runtime state; `fs:0`, `fs:8`, `fs:16` nesou pending error, error flag a stack top vlákna. Stav a free-list hlavičky zabírají 1280 bajtů před globály.

Runtime je emitován přímo jako x86_64 bytes z LSL modulů. Nepoužívá libc, C ABI runtime, assembler ani linker.

## Heap objekty

Payload pointer ukazuje na hlavičku:

```text
+0   type: u64
+8   length/value: u64
+16  capacity nebo inline payload
+24  data pointer podle typu
```

Allocator před payloadem udržuje neveřejnou 32-byte GC hlavičku. Aktuální type codes:

- `1` String
- `2` List
- `3` Dictionary/Instance/Class reprezentace
- `4` boxed Bool
- `5` boxed None
- `6` boxed IEEE-754 Float
- `7` Tuple
- `8` RealArray
- `9` boxed signed 64-bit Int (přechodový dynamic ABI)
- `10` boxed Function code pointer (veřejné dynamic ABI; self-host backend používá interní raw typed fast path)
- `11` opaque native library handle
- `12` opaque native Function handle
- `13` contiguous raw `IntArray`
- `14` contiguous raw IEEE-754 `FloatArray`
- `15` packed `ByteArray`
- `16` `Set`: unique immutable elements in the boxed List layout

Set uses the List header, count, capacity and slot buffer. Its buffer and every
element are traced by GC exactly like a List. Private helpers may read/mutate
slots; public indexed get/set, slicing, append and Dictionary-key use reject it.
Iteration uses a separate checked type dispatcher, not public indexing. Set
equality ignores order, while iteration/rendering preserve insertion order.
The initial implementation uses linear equality lookup, not hash buckets.

String payload je UTF-8, ale jazykové `len`, indexace a slicing pracují s Unicode code points. List/Tuple/RealArray slots, Dictionary hodnoty a instance fields nesou dynamické hodnoty; staticky známé Int, Bool a None jsou na této hranici boxované. Generic truth, equality, comparison, numeric operations, rendering, JSON, conversions, indexing a `rang` přijímají raw i boxed Int. Typed Int fast path zůstává raw.

Object identity se neurčuje hranicí ELF adresy. Každá alokace se zapisuje do exact open-addressed pointer registry; static String templates se při prvním použití klonují do heapu a internují podle template pointeru. Veřejné Any argumenty, collection slots, polymorfní returns a callback returns používají jednoznačné scalar tagy 9/4/5/10; typed self-host trust core může uvnitř výrazu držet raw Int. `pointer_collision_conformance` vytváří raw Int bitově shodný s živou heap adresou a ověřuje správný typ/equality přes Function, List, Dictionary i GC hranice.

## GC a vlastnictví

Heap používá conservative mark-sweep:

- roots jsou globální frame a aktivní native stack;
- hrany kolekcí se procházejí iterativním intrusive worklistem bez alokace;
- cycles jsou podporované;
- sweep bloky vrací do size-aware free listu;
- collection je automatická podle byte-pressure; `gc()` ji může vyžádat výslovně.

GC hlavička bloku má kapacitu (+0), další heap blok (+8), druh/stav
(+16: 0 objekt, 1 volný, 2 raw buffer) a mark/free-list word (+24).
Raw buffer se pouze označuje, nikdy se jeho obsah neinterpretuje jako objekt.
Během mark fáze +24 zároveň nese intrusive worklist link (1 značí konec);
state+184 drží jeho hlavu. State+8 indikuje nehotový buffer pozastaveného
workeru: takový sweep nic neuvolní. State+144 počítá alokované bajty,
state+152 je rozpočet `max(4 MiB, 2 * live_bytes)`.

Automatické safepointy jsou na dokončených source-expression hranicích,
ne v alokátoru; explicitní unsafe a interní helpery je nemají. Slow path
ukládá registry do skenovaného stack frame. Koordinátorem je hlavní vlákno,
včetně timed-futex čekání v join; worker GC sám nespouští. Graf se prochází
až po pozastavení workerů. SIGUSR1 má SA_RESTART; process wait4 opakuje EINTR.

ELF image je statický PIE `ET_DYN` s nulovou virtuální bází, jediným RX
`PT_LOAD` a explicitním RW `PT_GNU_STACK`; nemá interpreter, dynamic sekci ani
relocace. Mutable allocator stav a počáteční 64K-entry String-template intern
table jsou v `brk` oblasti. Object registry je samostatný anonymous `mmap`:
běžný program začíná na 64K slots, compiler profil na 8M slots; před
překročením 50% occupancy se zdvojnásobí, deterministicky rehashuje a starou
mapu vrátí přes `munmap`. Intern table se při zaplnění také zdvojnásobí a
rehashuje v rostoucí `brk` oblasti. Interned Strings jsou explicitní GC roots.
Selhání alokace nebo úplný probe končí deterministicky statusem 70 a
`MemoryError`, nikoli zápisem přes neplatnou adresu nebo nekonečnou smyčkou.

## Process/I/O cleanup

`capture` kontroluje pipe/memfd/fork/read/wait/lseek/dup2 a propaguje setup/I/O chyby jako catchable `ProcessError`; `capture_input` připraví stdin v seekable memfd, takže velký vstup nemůže uváznout proti stdout pipe. Již otevřené deskriptory se na chybových větvích zavírají. Linux `close(2)` je cleanup best-effort a po `EINTR` se neopakuje: descriptor už může být uvolněný a retry by mohl zavřít nově recyklované fd. Cleanup chyba nepřepisuje původní operation error.

State offset `+88` drží interní EOF marker posledního `input`; veřejné CLI jím rozlišuje prázdný řádek od konce pipe. TTY detekce používá `ioctl(TCGETS)`. `time` modul používá `clock_gettime` a `nanosleep`; sleep po `EINTR` opakuje syscall se zbývajícím `timespec`.

## Exceptions

`r14 != 0` znamená pending error a `r13` nese String message. Přímá LSL volání po návratu kontrolují flag a skáčou do nejbližšího `safe`/`try` handleru, nebo vypíšou fatal error na stderr a skončí nenulově.

## Native CPU plugin ABI

Omezený ABI v1 mapuje self-contained Linux x86_64 ET_DYN bez libc, relocations a external symbols. Opaque library/function objekty mají type 11/12; veřejné volání přijímá nejvýše šest Int64 a vrací Int64, takže plugin nikdy nevidí LSL heap layout. Viz `docs/native-plugins.md`.
