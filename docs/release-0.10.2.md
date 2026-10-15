# Release LSL 0.10.2

`lsl update` funguje na Windows a macOS. Kanál aktualizací nese balíky
všech sedmi hostitelů.

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

## Ověření

- `tests/update_portable_conformance.lsl` (i ve vnitřním ABI CLI) na
  Linuxu, Windows a macOS v CI, ve wine a v emulaci arm64/riscv64.
- `tools/ci/update_e2e.py` v CI na Windows Server 2025 x64, Windows 11
  ARM64, macOS 15 arm64 a Intel proti produkčnímu kanálu: kontrola,
  odmítnutí downgradu, aktualizace na vydanou verzi a rollback zpět.
