# Knihovna sandbox

`load sandbox`

Capability sandbox pro procesy na Linuxu x86-64 — stojí za ním příkaz
`lsl sandbox`. Sandbox je záměrně mimo proces: program vidí prázdný
tmpfs root, minimální `/proc` a `/dev`, vlastní read-only spustitelný
soubor a jen cesty explicitně navázané do `/input` nebo `/output`.
Síťové namespaces, systemd cgroup, prlimit a timeout se nastaví před
spuštěním.

## Funkce

### sandbox.available()

`True`, pokud jsou dostupné systémové nástroje sandboxu.

### sandbox.run(executable, arguments, policy)

Spustí program v sandboxu a vrátí exit status. `arguments` je List
Stringů (max. 4096).

### sandbox.command(executable, arguments, policy)

Sestaví argv pro sandbox (pro transparentní volání).

### sandbox.profile() / sandbox.is_active()

Aktivní profil; `True`, pokud program běží uvnitř sandboxu.

## Policy

```lsl
{"profile": "strict" | "server",     # výchozí strict
 "timeout": Int (1..3600, výchozí 30),
 "memory": Int (64 MiB..8 GiB),
 "read": [cesty], "write": [cesty]}   # bindy do /input a /output
```

## Chyby

- `SandboxError` — neplatná policy, chybějící nástroje, selhání spuštění.

## Související stránky

- `lsl man httpserver` — nasazení serveru pod sandbox
- `lsl man os` — běžné spouštění bez sandboxu
