# LSL 0.7.0

LSL 0.7.0 je první feature release po stabilizační řadě 0.6.x. Přidává
serverový a sandboxový aplikační základ, ověřitelný původ knihoven a explicitní
hranici mezi běžným a nízkoúrovňovým kódem.

## Dosud implementované změny

- `lsl server` spouští omezený statický HTTP server; s `--tls-cert` a
  `--tls-key` používá systémový nginx/OpenSSL HTTPS frontend.
  Odpovědi používají `MSG_NOSIGNAL`, takže reset jednoho klienta nemůže
  ukončit celý server přes `SIGPIPE`.
- Původ registry knihovny zobrazuje nový `lsl origin [NAME]`. Install/update
  ukládá striktní provenance sidecar s originem, source URL a SHA-256.
- `lsl sandbox` kompiluje a spouští worker v bubblewrap namespaces se
  systemd cgroup, prlimit a timeout limity a explicitními read/write
  capabilities.
- Nový lexikální blok `unsafe:` ohraničuje raw `__lsl_*`, native a thread
  operace. Bezpečný CLI překlad kontroluje celý uživatelský importní graf;
  sandbox překlad unsafe kód nepovolí vůbec.
- Runtime/codegen dostal šestargumentovou syscall bránu a opravenou hranici
  mezi interním raw ABI compileru a veřejným tagged Any ABI stdlib modulů.
- Nové regrese pokrývají HTTP parser/path confinement, symlink escape,
  syscall6, provenance, sandbox capabilities a safe/unsafe compiler policy.

## Záměrně neprohlašované vlastnosti

LSL 0.7 nezavádí Rust borrow checker ani formální důkaz absence data races.
Bezpečný režim místo toho zachovává runtime bounds/type checks, blokuje raw
memory doors a vyžaduje explicitní `unsafe:` pro vlákna a native-adjacent ABI.
TLS kryptografii neimplementuje LSL a procesový sandbox stále důvěřuje Linux
kernelu, bubblewrap a systemd.

## Ověření vydání

Dne 27. 8. 2026 prošel třífázový bitový fixed point, fast i finální full suite,
`lsl config`, čistá instalace, fixed point z instalované kopie, audit všech
pure-LSL ELF a reálné loopback HTTP i HTTPS požadavky. Compiler stage 1–3 a
obě verzované kopie mají SHA-256
`d19fbb95f937344a74118b4ab7dfc0a9c0d9c2398ede44705899757ea33094fa`;
CLI má SHA-256
`942e5fc4dd93e492309cb1f4bffacdbdaef720ad2f80f73b497a139f7caf436b`.

Při čistém instalačním auditu byla navíc zachycena a opravena integrační chyba
`lsl config`: interně generovaný a předem validovaný evaluator používá privátní
runtime helpery, a proto se nyní překládá důvěryhodnou compilerovou cestou.
Samostatný CLI regresní test hlídá výsledný JSON.
