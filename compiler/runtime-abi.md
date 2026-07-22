# Pure-LSL native runtime ABI

Stav: interní Linux x86_64 ABI verze 0.7. Není to veřejné plugin ABI.

## Strojová hranice

Compiler generuje SysV-like volání: prvních šest argumentů je v `rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9`, další argumenty jsou na zásobníku a výsledek je v `rax`. `r12` ukazuje na main/global frame, `r13` drží poslední error String, `r14` error flag a `rbx` adresu 64-byte allocator/GC state bloku rezervovaného přes `brk`.

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

String payload je UTF-8, ale jazykové `len`, indexace a slicing pracují s Unicode code points. List/Tuple/RealArray slots, Dictionary hodnoty a instance fields nesou dynamické hodnoty; staticky známé Int, Bool a None jsou na této hranici boxované. Generic truth, equality, comparison, numeric operations, rendering, JSON, conversions, indexing a `rang` přijímají raw i boxed Int. Typed Int fast path zůstává raw.

Object identity se už neurčuje hranicí ELF adresy. Každá alokace se zapisuje do exact open-addressed pointer registry; static String templates se při prvním použití klonují do heapu a internují podle template pointeru. Tím dynamické Int hodnoty nad `0x400000` zůstávají Int. K úplně jednoznačnému tag ABI ještě zbývá zapnout scalar boxování na Any function argument/return hranicích a poté odstranit raw fallback heuristiky; do té doby stále existuje teoretická kolize raw Int, jehož bits jsou přesně rovné adrese živého heap objektu.

## GC a vlastnictví

Heap používá conservative mark-sweep:

- roots jsou globální frame a aktivní native stack;
- List/Tuple/RealArray a Dictionary hrany se procházejí rekurzivně;
- cycles jsou podporované;
- sweep bloky vrací do size-aware free listu;
- `gc()` spouští collection explicitně.

ELF image má pouze RX `PT_LOAD`; mutable allocator stav, 16M-entry object registry a 64K-entry String-template intern table jsou mimo image v `brk` heapu. Interned Strings jsou explicitní GC roots.

## Exceptions

`r14 != 0` znamená pending error a `r13` nese String message. Přímá LSL volání po návratu kontrolují flag a skáčou do nejbližšího `safe`/`try` handleru, nebo vypíšou fatal error na stderr a skončí nenulově.

## Budoucí plugin ABI

Native shared-object/tensor ABI zatím není podporované. Budoucí loader musí být implementován v LSL, verzovat layout a ownership a nesmí odhalovat interní heap layout pluginům; viz `docs/native-plugins.md`.
