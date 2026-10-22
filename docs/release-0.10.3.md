# Release LSL 0.10.3

Překladač nepotřebuje žádné externí nástroje: LuxIR 0.4.0 sám sestaví
a slinkuje programy pro všechny cíle (Linux, Windows, macOS, bare metal
RISC-V i WebAssembly). Balíky pro Windows už neobsahují LLVM a na macOS
nejsou potřeba nástroje Xcode.

## Změny

- Windows x64 a ARM64 bez MinGW a LLVM: LuxIR zapisuje objekty COFF
  (x86-64 bajtově jako GNU as, arm64 bajtově jako LLVM) a linkuje
  konzolové programy PE32+ s ASLR (high-entropy VA), DEP a zásobníkem
  8 MiB. Importy Win32 popisují soubory `.def` vedle runtime
  (`lib/lsl/compiler/qbe/windows-*/`), importní knihovny ani
  `llvm-dlltool` nejsou potřeba. Balíky pro Windows jsou proto výrazně
  menší (bez `llvm-mc.exe` a `lld.exe`); `lsl update` staré nástroje LLVM
  odsune spolu s předchozí verzí.
- macOS (Apple Silicon i Intel) bez Xcode a LLVM: LuxIR zapisuje objekty
  Mach-O bajtově jako LLVM a linkuje spustitelný Mach-O (PIE) s
  vypuštěním nepoužitých funkcí, voláním `libSystem` přes stuby a GOT
  navázané dyld při načtení a ad-hoc podpisem (na arm64 povinný).
- WebAssembly (`wasm32-wasi`, `wasm32-wasi-threads`) bez wabt: binární
  modul vyrobí LuxIR (vestavěný assembler WAT, výstup bajtově shodný
  s `wat2wasm`); překlad malého programu je asi o 15 % rychlejší.
- Bare metal RISC-V bez binutils: obraz pro desku (qemu `virt`) linkuje
  LuxIR v rozložení dřívějšího linker skriptu (paměťový obraz shodný s GNU
  ld).
- Překlad pro libovolný cíl spouští jen `lslc` a jeden běh `luxir -a -l`
  na každém hostiteli; hledání binutils, LLVM, Xcode a Homebrew zmizelo.
- Oprava: `tui.emit` kopíruje text po bajtech v lineárním čase; dlouhé
  snímky obrazovky se dříve skládaly kvadraticky (20 KB trvalo ~80 ms).

## Ověření

- LuxIR: objekty COFF a Mach-O bajtově shodné s referenčními assemblery
  na sondách instrukcí a relaxace, `tests/run` i celém runtime LSL pro
  Windows a macOS; programy PE32+ x86-64 běží ve wine, linker Mach-O
  ověřuje nezávislá kontrola rozvržení (relokace, dyld info, stuby,
  podpis), moduly WebAssembly shodné s `wat2wasm` na všech testech cílů.
- LSL: testy cílů v CI na skutečných strojích (Windows Server 2025 x64,
  Windows 11 ARM64, macOS 15 arm64 a Intel, Linux arm64), WebAssembly
  v Node a wasmtime, bare metal v qemu-system; nativní překladač na
  Windows a macOS přeloží všechny testy a sám sebe.
