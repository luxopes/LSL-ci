# Knihovna cuda

`load cuda`

Volitelný NVIDIA CUDA backend běžící jako oddělený proces
`cuda/lsl-cuda-worker` (napsaný v CUDA C++). Bez něj zůstává jádro
pure-LSL a tenzorové operace padají zpět na CPU. Knihovna pokrývá
detekci, persistentní session a device buffery.

## Detekce a stav

```lsl
cuda.available()     # True, pokud je worker dostupný
cuda.probe()         # podrobná sonda (worker, CUDA verze)
cuda.devices()       # seznam zařízení
cuda.device_count()  # počet zařízení
cuda.device()        # aktuální index zařízení
cuda.set_device(index)
cuda.backend()       # "cuda" nebo "cpu"
```

## Konfigurace

```lsl
cuda.configure(worker, policy, min_elements)   # cesta workeru a práh akcelerace
cuda.minimum_elements()
```

Operace pod prahem (výchozí rozumná hodnota) běží na CPU — režie
přenosu by jinak akceleraci přebila.

## Persistentní session a buffery

```lsl
session = cuda.Session()            # nebo cuda.session() (sdílená)
buffer = cuda.upload_to(session, values)
```

`Session` drží spojení s workerem přes roury; `Buffer` je Float64 device
buffer s operacemi `download`, `reduce`, `elementwise`, `matmul`,
`transpose` a kontrolou kompatibility. Podrobný životní cyklus a
hardwarové požadavky: `lsl man 15-cuda`.

## Příklad

```lsl
load cuda

print cuda.backend(), cuda.device_count()
if cuda.available():
    print cuda.devices()
end
```

## Související stránky

- `lsl man 15-cuda` — podrobná kapitola o GPU výpočtech
- `lsl man tensor` — tenzory a CPU fallback
