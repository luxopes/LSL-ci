# CUDA v LSL 0.6

LSL 0.6 obsahuje skutečný NVIDIA CUDA Runtime backend. Self-hosted compiler
ani výsledné LSL programy nelinkují libc, `libcuda` nebo CUDA Runtime; CUDA
kontext vlastní samostatný `lsl-cuda-worker`. Když worker nebo zařízení není
dostupné, politika `auto` použije stejné FloatArray operace na CPU.

Bundlovaný worker spouští na GPU tyto Float64 kernely:

- ověřovací device kernel;
- paralelní víceúrovňový `sum`;
- paralelní `dot`;
- `AXPY` (`y = alpha*x + y`);
- tiled 16×16 row-major `matmul`.

## Požadavky a hledání workeru

Předkompilovaný `cuda/lsl-cuda-worker` je Linux x86_64 binárka pro
architektury podporované CUDA 13.3. Potřebuje kompatibilní NVIDIA driver,
glibc a libstdc++. Vlastní build je popsaný v
[`cuda/README.md`](../cuda/README.md).

Modul hledá worker v tomto pořadí:

1. cesta předaná `cuda.configure`;
2. `LSL_CUDA_WORKER`;
3. `cuda/lsl-cuda-worker` v pracovním stromu;
4. `lsl-cuda-worker` vedle spouštěného ELF;
5. `/usr/local/bin/lsl-cuda-worker` a `/usr/bin/lsl-cuda-worker`.

Installer jej kopíruje do `<prefix>/bin/lsl-cuda-worker`.

Worker je samostatná cizí procesní hranice, ne součást statického LSL runtime.
Release binárka je PIE s plným RELRO, okamžitým bindingem, stack protector a
neproveditelným stackem. JSON požadavek je omezen na 4 MiB a 64 úrovní,
JSON pole na 131 072 prvků a binární transport na 32 MiB; binární pole, výstup
i device buffer mají limit 2 000 000 Float64 prvků. Parser vyžaduje celý
validní top-level objekt, ABI 1 a odmítá duplicitní používané klíče.

## Konfigurace

```text
export LSL_CUDA=auto
export LSL_CUDA_DEVICE=0
export LSL_CUDA_MIN_ELEMENTS=400000000
```

`LSL_CUDA` přijímá:

- `auto` — GPU použije pouze nad prahem a při chybě zachová CPU fallback;
- `required` — skutečné NVIDIA zařízení je povinné a chyba se propaguje jako
  `Cuda*Error`;
- `off` — worker se vůbec nespouští.

Prahová hodnota jsou pracovní jednotky: počet prvků pro vektorové operace a
`m*k*n` pro matmul. Výchozích 400 000 000 je konzervativní hodnota pro
samostatný proces a běžnou spotřebitelskou GPU. Konkrétní hardware je vhodné
přeměřit. Hodnota `0` v politice `required` se hodí pro hardwarové testy.

Stejné nastavení lze provést v programu:

```lsl
load cuda

call cuda.configure("cuda/lsl-cuda-worker", "required", 0)
probe = cuda.probe()
print probe["name"], probe["compute_capability"]
print cuda.devices(), cuda.backend()
```

`cuda.probe()` spustí kernel, zkopíruje jeho výsledek z device memory a vrátí
metadata pouze při správné hodnotě. `cuda.available()` je tedy potvrzení
funkčního CUDA kernelu, nikoli jen existence souboru nebo driveru.

## Tensor integrace

`tensor.Tensor.sum`, `dot`, `axpy`, `matmul` a raw varianty `sum_data`,
`dot_data`, `axpy_data`, `matmul_data` používají stejný dispatcher. Veřejným
datovým typem zůstává contiguous `FloatArray`.

```lsl
load tensor as t

a = t.from_values([1, 2, 3, 4], [2, 2])
b = t.from_values([5, 6, 7, 8], [2, 2])
c = a.matmul(b.data, b.shape)
print c.data
```

## Rychlý binární protokol

Výpočetní cesta nepřevádí velká pole do JSON. LSL runtime kopíruje raw
little-endian IEEE-754 Float64 data do stdin workeru a čte stejné bity ze
stdout:

```text
lsl-cuda-worker --binary sum COUNT
lsl-cuda-worker --binary dot COUNT
lsl-cuda-worker --binary axpy ALPHA COUNT
lsl-cuda-worker --binary matmul M K N
```

Payloady jsou po řadě `values`, `left+right`, `x+y` a `left+right`; výstup je
jedno Float64, jedno Float64, nové `y`, nebo row-major matice délky `M*N`.
Host kontroluje exit status i přesnou délku binárního výstupu.

Metadata a kompatibilní fallback používají JSON process ABI na stdin:

```json
{"abi":1,"operation":"cuda.probe","payload":{}}
```

Úspěšný skutečný worker vrátí například:

```json
{"abi":1,"ok":true,"value":{"backend":"nvidia-cuda-runtime","verified":true,"device":0,"name":"NVIDIA GeForce GTX 1650","compute_capability":"7.5","runtime_version":13030,"driver_version":13030}}
```

JSON operace `cuda.devices`, `cuda.sum`, `cuda.dot`, `cuda.axpy` a
`cuda.matmul` zůstávají součástí `lsl-cuda-v1`, aby fungoval přenosný
conformance double [`tests/cuda_worker.lsl`](../tests/cuda_worker.lsl).

## Reálné ověření a výkon

```text
./compiler/pure/lslc-direct tests/cuda_hardware_conformance.lsl /tmp/cuda-test
/tmp/cuda-test

LSL_CUDA_HARDWARE_TEST=1 ./tests/lsl-test fast

./compiler/pure/lslc-direct tests/cuda_hardware_benchmark.lsl /tmp/cuda-bench
/tmp/cuda-bench 1024
```

Na místním NVIDIA GeForce GTX 1650 (compute capability 7.5) hardware test
ověřil sum, dot, AXPY a matmul na CUDA. Referenční end-to-end měření
1024×1024 bylo přibližně 11,73 s na CPU a 1,16 s přes CUDA. U 128×128 bylo
naopak CPU 0,003 s a první CUDA dispatch 0,87 s, protože ověření i každý
výpočet vytváří nový proces a
CUDA kontext.

Persistentní worker, sdílené device buffery, zero-copy a přímé in-process CUDA
driver ABI nejsou veřejným kontraktem 0.6.
