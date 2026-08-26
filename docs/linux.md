# Linux x86_64

První produkční target je Linux x86_64. `lsl` a `lslc` jsou statické
LSL-generované PIE ELF soubory s ASLR a neproveditelným stackem, bez libc,
dynamic interpreteru, assembleru nebo linkeru.

## Ověření bootstrapu

```text
./compiler/pure/lslc-direct compiler/pure/lslc_direct.lsl /tmp/lslc-next
cmp ./compiler/pure/lslc-direct /tmp/lslc-next
./tests/lsl-test
```

Test runner spouští procesy přímo přes `fork`, `execve` a `wait4`. Fixed point musí být bitově shodný; aktuální SHA-256 je v `PURE_LSL_PROGRESS.md`.

## Instalace

```text
./compiler/pure/lsl-install /tmp/lsl-prefix
cd /tmp
/tmp/lsl-prefix/bin/lslc /cesta/program.lsl /tmp/program
/tmp/program
```

Bez prefixu se instaluje do `/usr/local`. Standardní moduly jsou v `<prefix>/lib/lsl`; compiler jejich cestu odvodí přes syscall `readlink("/proc/self/exe")`.

No-argument `lsl` rozlišuje terminál přes `ioctl(TCGETS)`. TTY dostane interaktivní banner/prompty a končí řádkem `exit` nebo Ctrl-D. Pipe končí pouze EOF; heredoc pouze svým shellovým delimiterem, bez vnitřního `exit`. Výsledný `<stdin>` zdroj se přímo přeloží do dočasného syscall-only ELF; shell ani interpreter se nepouští. Modul `time` používá `clock_gettime(CLOCK_REALTIME/CLOCK_MONOTONIC)` a `nanosleep`.

## Runtime syscalls

Runtime přímo používá mimo jiné `read`, `write`, `open`, `close`, `access`,
`lseek`, `brk`, `fork`, `execve`, `wait4`, `pipe`, `dup2`, `readlink`, `mkdir`
a `unlink`. HTTP(S) modul spouští systémový `/usr/bin/curl`; citlivý request
config předává přes stdin a shell nepoužívá. Modul `os` tokenizuje String nebo
přijme List[String], hledá executable v `PATH` a také volá přímý `execve`;
`/bin/sh -c` nepoužívá.

ELF má nulovou virtuální bázi, jediný RX `PT_LOAD` a RW `PT_GNU_STACK`;
writable stav allocatoru/GC je rezervován přes `brk`, takže image není RWX.
