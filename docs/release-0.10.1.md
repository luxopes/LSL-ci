# Release LSL 0.10.1

Překladač běží nativně na **Windows a macOS**. Stejné programy, stejné
cíle (`--target`) jako v 0.10.0; backend je LuxIR 0.2.1.

## Balíky

| Archiv | Hostitel překladače | Assembler a linker |
|---|---|---|
| `lsl-0.10.1-linux-x86_64.tar.gz` | Linux x86_64 | GNU binutils |
| `lsl-0.10.1-linux-aarch64.tar.gz` | Linux ARM64 (Raspberry Pi, Android v Termuxu) | GNU binutils |
| `lsl-0.10.1-linux-riscv64.tar.gz` | Linux RISC-V 64 | GNU binutils |
| `lsl-0.10.1-windows-x86_64.zip` | Windows 10/11 x64 | LLVM `llvm-mc` a `lld` v balíku |
| `lsl-0.10.1-windows-arm64.zip` | Windows 11 on ARM | LLVM `llvm-mc` a `lld` v balíku |
| `lsl-0.10.1-macos-arm64.tar.gz` | macOS Apple Silicon | Xcode Command Line Tools |
| `lsl-0.10.1-macos-x86_64.tar.gz` | macOS Intel | Xcode Command Line Tools |

Balíky pro Windows obsahují `llvm-mc.exe` a `lld.exe` z oficiálního
vydání LLVM 20.1.8 (archivy ověřené SHA-256, licence Apache 2.0 s výjimkou
LLVM v `LICENSE-LLVM.txt` a `LICENSE-lld.txt`). Na Windows jde z nich
překládat i pro Linux, macOS, Android a bare metal.

## Změny

- Systémová vrstva překladače pro Windows a macOS (`host_portable.lsl`):
  - cesty s `/`, také zpětná lomítka ve zdrojových cestách,
  - dočasné soubory v `%TEMP%` nebo `$TMPDIR`,
  - nástroje `.exe` vedle překladače,
  - konfigurace vyhodnocená v čistém procesu s časovým limitem.
- Instalátor pro Windows a macOS (`install_portable.lsl`) kopíruje balík
  do prefixu. Výchozí prefix je `%LOCALAPPDATA%\Programs\LSL`, na macOS
  `/usr/local`. Seznamy souborů sdílí s linuxovým instalátorem
  (`install_files.lsl`).
- Výpis adresáře v runtime: interní vestavěná funkce
  `__lsl_list_directory(cesta)` vrací jména položek (Linux `getdents64`,
  Windows `FindFirstFileW`, macOS `opendir`/`readdir`). `lsl list` ji
  používá na Windows a macOS. Test `tests/list_directory_conformance.lsl`
  prochází na všech systémech kromě WASI a bare metal, kde výpis
  adresáře není.
- LuxIR v LSL na Windows a macOS bere paměť mimo GC z runtime, ne z
  `mmap` (LuxIR 0.2.1). Na Linuxu je generovaný kód stejný.
- Importní knihovny Win32 pro x86_64 se generují spolu s runtime. Na
  Linuxu už pro ně není potřeba balík MinGW.
- Oprava: dynamické `+` dvou seznamů nebo n-tic v kódu modulů překladače
  (rychlá cesta `add_any_raw`) spojovalo hodnoty jako text. Chyba byla
  i v 0.10.0; má registrovaný regresní test
  `tests/qbe/internal_list_concat.lsl`.

## Výkon

Proti vydaným binárkám 0.10.0 beze změny: mediány překladu i běhu se liší
o méně než 3 % (šum měření), velký zdroj (překladač) 3076 → 3098 ms
(+0,7 %). Rychlá cesta pro sčítání řetězců zůstala stejná jako v 0.10.0.

## Ověření

Na skutečných strojích v CI (Windows Server 2025 x64, Windows 11 ARM64,
macOS 15 Apple Silicon, macOS 15 Intel):

- všechny samostatné testy se přeloží nativním překladačem a projdou
  (92 na Windows, 98 na macOS; přeskočený je jen test vyžadující
  `extensions/` z repozitáře),
- překladač přeložený na stroji přeloží sám sebe bajtově shodně (stupeň 2
  = stupeň 3),
- `lsl-install` nainstaluje balík a nainstalovaný překladač přeloží a
  spustí program,
- `lsl about`, `lsl help` a `lsl list` fungují.

Na Linuxu prošly fixed point, plná sada a úplné `verify_release.py`.
Nástroje pro aarch64 a riscv64 se v emulaci (qemu-user s binutils cílové
architektury) přeloží samy bajtově shodně a 102 ze 103 nativně
přeložených testů projde. Jediná výjimka, izolované nativní volání, pod
qemu-user neběží ani s 0.10.0; na skutečném ARM64 v CI prochází. Překladač
pro Windows x64 se ve wine přeloží sám bajtově shodně.
Výsledky jsou v `tests/release/0.10.1/`.

## Známá omezení na Windows a macOS

- `lsl update` a knihovny z registru (`lsl install NÁZEV`, `lsl search`)
  zatím fungují jen na Linuxu. Ověření podpisu a archivu tam používá
  systémové nástroje. Na Windows a macOS se aktualizuje stažením nového
  balíku.
- `lsl config` hlídá jen časový limit, ne paměť a soubory.
- Binárky nejsou podepsané certifikátem ani notarizované. Ve Windows může
  varovat SmartScreen. macOS soubor stažený prohlížečem zablokuje
  (`xattr -dr com.apple.quarantine lsl-0.10.1`), `curl` ne.
- Na macOS potřebují jiné cíle než macOS LLVM z Homebrew
  (`brew install llvm`). WebAssembly potřebuje všude `wat2wasm`.
