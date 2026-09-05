# LSL 0.7.7 pro Linux x86_64

Spustitelné nástroje jsou v `bin/`, standardní knihovna a zdroj compileru
v `lib/lsl/`. Instalace není nutná:

```text
./bin/lsl version
./bin/lsl program.lsl
./bin/lsl compile program.lsl program
./bin/lsl-install /absolutni/cesta/k/prefixu
```

CUDA worker je `bin/lsl-cuda-worker`. Host programy zůstávají statické
a při nedostupnosti GPU mohou používat CPU. Příklad:

```text
./bin/lsl compile examples/cuda_session.lsl bin/cuda-example
LSL_CUDA=required ./bin/cuda-example
LSL_CUDA=off ./bin/cuda-example
```

Pokud výsledný program uložíte mimo `bin/`, nastavte `LSL_CUDA_WORKER` na
absolutní cestu k workeru. Pro CUDA je potřeba kompatibilní NVIDIA driver,
glibc a libstdc++; toolkit na cílovém systému není nutný. Volitelný vlastní
build workeru popisuje [cuda/README.md](cuda/README.md).

- [CUDA API a životnost prostředků](docs/cuda.md)
- [Poznámky k vydání](docs/release-0.7.7.md)
- [Český manuál a soubory ke stažení](https://lsl.lux-ai.cz/)

Self-host compiler lze ověřit bez externího toolchainu:

```text
(cd lib/lsl && ../../bin/lslc compiler/pure/lslc_direct.lsl /tmp/lslc-next)
cmp bin/lslc /tmp/lslc-next
```

Relativní cesta zdroje musí odpovídat release buildu: compiler uchovává cesty
v diagnostikách, takže překlad s absolutní cestou má jiný kontrolní součet.

`bin/lsl-test` potřebuje `tests/` ze zdrojového archivu. Licence: MIT, viz
`LICENSE`. Kontrolní součty distribuovaných archivů jsou v `SHA256SUMS` vedle
souborů ke stažení.
