# NVIDIA CUDA worker

`lsl-cuda-worker` je skutečný CUDA Runtime backend pro LSL 0.6. Proces vlastní
CUDA kontext, alokuje device memory a spouští NVIDIA kernely pro probe, Float64
sum, dot, AXPY a tiled matmul. LSL compiler ani výsledný host ELF na CUDA
knihovny nelinkují.

Repozitář obsahuje Linux x86_64 binárku sestavenou pomocí CUDA 13.3 pro všechny
hlavní architektury podporované tímto toolkitem. Vyžaduje kompatibilní NVIDIA
ovladač, glibc a libstdc++.

## Build

```text
/usr/local/cuda/bin/nvcc -O3 -std=c++17 -arch=all-major \
  cuda/lsl_cuda_worker.cu -o cuda/lsl-cuda-worker
strip --strip-unneeded cuda/lsl-cuda-worker
```

Jinou cestu k `nvcc` lze použít beze změny zdroje. `-arch=all-major` je vhodné
pro distribuovanou binárku; pro jediný stroj lze zvolit konkrétní `sm_XX`.

## Ověření

Probe není pouhý dotaz na driver: zapíše hodnotu CUDA kernelem do device memory,
zkopíruje ji zpět a až potom vrátí `"verified":true`.

```text
printf '%s' '{"abi":1,"operation":"cuda.probe","payload":{}}' \
  | ./cuda/lsl-cuda-worker

./compiler/pure/lslc-direct tests/cuda_hardware_conformance.lsl /tmp/cuda-test
/tmp/cuda-test

# Nebo jako opt-in součást celého suite:
LSL_CUDA_HARDWARE_TEST=1 ./tests/lsl-test fast
```

Benchmark přijímá volitelný rozměr čtvercové matice:

```text
./compiler/pure/lslc-direct tests/cuda_hardware_benchmark.lsl /tmp/cuda-bench
/tmp/cuda-bench 1024
```

Podrobný protokol a konfigurace jsou v [docs/cuda.md](../docs/cuda.md).
