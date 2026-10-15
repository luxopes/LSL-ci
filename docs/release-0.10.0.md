# Release LSL 0.10.0

Vydání nových platforem. Runtime LSL je nově napsaný v LSL a přenositelný,
backend je LuxIR 0.2.0. Z jednoho překladače vznikají programy pro
Linux, Windows, macOS, WebAssembly a bare metal RISC-V. Samotný překladač
je k dispozici pro Linux x86_64, ARM64 a RISC-V 64.

## Balíky

| Archiv | Hostitel překladače |
|---|---|
| `lsl-0.10.0-linux-x86_64.tar.gz` | Linux x86_64 (PC, servery, WSL 2, kontejnery) |
| `lsl-0.10.0-linux-aarch64.tar.gz` | Linux ARM64 (Raspberry Pi s 64bitovým OS, servery ARM, Android v Termuxu) |
| `lsl-0.10.0-linux-riscv64.tar.gz` | Linux RISC-V 64 |

Každý balík obsahuje runtime všech cílů, takže překládá pro všechny cíle.
Pro cíle stejné architektury jako hostitel použije systémové binutils
(`as`, `ld` v `/usr/bin`, v Termuxu v jeho prefixu). Pro ostatní cíle
použije jen nástroje daného cíle, nikdy nativní assembler jiné architektury.

## Cíle (`lsl compile --target NAME`)

| Cíl | Výsledek | Potřebné nástroje na hostiteli |
|---|---|---|
| `linux-x86_64`, `linux-arm64`, `linux-riscv64` | statický PIE ELF bez libc | GNU binutils (nativní nebo `x86_64-linux-gnu-`, `aarch64-linux-gnu-`, `riscv64-linux-gnu-`) |
| `windows-x86_64` | PE `.exe` nad Win32 | `binutils-mingw-w64-x86-64` a `mingw-w64-x86-64-dev` |
| `windows-arm64` | PE `.exe` pro Windows on ARM | `clang`, `ld.lld` |
| `macos-x86_64`, `macos-arm64` | Mach-O nad libSystem (arm64 s ad-hoc podpisem) | `clang`, `ld64.lld` |
| `wasm32-wasi` | modul WebAssembly (WASI preview1), jedno vlákno | `wat2wasm` (WABT) |
| `wasm32-wasi-threads` | modul WebAssembly se skutečnými vlákny (wasi-threads) | `wat2wasm` (WABT) |
| `baremetal-riscv64` | obraz ELF bez OS pro desku qemu `virt` | `riscv64-linux-gnu-` binutils |

Na Androidu běží programy pro `linux-arm64` přímo (statický ELF bez
loaderu).

## Runtime v LSL

- Alokátor, GC, řetězce, kolekce, čísla a převody, chyby, I/O, procesy,
  vlákna, nativní knihovny i start programu jsou v `runtime/*.lsl`.
  Instrukce procesoru jsou jen v malé vrstvě architektury
  `runtime/arch/*` a služby systému jsou ve vrstvě OS `runtime/os_*.lsl`
  (Linux přes systémová volání, Windows přes Win32, macOS přes libSystem,
  WASI, bare metal).
- **Windows:** konzole v UTF-8, procesy přes `CreateProcessW`, vlákna a
  zastavení světa pro GC přes `SuspendThread`, časové limity pluginů.
  Nativní knihovny běží v izolovaném dceřiném procesu s job objektem.
  Při pádu se vypíše kód výjimky a posun v obrazu. `httpserver` obsluhuje
  HTTPS přes nginx.
- **macOS:** nativní knihovny v dceřiném procesu se `sandbox_init`, sandbox
  procesů přes Seatbelt (`sandbox-exec`), `unixsock` s předáváním
  deskriptorů, HTTPS přes nginx (Homebrew, MacPorts).
- **WebAssembly:** soubory přes předotevřené adresáře WASI, hodiny,
  argumenty a prostředí. `wasm32-wasi-threads` má skutečná vlákna nad
  sdílenou pamětí. GC vlákna zastavuje kooperativně v bezpečných bodech
  LuxIR. Přetečení stínového zásobníku skončí zprávou
  `LSL runtime crash: stack overflow`. Spouštění:
  `wasmtime run -W threads=y -S threads=y -S inherit-env=y --dir . app.wasm`,
  nebo Node 24 přes `lib/lsl/tools/wasi_run.mjs` (i s vlákny).
- **Bare metal RISC-V:**
  - Program běží v S-módu se stránkováním Sv39: kód jen ke čtení a
    spuštění, strážní stránky pod zásobníky, zásobníky vláken 8 MiB.
  - Vlákna jsou preemptivní na všech jádrech (nejvýš 8).
  - RAM, UART a časovač se čtou ze stromu zařízení.
  - Vstup a výstup jde přes semihosting (soubory, argumenty a návratový
    kód hostitele), jinak přes UART.
  - Entropie pochází z CSR seed (Zkr).
  - Spouštění: `python3 lib/lsl/tools/baremetal_run.py app`
    (qemu-system-riscv64).

