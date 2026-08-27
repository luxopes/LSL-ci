# LSL 0.7 release handoff

## Cíl a aktuální stav

Produkční LSL obsahuje pouze LSL zdroje a LSL-generované Linux x86_64 ELF.
Self-host compiler přímo zapisuje statický syscall-only ELF bez C/C++, libc,
assembleru, linkeru, Pythonu nebo shell launcheru. Stage N reprodukuje stage
N+1 bit po bitu.

- Repo: `/home/antonin/lsl`
- Větev: `complete-roadmap`
- Aktuální implementační milníky jsou v `git log`; handoff záměrně neukládá
  self-referenční hash vlastního dokumentačního commitu.
- Aktuální fixed-point SHA-256:
  `d19fbb95f937344a74118b4ab7dfc0a9c0d9c2398ede44705899757ea33094fa`
- Aktuální CLI SHA-256:
  `942e5fc4dd93e492309cb1f4bffacdbdaef720ad2f80f73b497a139f7caf436b`
- `compiler/pure/lslc-direct == compiler/lslc`
- `compiler/pure/lsl-cli == lsl`
- ELF: jediný RX `PT_LOAD`, bez `INTERP` a RWX
- Produkční strom: žádné `.c`, `.h`, `.py` ani `.sh`
- Příklad s bare input syntaxí je commitnutý jako `examples/hello.lsl`.

Podrobné historické hashe a důkazy jsou v `PURE_LSL_PROGRESS.md`; veřejný scope
je v `TODO.md`.

## Ověřeně dokončený scope 0.7

- pure-LSL lexer/parser/linker, source spans a strukturovaná diagnostika;
- přímý x86_64 encoder, assembler model, ELF writer a self-host fixed point;
- Int/Bool/None/Float/String, List/Tuple/RealArray/Dictionary, Unicode a JSON;
- jednoznačný tagged Any ABI včetně Function/callback returns a
  raw-Int/live-pointer collision proof;
- functions, recursion, classes, široké register/stack ABI a exceptions;
- conservative cycle GC, free-list reuse, dynamický růst registry/intern cache;
- filesystem, argv/env, původní `input "prompt"` i `input("prompt")`, partial I/O a process/capture/status/stderr;
- deadlock-free memfd `capture_input` a live `capture_stream` callbacky;
- strict JSON parser (Float/exponenty, bounds, escapes/surrogates, trailing data);
- config defaults/types/provenance/lazy/cycles, AI retry/cancel/SSE streaming;
- process JSON plugin ABI, zero-copy CPU Tensor a omezený in-process ET_DYN ABI;
- relocatable pure-LSL CLI, configure tool, installer a test runner.
- `lsl origin` a striktní provenance sidecar balíčků;
- omezený syscall-only HTTP server a statický HTTPS frontend přes
  systémový nginx/OpenSSL;
- capability `lsl sandbox` s namespaces, systemd cgroup, prlimit/timeout a
  explicitními read/write bindy;
- výchozí safe CLI překlad, lexikální `unsafe:` hranice a zákaz unsafe kódu
  při sandbox kompilaci;
- šestargumentová syscall brána a explicitní přechod mezi interním raw ABI
  compileru a veřejným tagged Any ABI modulů.

## Testy, hardening a výkon

`tests/lsl-test` má režimy:

```text
./tests/lsl-test fast
./tests/lsl-test              # full (výchozí)
./tests/lsl-test fixed-point
```

Pozitivní corpus je agregovaný v `tests/full_conformance.lsl`, ale očekávaný
výstup se stále skládá z původních `.out`, takže jednotlivé source spans a
důkazy zůstávají zachované. Full navíc spouští:

- negative compiler corpus a config conformance;
- 1000 deterministicky generovaných validních lexer/parser programů;
- 200 JSON round trips a 24 malformed JSON případů;
- GC stress: 10000 cyklů, 3000-uzlový graf a reuse;
- RLIMIT_NOFILE fault injection pro pipe/memfd setup/cleanup;
- generativní config corpus se 100 options/defaults/overrides/force/list hodnotami;
- fixed-point byte comparison.

Naměřené časy na současném hostu:

- původní full: 23,2 s;
- stejný agregovaný feature corpus před novými stress testy: 9,4 s;
- aktuální rozšířený full: 15,0 s;
- fast: 4,2 s;
- fixed-point: 3,7 s;
- self-host compile: 3,95 → přibližně 3,62 s;
- self-host peak RSS: přibližně 809 → 764 MiB.

Compiler byte encoder normalizuje raw/boxed Int do typed raw locals a Int tokeny
parsuje trust-core helperem před high-memory codegenem. Tím zmizel vzácný
fixed-point drift; 40 po sobě jdoucích reprodukcí bylo shodných.

Process setup kontroluje pipe/memfd/fork/read/wait/lseek/dup2. Otevřené fd se na
error větvích uklidí. Linux `close(2)` cleanup je best-effort a po `EINTR` se
neopakuje, protože descriptor už může být recyklovaný.

## Zbývající neblokující práce

Implementační scope 0.7 je uzavřený. Následující body nejsou blockery vydání:

1. syntetická fault injection pro obtížně vyvolatelné fork/wait/read failures;
2. další benchmark/regression limity a snížení compiler peak RSS;
3. volitelná native ABI v2 (povolené relocations, Tensor descriptors);
4. další CPU targety a obecnější device ABI;
5. plný Rust ownership/borrow checker a statický důkaz absence data races;

## Provozní pravidla

- Dlouhé buildy pouze sériově pod `ulimit -v 1572864`.
- Nepoužívat C/Python/assembler/linker ani jako dočasný backend.
- Nespouštět síť bez výslovného požadavku.
- Před změnou číst okolní kód; dělat nejmenší úplnou změnu.
- Každý compiler/runtime zásah: cílený test → 2–3 self-host stages → SHA/cmp →
  deterministická regenerace nástrojů → full suite → config.
- Před commitem: `git status`, `git diff`, `git diff --check`, explicitní `git add`.
- Nic nepushovat bez výslovného požadavku.

## Auditní příkazy

```text
ulimit -v 1572864
./compiler/pure/lslc-direct compiler/pure/lslc_direct.lsl /tmp/lsl-next
cmp compiler/pure/lslc-direct /tmp/lsl-next
./tests/lsl-test
./lsl config examples/config/system.lsl > /tmp/config.json
cmp tests/config_expected.json /tmp/config.json
readelf -l compiler/pure/lslc-direct
find . -type f \( -name '*.c' -o -name '*.h' -o -name '*.py' -o -name '*.sh' \)
```
