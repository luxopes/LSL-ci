# Release LSL 0.10.2

`lsl update` funguje na Windows a macOS. Kanál aktualizací nese balíky
všech sedmi hostitelů. Nové 32bitové cíle `linux-arm` a `linux-x86`.

## Změny

- Self-update na Windows (x64, ARM64) a macOS (Apple Silicon, Intel):
  - podpis manifestu (Ed25519) a SHA-256 archivu ověřuje LSL
    (`compiler/pure/release_crypto.lsl`), bez `openssl` a `sha256sum`,
  - stahuje systémový `curl`, rozbaluje systémový `tar`; seznam položek
    archivu se předem zkontroluje (ZIP: centrální adresář, tar.gz: přísný
    parser jako na Linuxu),
  - nová verze se nainstaluje vlastním `lsl-install` vedle aktivní,
    ověří se (verze, překlad a spuštění programu) a teprve pak se vymění
    přejmenováním; přerušenou výměnu vrátí příští spuštění,
  - předchozí verze zůstává pro `lsl update --rollback`,
  - aktualizuje se instalace z `lsl-install` (značka
    `lib/lsl/INSTALLATION`), ne rozbalený archiv ani zdrojový checkout.
- Nový kanál `channels/stable-v2.json` se všemi platformami čtou klienti
  od 0.10.2 na všech systémech; Linux RISC-V 64 se tak také aktualizuje
  sám. `stable.json` zůstává pro starší klienty (jen Linux x86_64 a
  aarch64).
- Runtime: interní `__lsl_rename(zdroj, cíl)` (bez přepsání cíle) pro
  Linux, Windows a macOS. Procesy v čistém prostředí na Windows dostanou
  `SystemRoot`, jinak v nich nefungují síťové nástroje.
- Oprava: chybová hláška `lsl update` neobsahuje zdvojené
  `UpdateError: UpdateError:`.

- 32bitový Linux: `--target linux-arm` (armv7 hard-float) a
  `--target linux-x86` (i686, SSE2). LuxIR má pro oba vlastní generátor
  assembleru (backendy `arm` a `i386`), stačí GNU binutils jako u ostatních
  cílů Linuxu; C překladač není potřeba. Hodnoty LSL zůstávají 64bitové
  (LuxIR je rozloží na dvojice 32bitových slov), programy se chovají stejně
  jako na 64bitových cílech. Překladač pro oba cíle přeloží sám sebe
  bajtově shodně. Nativní knihovny jsou zatím jen 64bitové.
- Oprava (všechny cíle): vnitřní ABI (moduly překladače a aktualizace)
  drží celá čísla v hodnotách `Any` bez boxování a číslo rovné adrese
  živého objektu se splete s objektem. Halda proto leží nad běžnými čísly:
  Linux 64bit, macOS a Windows od 2^44 (s náhodným posunem), 32bitový
  Linux a WebAssembly se značkou bitu 40 v adresách, bare metal v aliasu
  RAM od 192 GiB. Na macOS se dosud halda nacházela kolem 2^32 a výpočet
  podpisu aktualizace mohl dát chybný výsledek.
- 32bitový Linux: časové limity socketů zkusí `SO_*TIMEO_NEW` a na jádrech
  před 5.1 (nebo starším qemu) použijí původní volbu.
- README balíku popisuje spuštění nepodepsaných binárek (SmartScreen,
  karanténa macOS).

## Ověření

- `tests/update_portable_conformance.lsl` (i ve vnitřním ABI CLI) na
  Linuxu, Windows a macOS v CI, ve wine a v emulaci arm64/riscv64.
- `tools/ci/update_e2e.py` v CI na Windows Server 2025 x64, Windows 11
  ARM64, macOS 15 arm64 a Intel proti produkčnímu kanálu: kontrola,
  odmítnutí downgradu, aktualizace na vydanou verzi a rollback zpět.
- 32bitový Linux: celá sada (106 testů) na `linux-x86` nativně a
  `linux-arm` v qemu, lokálně i v CI; self-host bajtově shodný.
- `tests/internal_int_heap_alias_conformance.lsl` na všech cílech.
