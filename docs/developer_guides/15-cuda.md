# CUDA v LSL 0.7.7

LSL má NVIDIA CUDA backend pro dense Float64 výpočty. Compiler a host runtime
zůstávají pure LSL se syscalls; CUDA kontext a device memory vlastní izolovaný
`lsl-cuda-worker`. Verze 0.7.7 přidává persistentní session, device buffery,
elementwise operace, transpozici a `tensor.DeviceTensor`.

## Požadavky a hledání workeru

Distribuovaný worker je Linux x86_64 ELF sestavený CUDA Toolkitem 13.3 pro
`all-major` architektury. Vyžaduje kompatibilní NVIDIA driver, glibc a libstdc++.
CUDA Toolkit není pro spuštění potřeba. Vlastní build popisuje
README v adresáři `cuda/` zdrojového archivu. Ověřené zařízení je GTX 1650 (CC 7.5).

Installer kopíruje worker do `<prefix>/bin/lsl-cuda-worker`. Modul hledá:

1. cestu z `cuda.configure` (prázdná cesta hledání vypne);
2. `LSL_CUDA_WORKER`;
3. `lsl-cuda-worker` vedle spuštěného ELF;
4. `cuda/lsl-cuda-worker` pod adresářem spuštěného ELF;
5. `/usr/local/bin/lsl-cuda-worker`, potom `/usr/bin/lsl-cuda-worker`.

Pracovní adresář se automaticky neprohledává. Při spuštění programu z `/tmp`
nastavte cestu explicitně nebo použijte absolutní `LSL_CUDA_WORKER`.

## Konfigurace a zařízení

```lsl
load cuda
call cuda.configure("cuda/lsl-cuda-worker", "required", 0)
call cuda.set_device(0)
print cuda.probe(), cuda.devices(), cuda.backend()
```

`configure(worker, policy, min_elements)` nastaví worker, politiku a práh
jednorázových kernelů; vymaže cache probe. `set_device(index)` zvolí zařízení
pro příští operace a session, `device()` vrátí jeho index. Existující session
zůstává na původním zařízení. Konfiguraci měňte před spuštěním pracovních vláken.

Výchozí prostředí je `LSL_CUDA=auto`, `LSL_CUDA_DEVICE=0` a
`LSL_CUDA_MIN_ELEMENTS=400000000`. Index 0–255 se workeru předává explicitně
i přes izolované prázdné prostředí procesu.

| Politika | Jednorázové `*_data` | Nová `cuda.session()` |
|---|---|---|
| `auto` | CUDA nad prahem, při chybě CPU fallback | CUDA, při neúspěšné inicializaci CPU session |
| `required` | CUDA povinná bez ohledu na práh | CUDA povinná |
| `off` | CPU, worker se nespouští | CPU session |

Práh počítá prvky vektoru nebo `m*k*n` pro matmul. Limit transportu se
kontroluje samostatně podle velikosti vstupních a výstupních polí.
`probe()` spustí a ověří device kernel. `available()` vrací Bool, `backend()`
vrací `cuda` nebo `cpu`. Neúspěšný probe vrací `None` i v `required`;
výpočet a `devices()` v této politice propagují chybu.

## Persistentní výpočty

```lsl
load cuda
load tensor

call cuda.configure("cuda/lsl-cuda-worker", "required", 0)
s = cuda.session()
a = tensor.from_values([1, 2, 3, 4], [2, 2])
b = tensor.from_values([5, 6, 7, 8], [2, 2])
da = a.to_device(s)
db = b.to_device(s)
dc = da.matmul(db)
host = dc.to_host()
print host.data
call s.close()
```

Výsledek je `FloatArray([19.0, 22.0, 43.0, 50.0])`. Session vytvoří worker
a CUDA kontext jednou. Další příkazy jdou přímo přes Unix socket bez nového
procesu. Mezivýsledky zůstávají na GPU; data se vracejí při `download`,
`to_host`, `sum` a `dot`.

| Session | Význam |
|---|---|
| `s.backend`, `s.device` | Vybraný backend a index zařízení |
| `s.upload(FloatArray)` | Vlastní snapshot host dat, vrátí Buffer |
| `s.zeros(count)` | Nový nulový Buffer |
| `s.info()` | Počet bufferů a prvků; GPU také PID workeru |
| `s.synchronize()` | Počká na dokončení device práce |
| `s.close()` | Zavře spojení, uvolní device alokace; opakování je bezpečné |

| Buffer | Význam |
|---|---|
| `b.count` | Počet Float64 prvků |
| `b.download()` | Nezávislý host FloatArray se stejnými IEEE-754 bity |
| `b.sum()`, `b.dot(other)` | Redukce do jednoho Float |
| `b.add(other)`, `subtract`, `multiply`, `divide` | Nový Buffer, stejné délky |
| `b.scale(alpha)`, `b.relu()` | Nový Buffer |
| `b.fill(value)` | Vyplní existující Buffer a vrátí jej |
| `b.axpy(alpha, x)` | Změní `b = alpha*x + b` a vrátí jej |
| `b.matmul(other, m, k, n)` | Nový row-major Buffer délky `m*n` |
| `b.transpose(m, n)` | Nový row-major Buffer tvaru `n*m` |
| `b.free()` | Uvolní Buffer; opakování je bezpečné |

Každá session patří jednomu host vláknu; pro další vlákno vytvořte vlastní.
Buffery různých sessions nelze kombinovat ani na stejném zařízení.
Použití po `free` nebo `close` vyvolá `CudaResourceError`.

Volejte `free` u mezivýsledků a `close` po dokončení, také na chybové cestě
`try/else`. LSL GC není destruktor externích prostředků. Ukončení host procesu
zavře socket a worker uvolní kontext i buffery. Pád workeru nebo porušený
transport zneplatní session. U otevřené GPU session se chyba propaguje i v
`auto`, protože host nemá kopii všech mezivýsledků. Lze vytvořit novou session
a znovu nahrát vstupy.

