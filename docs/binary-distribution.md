# LSL 0.10.2 pro Linux, Windows a macOS

Archiv obsahuje překladač pro jeden systém a architekturu hostitele
(Linux x86_64/aarch64/riscv64, Windows x64/ARM64, macOS Apple
Silicon/Intel). Spustitelné
nástroje jsou v `bin/`. V `lib/lsl/` je standardní knihovna, zdroj
frontendu, runtime všech cílů a připnuté offline manuály. Instalace není
nutná:

```text
./bin/lsl version
./bin/lsl program.lsl
./bin/lsl compile program.lsl program
./bin/lsl-install /absolutni/cesta/k/prefixu
```

Výchozí frontend a backend `bin/luxir` jsou napsané v LSL. Výchozí cíl je
architektura balíku. Pro program stejné architektury potřebujete **GNU
`as` a `ld` z binutils**:

- Debian a Ubuntu: `sudo apt install binutils`
- Raspberry Pi OS (64bitový): `sudo apt install binutils`
- Android v Termuxu: `pkg install binutils`

Na Windows obsahuje balík assembler a linker LLVM (`bin/llvm-mc.exe`,
`bin/lld.exe`, licence v `LICENSE-LLVM.txt` a `LICENSE-lld.txt`); nic
dalšího se instalovat nemusí (`bin\lsl.exe version`, `bin\lsl-install.exe`
nainstaluje do `%LOCALAPPDATA%\Programs\LSL`). Na macOS potřebuje překladač
Xcode Command Line Tools (`xcode-select --install`).

Binárky nejsou podepsané certifikátem vývojáře ani notarizované:

- **Windows:** SmartScreen může při prvním spuštění zobrazit „Systém Windows
  ochránil váš počítač“; pokračujte přes „Další informace“ → „Přesto
  spustit“. ZIP stažený prohlížečem lze předem odblokovat v PowerShellu:
  `Unblock-File lsl-0.10.2-windows-x86_64.zip`. Stažení přes `curl.exe` značku
  internetu nepřidá.
- **macOS:** soubor stažený prohlížečem dostane karanténu a Gatekeeper ho
  odmítne. Před spuštěním ji odstraňte: `xattr -dr com.apple.quarantine
  lsl-0.10.2`, nebo program jednou povolte v Nastavení systému → Soukromí
  a zabezpečení → „Přesto otevřít“. Stažení přes `curl` karanténu nepřidá
  a `lsl update` také ne.

Výsledné programy na Linuxu jsou statické PIE ELF s ASLR a neproveditelným stackem,
bez libc a bez dynamického loaderu. Spuštění už přeloženého programu
binutils nepotřebuje.

## Další cíle

```text
./bin/lsl compile --target windows-x86_64 app.lsl app.exe
./bin/lsl compile --target macos-arm64 app.lsl app
./bin/lsl compile --target wasm32-wasi-threads app.lsl app.wasm
./bin/lsl compile --target baremetal-riscv64 app.lsl app.elf
```

| Cíl | Nástroje na hostiteli (Debian/Ubuntu) |
|---|---|
| `linux-x86_64` | žádné (assembler i linker jsou vestavěné v LuxIR) |
| `linux-arm64` | žádné (assembler i linker jsou vestavěné v LuxIR) |
| `linux-riscv64` | `binutils`, pro jinou architekturu `binutils-riscv64-linux-gnu` |
| `windows-x86_64` | `binutils-mingw-w64-x86-64`, `mingw-w64-x86-64-dev` |
| `windows-arm64` | `clang`, `lld` |
| `macos-x86_64`, `macos-arm64` | `clang`, `lld` (`ld64.lld`) |
| `wasm32-wasi`, `wasm32-wasi-threads` | `wabt` |
| `baremetal-riscv64` | `binutils-riscv64-linux-gnu` |
| `linux-x86` | žádné (assembler i linker jsou vestavěné v LuxIR) |
| `linux-arm` | `binutils-arm-linux-gnueabihf` |

Spuštění na hostiteli bez cílového systému:

- WebAssembly: `wasmtime run -W threads=y -S threads=y -S inherit-env=y --dir . app.wasm`
  (vlákna; pro hlubokou rekurzi `-W max-wasm-stack=8388608`), nebo
  `node lib/lsl/tools/wasi_run.mjs app.wasm` (Node 24, také s vlákny).
- Bare metal RISC-V: `python3 lib/lsl/tools/baremetal_run.py app.elf`
  (qemu-system-riscv64, deska `virt`, 4 jádra; vstup a výstup přes
  semihosting).
- Linux arm64 a riscv64 na PC: qemu-user (`binfmt`).
- 32bitový Linux `linux-arm` (armv7, hard-float: Raspberry Pi OS 32bit,
  Android armv7) a `linux-x86` (i686 se SSE2): LuxIR vypíše assembler
  (backendy `arm` a `i386`), stačí binutils; `linux-x86` běží přímo na
  64bitovém jádře x86_64, `linux-arm` v qemu-user. Nativní knihovny
  (`native`) jsou zatím jen 64bitové.

Stabilní vydání; `lsl version` vypisuje `0.10.2`. Podepsaný `lsl update`
sleduje stabilní kanál na všech hostitelích (Linux x86_64, aarch64 a
riscv64, Windows x64 a ARM64, macOS arm64 a x86_64). Podpis Ed25519 i
SHA-256 archivu ověřuje sám překladač; na Windows a macOS stahuje systémový
`curl` a rozbaluje systémový `tar` (Windows 10 1803 a novější je mají).
Aktualizuje se instalace z `lsl-install`, ne rozbalený archiv. Předchozí
verze zůstává pro `lsl update --rollback`. Knihovny z registru
(`lsl install NÁZEV`) jsou zatím jen na Linuxu.

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
python3 tools/release/build_target_tools.py --target linux-arm64 --output /tmp/arm64 --layout
python3 tools/release/build_target_tools.py --target windows-x86_64 --output /tmp/win --layout --llvm DIR
```

Runtime ostatních cílů sestaví `tools/runtime/build.py --target NAME`.
`tools/release/verify_release.py` pak spustí úplné release kontroly.
Jeho migrační gate navíc potřebuje předem dostupný funkční balík 0.8.9
s instalátorem a sousedními nástroji; předejte jej pomocí
`--old-installer /cesta/k/lsl-0.8.9/bin/lsl-install`, nebo se použije
`~/.local/bin/lsl-install`. To je externí předpoklad migračního testu;
běžný self-host starší instalaci nepotřebuje. `bin/lsl-test` potřebuje
`tests/` ze zdrojového archivu.

## Volitelné CUDA

CUDA worker `bin/lsl-cuda-worker` je jen v balíku pro x86_64. Host
programy zůstávají statické a při nedostupnosti GPU mohou používat CPU:

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