## Jazyk

- Volání funkce jako samostatný příkaz musí mít `call`, jinak překlad
  skončí chybou `function call result is discarded without call`. Bez
  `call` se smí zapsat jen metody objektů (`seznam.append(x)`) a vestavěné
  příkazy (`del`, `exit`, `check`, `Error`, `writefile` …).

## Výkon

Měřeno na stejném stroji, vydané binárky 0.10.0 proti vydaným binárkám
0.9.2, CPU čas dětských procesů, mediány 11 střídavých kol:

- Překlad malých programů je o 42 až 44 % rychlejší.
- Překlad velkého zdroje (překladač 0.9.2, 5 střídavých běhů) zrychlil
  z 5479 ms na 2791 ms (−49 %).
- Běh je rychlejší:
  - formátování −74 %,
  - parsování −55 %,
  - float_loop −60 %,
  - list_access −65 %,
  - dictionary_access −51 %,
  - string_split_join −54 %,
  - allocation_gc −55 %.
- integer_loop (−0,1 %) a intarray_access (−1,5 %) jsou beze změny.
  function_calls je v krátkém běhu šum; při 200 milionech volání
  připnutých na jedno jádro vychází 301 ms v obou verzích (9 běhů).

Podrobnosti jsou v `tests/release/0.10.0/`.

## Aktualizace

`lsl update` ověřuje podepsaný stabilní kanál na Linuxu x86_64 i aarch64:
stahuje archiv vlastní architektury a kontroluje stroj ELF instalátoru.
Platformy, které klient nezná, v manifestu přeskočí. Archiv pro RISC-V 64
zatím do kanálu nepatří, protože klienti 0.9.x by neznámou architekturu
odmítli. Na RISC-V se instaluje ručně z archivu.

## Ověření

- Fixed point frontendu i backendu na Linuxu x86_64 (`build_release.py`).
  Nástroje pro aarch64 a riscv64 přeložil tentýž překladač s `--target`.
  Na emulovaném aarch64 a riscv64 (qemu-user se systémovými binutils
  cílové architektury) se překladač i LuxIR přeloží samy a výsledek je
  bajtově shodný.
- Úplné `verify_release.py`: korpus, oba fixed pointy, managed instalace,
  migrace z 0.8.9 s rollbacky, hardening obrazu, veřejné CLI a registrované
  nativní regrese.
- Samostatné testy pro každý cíl:
  - Linux arm64 a riscv64 nativním toolchainem v emulaci: 100/100 a 99/99.
  - Skutečné stroje v CI: Windows x86_64 (Windows Server 2025, Windows 11
    ARM v emulaci), Windows arm64, macOS x86_64 a arm64, Linux arm64.
  - WebAssembly v Node i wasmtime: 89/89 pro oba cíle.
  - Bare metal RISC-V v qemu se 4 i 1 jádrem: 90/90.
  - Android (Samsung Galaxy Z Fold7, Android 17) přes adb během vývoje
    0.10 (99/99 testů); s finálními binárkami se na zařízení znovu nespouštělo.
- Testy, které na dané platformě nedávají smysl (procesy ve WASI, `/proc`
  na Windows …), se přeskakují s uvedeným důvodem (`tests/cross_targets.py`).

## Známá omezení

- Překladač běží jen na Linuxu. Na Windows ho spustíte ve WSL 2, na macOS
  v linuxovém kontejneru. Programy pro Windows a macOS se z Linuxu
  přeloží přímo.
- Na Androidu jsou ověřené přeložené programy. Překladač v Termuxu
  (`pkg install binutils`) zatím na skutečném zařízení ověřený není.
- `wasm32-wasi` (bez vláken) spouští vlákna postupně. Program, ve kterém
  vlákno čeká na hlavní vlákno, potřebuje `wasm32-wasi-threads`. WASI
  preview1 nemá procesy ani sockety.
- Bare metal je ověřený na desce qemu `virt`. Jiné desky RISC-V s 16550
  UART a CLINT by měly fungovat podle stromu zařízení, ale nejsou
  vyzkoušené. Procesy ani sockety bez OS nejsou.
- Sandbox procesů na Windows není (`sandbox.available()` vrací False). Na
  Windows a macOS nativní knihovny běží v izolovaném procesu, ale jejich
  systémová volání se neomezují jako seccomp na Linuxu.
- Bare metal pro x86_64 a ARM a 32bitové cíle (ESP32 a menší) jsou
  v plánu.
