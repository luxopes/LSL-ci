# Changelog

Na této stránce jsou uživatelsky významné změny vydaných verzí. Stabilní
manuály a soubory ke stažení zůstávají dostupné v
[historii vydání](/releases/).

## 0.6 — 29. 7. 2026

Druhé archivované self-hosted vydání LSL.

### Jazyk

- Operátor mocniny je `^`; původní `**` je odmítnuté syntaxí.
- Přibyly first-class Lux Stringy, například
  `text = l"Jmenuji se {name}"`.
- `printl` zůstává kompatibilní a používá stejnou interpolaci.
- Celý modul lze importovat pod aliasem: `load test as t`.

### Compiler a výkon

- Konstantní String concat se skládá už při překladu.
- Malé konstantní mocniny se emitují inline.
- Lux String s více výrazy používá vyvážený concat strom.
- JSON encoder a binární FloatArray transport se vyhnou kvadratickému
  skládání velkých payloadů.
- Self-hostovaný compiler zůstává bitově reprodukovatelný ve fixed pointu.

### Skutečná NVIDIA CUDA

- Vydání obsahuje `lsl-cuda-worker` postavený pomocí CUDA Runtime.
- Na GPU běží ověřovací kernel, Float64 `sum`, `dot`, AXPY a tiled matmul.
- `cuda.available()` vrací True až po úspěšném device kernelu.
- Velká pole používají raw binární stdin/stdout místo JSON serializace.
- Politiky `auto`, `required`, `off`, výběr zařízení a CPU fallback jsou
  součástí veřejného modulu `cuda`.
- Hardware conformance a benchmark byly ověřeny na NVIDIA GeForce GTX 1650,
  compute capability 7.5.

### Distribuce a dokumentace

- `lsl --help`, `lsl version` a `lsl --version` hlásí 0.6.
- Installer přidává CUDA worker vedle LSL binárek.
- Web obsahuje samostatné stabilní manuály 0.5 a 0.6, historii vydání,
  zdrojové archivy, binární balíky, offline manuály a SHA-256 součty.

## 0.5 — 29. 7. 2026

První veřejné self-hosted vydání LSL.

- Compiler je napsaný v LSL a sám sebe překládá do bitově shodného výsledku.
- Přímý backend zapisuje statický Linux x86_64 ELF bez libc, assembleru a
  linkeru.
- Runtime používá Linux syscalls a obsahuje garbage collector, String,
  kolekce, Float, moduly, třídy a strukturované chyby.
- Standardní knihovna zahrnuje JSON, konfiguraci, procesy, HTTP, AI,
  Tensor/FloatArray, GUI a správu systému.
- CLI přidalo funkční `--help`, `version` a `--version`, všechny s verzí 0.5.
- Vyšel první český dvanáctidílný vývojářský manuál a kompletní reference.

## Odkazy na stabilní manuály

- [LSL 0.6 — manuál a soubory ke stažení](/releases/0.6/)
- [LSL 0.5 — historický manuál a soubory ke stažení](/releases/0.5/)