## Tensor a pohledy

`Tensor.sum`, `dot`, `axpy` a `matmul` respektují offset a strides.
Necontiguous pohled se materializuje v logickém pořadí; AXPY zapíše výsledek
zpět do sdílených dat pohledu. `reshape` vyžaduje plný contiguous Tensor.
Prázdné tvary a matmul s nulovou vnitřní dimenzí jsou podporované.

`t.to_device(s)` materializuje i pohled a vrátí `DeviceTensor`. Ten má
`shape`, `dtype="Float64"`, `backend`, `rank()`, `size()`, `to_host()`,
`reshape(shape)`, `free()`, `sum()`, `dot(other)`, `matmul(other)`,
`transpose()`, `add(other)`, `subtract(other)`, `multiply(other)`,
`divide(other)`, `scale(alpha)`, `relu()`, `fill(value)` a
`axpy(alpha, other)`. Elementwise operace vyžadují stejné tvary; dot rank 1,
matmul a transpose rank 2. Broadcasting se neprovádí.

`DeviceTensor.reshape` sdílí Buffer. Uvolnění jednoho aliasu zneplatní všechny
jeho pohledy. Aritmetické operace a transpozice mají vlastní Buffer.

## Kompatibilní jednorázové API

`cuda.sum_data`, `dot_data`, `axpy_data`, `matmul_data` a stejné exporty
`tensor` zachovávají CPU fallback a FloatArray rozhraní. AXPY mění `y` na místě.

```text
lsl-cuda-worker --device 0 --binary sum COUNT
lsl-cuda-worker --device 0 --binary dot COUNT
lsl-cuda-worker --device 0 --binary axpy ALPHA COUNT
lsl-cuda-worker --device 0 --binary matmul M K N
```

Payloady jsou little-endian Float64: `values`, `left+right`, `x+y`,
`left+right`. Výstupy mají přesný počet bytů. Binární transport zachovává
nonfinite hodnoty a signed zero. Pořadí paralelní redukce a fused multiply-add
mohou změnit poslední bity výsledku oproti CPU; porovnávejte s tolerancí.

JSON ABI 1 zůstává pro metadata a starší workery:

```json
{"abi":1,"device":0,"operation":"cuda.probe","payload":{}}
```

Úspěch má `abi:1`, `ok:true`, `value`. Probe nového workeru uvádí
`backend:"nvidia-cuda-runtime"`, `verified:true`, `binary:true`,
`session_abi:2` a metadata zařízení. Worker bez `binary:true` používá JSON
operace `cuda.sum`, `cuda.dot`, `cuda.axpy`, `cuda.matmul`. Vadná binární
odpověď nového workeru se znovu neodesílá jako velký JSON.

## ABI 2 a limity

`lsl-cuda-worker --device INDEX --session` vrátí v ABI 1 cestu k socketu
v privátním adresáři `mkdtemp`. Přijme jednoho klienta stejného UID, odstraní
socket i adresář a obsluhuje spojení do EOF. Pokud klient nepřijde do 10 sekund,
startup prostředky se uklidí.

Frame obsahuje čtyřbytovou little-endian délku JSON hlavičky, hlavičku a
`bytes` bytů payloadu. Požadavek má `abi:2`, `operation`, `bytes` a
parametry `id`, `other`, `count`, `m`, `k`, `n`. Upload přenáší celé
pole; `fill`, `scale`, `axpy` jeden binární Float64. Odpověď má `abi:2`,
`ok`, `bytes`, případně `id`, `count`, `error`. Handly jsou kladná čísla,
během session se neopakují a neobsahují device adresu.

- ABI 2 hlavička: nejvýše 4096 bytů; JSON hloubka 64.
- Buffer a výstup: nejvýše 2 000 000 Float64 prvků.
- Session: nejvýše 256 živých bufferů a 32 000 000 živých prvků.
- Jeden příkaz včetně přenosu a kernelu: nejvýše 120 sekund.
- ABI 1: JSON nejvýše 4 MiB, JSON pole/výstup 131 072 prvků;
  jednorázový binární vstup nejvýše 32 000 000 bytů.
- CPU Tensor: nejvýše 32 rozměrů a 67 108 864 prvků.

Worker validuje rozsahy, tvary, délky, ABI a duplicitní používané JSON klíče.
Release ELF má PIE, plné RELRO, okamžitý binding, stack protector a
neproveditelný stack. Host socket má CLOEXEC a zápis bez SIGPIPE.

API pokrývá uvedené dense Float64 operace. Uživatelský CUDA C++ zdroj kernelů,
Float32/Float16, sparse operace, autograd, kolektivní multi-GPU operace a přímé
in-process driver ABI nejsou poskytované.

## Ověření a výkon

```text
LSL_CUDA_HARDWARE_TEST=1 ./tests/lsl-test full
./compiler/pure/lslc-direct tests/cuda_session_benchmark.lsl /tmp/cuda-bench
/tmp/cuda-bench 512 ./cuda/lsl-cuda-worker
```

Session conformance běží vždy na CPU; hardwarový režim porovnává stejný
očekávaný výstup s GPU. Testuje vlastnictví, use-after-free, prázdná pole,
nonfinite transport, tensorové pohledy, velký matmul a neplatné zařízení.

Měření 5. 9. 2026 na GTX 1650: 512×512, medián pěti běhů CPU 0,04325 s,
persistentní CUDA včetně downloadu 0,02228 s (1,94×). Inicializace session
včetně dvou uploadů 0,319 s. Kontrolní součet každého výsledku byl 134217728.
