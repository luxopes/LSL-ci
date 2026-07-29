# CUDA v LSL 0.6

LSL 0.6 poskytuje volitelnou GPU akceleraci přes modul `cuda`. Self-hosted
compiler ani výsledné LSL programy nelinkují libc, `libcuda` nebo CUDA Runtime.
CUDA kontext vlastní samostatný executable worker; když není dostupný, stejné
Tensor operace pokračují přes nativní FloatArray CPU kernely.

## Zapnutí

```text
export LSL_CUDA_WORKER=/opt/lsl-cuda-worker
export LSL_CUDA=auto
export LSL_CUDA_MIN_ELEMENTS=4096
```

`LSL_CUDA` přijímá:

- `auto` — CUDA pro dostatečně velké vstupy, při chybě CPU fallback;
- `required` — CUDA je povinná a chyba se propaguje jako `Cuda*Error`;
- `off` — worker se nespouští.

Program může stejné hodnoty nastavit bez environmentu:

```lsl
load cuda

call cuda.configure("/opt/lsl-cuda-worker", "auto", 4096)
print cuda.available()
print cuda.devices()
print cuda.backend()
```

## Tensor integrace

`tensor.Tensor.sum`, `dot`, `axpy`, `matmul` a jejich raw varianty
`sum_data`, `dot_data`, `axpy_data`, `matmul_data` používají CUDA dispatcher
automaticky. Veřejné typy a výsledky jsou stejné pro CPU i GPU.

```lsl
load tensor as t

a = t.from_values([1, 2, 3, 4], [2, 2])
b = t.from_values([5, 6, 7, 8], [2, 2])
c = a.matmul(b.data, b.shape)
print c.data
```

## Worker protokol `lsl-cuda-v1`

Transport používá `plugin` process ABI v1. Worker dostane jeden JSON argument:

```json
{"abi":1,"operation":"cuda.sum","payload":{"values":[1.0,2.0,3.0]}}
```

Vrací právě jeden JSON objekt na stdout:

```json
{"abi":1,"ok":true,"value":6.0}
```

nebo chybu:

```json
{"abi":1,"ok":false,"error":"CUDA device unavailable"}
```

Podporované operace a jejich payload:

| Operace | Payload | `value` |
|---|---|---|
| `cuda.devices` | `{}` | List metadata zařízení |
| `cuda.sum` | `{"values":[...]}` | Float |
| `cuda.dot` | `{"left":[...],"right":[...]}` | Float |
| `cuda.axpy` | `{"alpha":a,"x":[...],"y":[...]}` | nový List hodnot `y` |
| `cuda.matmul` | `{"left":[...],"right":[...],"m":m,"k":k,"n":n}` | row-major List délky `m*n` |

Referenční worker pro conformance je
[`tests/cuda_worker.lsl`](../tests/cuda_worker.lsl). Na produkčním stroji jej
nahradí executable používající NVIDIA CUDA Driver API, CUDA Runtime nebo
jinou implementaci stejného protokolu.

## Výkonnostní hranice

JSON a start procesu jsou záměrně bezpečné a přenositelné, ale nejsou
zero-copy. Proto `auto` používá výchozí práh 4096 prvků. Jeden request může
uvnitř workeru dávkovat GPU práci, každý současný LSL request je však
samostatný proces. Přímé sdílené device buffery a in-process CUDA driver ABI
nejsou v 0.6 veřejným kontraktem.
