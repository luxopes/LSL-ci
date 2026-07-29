# Plugin ABI

## Podporované: pure-LSL process ABI v1

`stdlib/plugin.lsl` poskytuje izolovanou plugin hranici bez shellu, libc nebo cizího loaderu:

```lsl
load plugin

value = plugin.request("/opt/my-plugin", "embed", {"text": "hello"})
# Pro velké JSON dokumenty:
value = plugin.request_input("/opt/my-plugin", "embed", {"text": "hello"})
```

Plugin je executable (může být přímo LSL-generovaný ELF). Host jej spustí přes
`fork`/`execve` a zachytí jednu JSON stdout response. `request` předává JSON v
argv; `request_input` jej streamuje přes stdin a není omezený Linux
`MAX_ARG_STRLEN`.

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

Host kontroluje ABI verzi, `ok`, prázdnou odpověď a propaguje `PluginError`. Hodnoty jsou omezené na JSON-compatible typy. Argumenty jsou oddělené argv; shellová interpolace se nepoužívá. Conformance je v `tests/plugin_process_*`.

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

`stdlib/native.lsl` mapuje self-contained Linux x86_64 `ET_DYN` image přímo přes syscalls, validuje ELF class/type/machine a section bounds, vyhledá symbol v `SHT_DYNSYM`, vytvoří opaque native Function a zavolá ji s nejvýše šesti signed Int argumenty. Image se explicitně uvolní `native.close`.

```lsl
load native
library = native.open("./kernel.so")
add = native.symbol(library, "add")
print native.call(add, [19, 23])
call native.close(library)
```

ABI v1 je záměrně omezené: image musí být position-independent, bez relocations, external symbols, libc a constructors; `st_value` musí odpovídat file mapping offsetu. Vstup i výstup jsou Int64. Loader nepředává pluginu LSL heap pointery. Malformed ELF, chybějící symbol, špatná architektura a příliš široké/non-Int volání jsou odmítnuté. Conformance vyrábí ET_DYN image pouze pomocí LSL `writebytes`, načte jej a in-process zavolá strojový symbol.

Bohatší CPU ABI může v další verzi přidat explicitně povolené `R_X86_64_RELATIVE` relocations a opaque Tensor descriptors. Přímý in-process GPU/device ABI není součástí aktuálního scope; podporovaná CUDA hranice je izolovaný worker výše.

Process JSON ABI zůstává doporučená izolovaná hranice pro obecné pluginy; omezený ET_DYN ABI je rychlá in-process CPU hranice pro důvěryhodné self-contained kernels.
