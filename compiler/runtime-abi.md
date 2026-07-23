# Pure-LSL native runtime ABI

Stav: interní Linux x86_64 ABI verze 0.7. Není to veřejné plugin ABI.

## Strojová hranice

Compiler generuje SysV-like volání: prvních šest argumentů je v `rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9`, další argumenty jsou na zásobníku a výsledek je v `rax`. `r12` ukazuje na main/global frame, `r13` drží poslední error String, `r14` error flag, `r15` původní process stack a `rbx` adresu 88-byte allocator/GC/process state bloku rezervovaného přes `brk`.

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

String payload je UTF-8, ale jazykové `len`, indexace a slicing pracují s Unicode code points. List/Tuple/RealArray slots, Dictionary hodnoty a instance fields nesou dynamické hodnoty; staticky známé Int, Bool a None jsou na této hranici boxované. Generic truth, equality, comparison, numeric operations, rendering, JSON, conversions, indexing a `rang` přijímají raw i boxed Int. Typed Int fast path zůstává raw.

Object identity se neurčuje hranicí ELF adresy. Každá alokace se zapisuje do exact open-addressed pointer registry; static String templates se při prvním použití klonují do heapu a internují podle template pointeru. Veřejné Any argumenty, collection slots, polymorfní returns a callback returns používají jednoznačné scalar tagy 9/4/5/10; typed self-host trust core může uvnitř výrazu držet raw Int. `pointer_collision_conformance` vytváří raw Int bitově shodný s živou heap adresou a ověřuje správný typ/equality přes Function, List, Dictionary i GC hranice.

## GC a vlastnictví

Heap používá conservative mark-sweep:

- roots jsou globální frame a aktivní native stack;
- List/Tuple/RealArray a Dictionary hrany se procházejí rekurzivně;
- cycles jsou podporované;
- sweep bloky vrací do size-aware free listu;
- `gc()` spouští collection explicitně.

ELF image má pouze RX `PT_LOAD`. Mutable allocator stav a počáteční 64K-entry String-template intern table jsou v `brk` oblasti. Object registry je samostatný anonymous `mmap`: běžný program začíná na 64K slots, compiler profil na 8M slots; před překročením 50% occupancy se zdvojnásobí, deterministicky rehashuje a starou mapu vrátí přes `munmap`. Intern table se při zaplnění také zdvojnásobí a rehashuje v rostoucí `brk` oblasti. Interned Strings jsou explicitní GC roots. Selhání alokace nebo úplný probe končí deterministicky statusem 70 a `MemoryError`, nikoli zápisem přes neplatnou adresu nebo nekonečnou smyčkou.

## Process/I/O cleanup

`capture` kontroluje pipe/memfd/fork/read/wait/lseek/dup2 a propaguje setup/I/O chyby jako catchable `ProcessError`; `capture_input` připraví stdin v seekable memfd, takže velký vstup nemůže uváznout proti stdout pipe. Již otevřené deskriptory se na chybových větvích zavírají. Linux `close(2)` je cleanup best-effort a po `EINTR` se neopakuje: descriptor už může být uvolněný a retry by mohl zavřít nově recyklované fd. Cleanup chyba nepřepisuje původní operation error.

## Exceptions

`r14 != 0` znamená pending error a `r13` nese String message. Přímá LSL volání po návratu kontrolují flag a skáčou do nejbližšího `safe`/`try` handleru, nebo vypíšou fatal error na stderr a skončí nenulově.

## Native CPU plugin ABI

Omezený ABI v1 mapuje self-contained Linux x86_64 ET_DYN bez libc, relocations a external symbols. Opaque library/function objekty mají type 11/12; veřejné volání přijímá nejvýše šest Int64 a vrací Int64, takže plugin nikdy nevidí LSL heap layout. Viz `docs/native-plugins.md`.
