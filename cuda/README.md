# NVIDIA CUDA worker

`lsl-cuda-worker` je skutečný CUDA Runtime backend pro LSL 0.7.7. Proces vlastní
CUDA kontext, alokuje device memory a spouští NVIDIA kernely pro probe, Float64
sum, dot, AXPY, tiled matmul, elementwise operace a transpozici. Persistentní
ABI 2 uchovává device buffery mezi příkazy. LSL compiler ani výsledný host ELF na CUDA
knihovny nelinkují.

Repozitář obsahuje Linux x86_64 binárku sestavenou pomocí CUDA 13.3 pro všechny
hlavní architektury podporované tímto toolkitem. Vyžaduje kompatibilní NVIDIA
ovladač, glibc a libstdc++.

## Build

```text
/usr/local/cuda/bin/nvcc -O3 -std=c++17 -arch=all-major \
  -Xcompiler=-fPIE,-fstack-protector-strong,-D_FORTIFY_SOURCE=3,-Wformat,-Wformat-security,-Werror=format-security \
  -Xlinker=-pie,-z,relro,-z,now \
  cuda/lsl_cuda_worker.cu -o cuda/lsl-cuda-worker
strip --strip-unneeded cuda/lsl-cuda-worker
```

Jinou cestu k `nvcc` lze použít beze změny zdroje. `-arch=all-major` je vhodné
pro distribuovanou binárku; pro jediný stroj lze zvolit konkrétní `sm_XX`.
Release build je PIE s plným RELRO, okamžitým bindingem, stack protector a
neproveditelným stackem.

Zdroj `lsl_cuda_worker.cu` zahrnuje `session.cuh`; při buildu ponechte oba
soubory ve stejném adresáři. Session inicializuje CUDA až po fork, přijímá
jedno spojení stejného UID a uvolňuje buffery při EOF. Má nejvýše 256 živých
bufferů a 32 milionů Float64 prvků; buffer nejvýše 2 miliony prvků. Hlavička
má limit 4096 bytů a příkaz deadline 120 sekund. Toolkit není nutný na cíli.

Worker odmítá JSON nad 4 MiB, JSON pole nad 131 072 prvků, binární vstup nad
32 MiB, binární pole a device buffery nad 2 000 000 prvků, JSON hlubší než
64 úrovní, duplicitní používané klíče a neplatnou ABI verzi. Tyto limity platí
i při přímém spuštění workeru mimo LSL.

## Ověření

Probe není pouhý dotaz na driver: zapíše hodnotu CUDA kernelem do device memory,
zkopíruje ji zpět a až potom vrátí `"verified":true`.

```text
printf '%s' '{"abi":1,"operation":"cuda.probe","payload":{}}' \
  | ./cuda/lsl-cuda-worker

./compiler/pure/lslc-direct tests/cuda_hardware_conformance.lsl /tmp/cuda-test
/tmp/cuda-test

# Nebo jako opt-in součást celého suite:
LSL_CUDA_HARDWARE_TEST=1 ./tests/lsl-test full
```

Benchmark přijímá volitelný rozměr čtvercové matice:

```text
./compiler/pure/lslc-direct tests/cuda_hardware_benchmark.lsl /tmp/cuda-bench
/tmp/cuda-bench 1024
```

Podrobný protokol a konfigurace jsou v [docs/cuda.md](../docs/cuda.md).

Persistentní benchmark s kontrolními součty a mediánem pěti běhů:

```text
./compiler/pure/lslc-direct tests/cuda_session_benchmark.lsl /tmp/cuda-session-bench
/tmp/cuda-session-bench 512 ./cuda/lsl-cuda-worker
```
