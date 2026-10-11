# LSL 0.9.1 pro Linux x86_64

Spustitelné nástroje jsou v `bin/`, standardní knihovna, zdroj frontendu a
připnuté offline manuály v `lib/lsl/`. Instalace není nutná:

```text
./bin/lsl version
./bin/lsl program.lsl
./bin/lsl compile program.lsl program
./bin/lsl-install /absolutni/cesta/k/prefixu
```

Výchozí frontend a backend `bin/luxir` jsou napsané v LSL. Překlad vyžaduje
**GNU `as` a `ld` z binutils**, také při přímém spuštění zdrojového skriptu.
Výsledné programy jsou statické Linux x86_64 PIE ELF s ASLR a neproveditelným
stackem, bez libc a dynamického interpreteru. Spuštění už přeloženého programu
binutils nepotřebuje. C QBE se automaticky nepoužívá.

Stabilní vydání; `lsl version` vypisuje `0.9.1`. Podepsaný `lsl update`
sleduje stabilní kanál. Instalátor zachovává předchozí spravovanou generaci
pro `lsl update --rollback`. Další OS a architektury nejsou součástí vydání.

## Self-host

Frontend v balíku lze ověřit pomocí dodaného nativního LuxIR a systémových
binutils:

```text
(cd lib/lsl && ../../bin/lslc compiler/pure/lslc_qbe.lsl /tmp/lslc-next)
cmp bin/lslc /tmp/lslc-next
```

Relativní cesta zdroje musí odpovídat release buildu: compiler uchovává cesty
v diagnostikách, takže překlad s absolutní cestou může mít jiný kontrolní součet.
Kontrola samostatného backendu navíc vyžaduje jeho připnuté zdroje LuxIR.
**Git checkout** používá `tools/release/prepare_sources.py` a `release.json`
pro přípravu LuxIR a export manuálů LSL-Web se souborem `SOURCE.json`.
Tato příprava potřebuje Git a síť, případně lokální Git checkouty závislostí.

**Vydaný zdrojový archiv** už obsahuje připnuté LuxIR zdroje v
`build/dependencies/LuxIR`, skutečný adresář `docs/developer_guides` včetně
`SOURCE.json` a kanonické kopie `build/qbe/runtime.o` a `build/luxir/luxir`,
bez symlinků. Git metadata závislostí nepotřebuje. V rozbaleném zdrojovém
archivu nespouštějte `prepare_sources.py`; oba překladače i nástroje
reprodukujete offline přímo:

```text
python3 tools/release/build_release.py
```

`tools/release/verify_release.py` pak spustí úplné release kontroly.
Jeho migrační gate navíc potřebuje předem dostupný funkční balík 0.8.9
s instalátorem a sousedními nástroji; předejte jej pomocí
`--old-installer /cesta/k/lsl-0.8.9/bin/lsl-install`, nebo se použije
`~/.local/bin/lsl-install`. To je externí předpoklad migračního testu;
běžný self-host starší instalaci nepotřebuje. `bin/lsl-test` potřebuje
`tests/` ze zdrojového archivu.

## Známé omezení

Překlad i běh jsou stejně rychlé nebo rychlejší než 0.9.0. Překlad velkého
zdroje compileru zůstává pomalejší než v 0.8.9 (backend LuxIR, viz
`tools/qbe/LUXIR_BENCHMARK_20261011.md` ve zdrojovém archivu); výsledné
programy jsou rychlejší. Převod desetinného textu na Float není u části
sedmnáctimístných čísel správně zaokrouhlený (1–2 ulp); oprava je plánovaná
pro 0.9.2.

## Volitelné CUDA

CUDA worker je `bin/lsl-cuda-worker`. Host programy zůstávají statické
a při nedostupnosti GPU mohou používat CPU:

```text
./bin/lsl compile examples/cuda_session.lsl bin/cuda-example
LSL_CUDA=required ./bin/cuda-example
LSL_CUDA=off ./bin/cuda-example
```

Pokud výsledný program uložíte mimo `bin/`, nastavte `LSL_CUDA_WORKER` na
absolutní cestu k workeru. Pro CUDA je potřeba kompatibilní NVIDIA driver,
glibc a libstdc++; toolkit na cílovém systému není nutný. Volitelný vlastní
build workeru popisuje `cuda/README.md` ve zdrojovém archivu.

Český manuál a soubory ke stažení: [lsl.lux-ai.cz](https://lsl.lux-ai.cz/).
Web a manuály se vyvíjejí odděleně v projektu
[LSL-Web](https://git.lux-ai.cz/LuxAI/LSL-Web).
Licence: MIT, viz `LICENSE`. Kontrolní součty distribuovaných archivů jsou
v `SHA256SUMS` vedle souborů ke stažení.
