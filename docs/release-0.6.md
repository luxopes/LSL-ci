# LSL 0.6

Lokální self-hosted vydání 0.6 navazuje na první veřejnou self-hosted verzi
0.5. V této fázi není nasazené na Netlify.

## Jazyk

- Mocnina používá `^`; původní `**` je syntaktická chyba.
- `^` zůstává pravostranně asociativní.
- `l"text {expression}"` je first-class interpolovaný String.
- `{{` a `}}` v Lux Stringu zapisují doslovné závorky.
- `printl "..."` zůstává zpětně kompatibilní.
- Celý modul lze aliasovat přes `load test as t`.

## Výkon

- Konstantní String concat se skládá při překladu.
- Mocniny s konstantním exponentem 0 až 4 se emitují inline.
- Lux String s více poli používá vyvážený concat strom.
- Stávající constant folding, dead-code elimination, immediate aritmetika,
  magic division a leaf-register emission zůstávají aktivní.

## CUDA

- Bundlovaný `cuda/lsl-cuda-worker` skutečně používá NVIDIA CUDA Runtime.
- GPU kernely implementují probe, Float64 sum, dot, AXPY a tiled matmul.
- `cuda.probe()` vrátí úspěch až po spuštění a ověření kernelu na zařízení.
- FloatArray data používají binární stdin/stdout transport bez JSON převodu.
- Tensor tyto operace směruje automaticky přes CUDA nebo CPU fallback.
- Politiky `auto`, `required`, `off`, zařízení a práh lze řídit environmentem.
- Přenosný protocol test běží bez GPU; samostatný hardware conformance test
  byl ověřen na NVIDIA GeForce GTX 1650 (compute capability 7.5).
- Referenční první end-to-end matmul 1024×1024 na tomto stroji: CPU 11,73 s,
  CUDA 1,16 s. Malé úlohy zůstávají v `auto` na CPU kvůli startu procesu.

## Toolchain

- `lsl --version`, `lsl version` a `lsl --help` hlásí 0.6.
- Compiler zůstává bitově reprodukovatelný ve fixed pointu.
- Standardní instalace obsahuje `stdlib/cuda.lsl` i předkompilovaný
  `bin/lsl-cuda-worker`, je-li v pracovním stromu dostupný.
