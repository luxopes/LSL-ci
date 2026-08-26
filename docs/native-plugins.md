# Plugin ABI

## Podporované: pure-LSL process ABI v1

`stdlib/plugin.lsl` poskytuje izolovanou plugin hranici bez shellu, libc nebo cizího loaderu:

```lsl
load plugin

value = plugin.request("/opt/my-plugin", "embed", {"text": "hello"})
# request_input je kompatibilní alias stejného bezpečného stdin transportu.
value = plugin.request_input("/opt/my-plugin", "embed", {"text": "hello"})
```

Plugin je executable (může být přímo LSL-generovaný ELF). Host jej spustí přes
`fork`/`execve`, request zapíše jako jediný JSON dokument na stdin a zachytí
jednu JSON stdout response. Payload ani token proto nejsou viditelné v
`/proc/*/cmdline` a transport není omezený Linux `MAX_ARG_STRLEN`. Staré
workery, které čtou JSON z argv, lze během migrace volat explicitním
`plugin.request_argv`; pro secrets není tato legacy varianta bezpečná.

Request:

```json
{"abi":1,"operation":"embed","payload":{"text":"hello"}}
```

Úspěšná response:

```json
{"abi":1,"ok":true,"value":{"vector":[1,2,3]}}
```

Chyba:

```json
{"abi":1,"ok":false,"error":"model unavailable"}
```

Host kontroluje exit status, ABI verzi, `ok`, prázdnou odpověď a propaguje
`PluginError`. Hodnoty jsou omezené na JSON-compatible typy. Shellová
interpolace se nepoužívá. Conformance ověřuje i nulový počet payload argv v
`tests/plugin_process_*`.

Tato hranice je vhodná pro AI model servery, GPU workery a pluginy, kde isolation a jednoduché ownership převažují nad zero-copy.

## Podporované: CUDA worker backend v 0.6

`stdlib/cuda.lsl` přidává profil `lsl-cuda-v1`. Bundlovaný
`cuda/lsl-cuda-worker` vlastní skutečný NVIDIA CUDA Runtime kontext, device
alokace, kopie a synchronizaci. Metadata používají process JSON ABI, velké
FloatArray vstupy používají raw binární stdin/stdout bez JSON serializace.
GPU kernely implementují probe, sum, dot, AXPY a tiled matmul.

```lsl
load cuda

print cuda.available(), cuda.devices()
result = cuda.matmul_data(left, right, m, k, n)
```

Worker se automaticky hledá v repozitáři a vedle LSL ELF, nebo se vybírá přes
`LSL_CUDA_WORKER`; politika `LSL_CUDA` je `auto`, `required` nebo `off`.
`cuda.probe()` potvrdí GPU až po správném výsledku device kernelu. V `auto`
režimu každá operace při absenci workeru nebo jeho chybě použije existující
FloatArray CPU kernel. Výchozí pracovní práh 400 000 000 lze změnit přes
`LSL_CUDA_MIN_ELEMENTS`. Portable protocol double je `tests/cuda_worker.lsl`,
skutečný device test `tests/cuda_hardware_conformance.lsl`.

## Podporovaný pure-LSL CPU/CUDA Tensor

`stdlib/tensor.lsl` poskytuje dense `Tensor` nad sdíleným `RealArray` nebo raw contiguous `FloatArray`: shape, strides, offset, dtype, bounds-checked get/set, reshape a explicitní zero-copy views. FloatArray cesta přidává syscall-only nativní Float64 kernely `float_sum`, `float_dot`, `float_axpy` a `float_matmul`; modul je exportuje také jako `dot_data`, `axpy_data` a `matmul_data`. V 0.6 tyto vstupy automaticky procházejí volitelným CUDA dispatcherem a zachovávají CPU fallback. Více Tensor objektů může sdílet stejný mutable data owner; změna přes view je okamžitě viditelná ostatním views.

## Podporované: omezené in-process CPU ET_DYN ABI v1

`stdlib/native.lsl` mapuje self-contained Linux x86_64 `ET_DYN` image přímo
přes syscalls, validuje ELF class/type/machine a všechny section/symbol/string
bounds, vyhledá symbol v `SHT_DYNSYM`, vytvoří opaque native Function a zavolá
ji s nejvýše šesti signed Int argumenty. Image se explicitně uvolní
`native.close`.

```lsl
load native
library = native.open("./kernel.so")
add = native.symbol(library, "add")
print native.call(add, [19, 23])
call native.close(library)
```

ABI v1 je záměrně omezené: image musí být position-independent, bez
relocations, dynamic sections, external symbols, libc a constructors;
`st_value` musí odpovídat file mapping offsetu a ležet v executable
`SHT_PROGBITS`. Vstup i výstup jsou Int64. Loader nepředává pluginu LSL heap
pointery. Malformed ELF, chybějící/undefined symbol, špatná architektura a
příliš široké/non-Int volání jsou odmítnuté. Conformance zahrnuje i poškozenou
section tabulku a zakázanou relocation sekci.

Bohatší CPU ABI může v další verzi přidat explicitně povolené `R_X86_64_RELATIVE` relocations a opaque Tensor descriptors. Přímý in-process GPU/device ABI není součástí aktuálního scope; podporovaná CUDA hranice je izolovaný worker výše.

Process JSON ABI zůstává doporučená izolovaná hranice pro obecné pluginy;
omezený ET_DYN ABI je rychlá in-process CPU hranice pouze pro důvěryhodné
self-contained kernely. Loader umí odmítnout vadnou strukturu souboru, ale
nemůže zabránit memory-corruption chybě uvnitř už spuštěného C/C++ kódu. Pro
nedůvěryhodný nebo složitý native kód použijte krátkodobý worker omezený na
úrovni hostitele (namespaces/seccomp/cgroup, bez secrets a s minimálními
filesystem/network oprávněními).

## Hranice control plane

Release target LSL je Linux x86-64. Compiler, GC a codegen nemají nezávislý
víceletý bezpečnostní audit a stdlib nenahrazuje vyzrálý PostgreSQL,
TLS/OAuth/OIDC ani telemetry ekosystém. Bezpečnostní kořen služby proto držte v
hostitelském runtime s auditovanými knihovnami; LSL i C++/CUDA používejte jako
oddělené krátkodobé workery. Statické PIE bez interpreteru je pro tuto roli
výhoda, ne důvod přesunout do LSL celý control plane.
