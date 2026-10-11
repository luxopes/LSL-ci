# Release LSL 0.9.0 BETA

11. října 2026. Předběžné vydání pro **Linux x86_64**.

## Nový backend

Výchozí compiler používá oddělený LSL frontend, LuxIR mezivýstup a nativní
backend LuxIR napsaný v LSL. Backend je odvozen z QBE 1.3, jeho zdroje jsou
samostatně v [LuxAI/LuxIR](https://git.lux-ai.cz/LuxAI/LuxIR). Referenční C
implementace se při běžném překladu ani self-host buildu nespouští.
Strojový assembler a linker poskytují GNU `as` a `ld` z balíku `binutils`.
Běh vytvořených programů tyto nástroje nepotřebuje.

Vydání zahrnuje nový frontend, backend, runtime, CLI, konfigurátor, instalátor
a regresní testy. Ostatní cíle backendu nejsou podporovanými platformami
celého LSL; tato BETA poskytuje runtime a instalaci pouze pro Linux x86_64.
Verze čtená příkazem `lsl version` je `0.9.0`, nápověda a vydání uvádějí BETA.

## Výkon a známá omezení

[Srovnání s 0.8.9](../tools/qbe/LUXIR_BENCHMARK_20261011.md) ukazuje rychlejší
běh všech osmi měřených programů. Překlad společného zdroje původního compileru
trvá 11,399 s místo 8,062 s: **o 41,4 % déle**. Tyto časy měří konkrétní
vstupy a hardware, nikoli záruku pro libovolný program. Další optimalizace
překladu i ostatní otevřené problémy z TODO jsou plánované pro **0.9.1**.

## Instalace a aktualizace

Vydání je na [Gitea Releases](https://git.lux-ai.cz/LuxAI/LSL/releases/tag/v0.9.0-beta.1)
explicitně označené jako prerelease. Z binárního archivu:

```sh
./bin/lsl version
./bin/lsl-install "$HOME/.local"
```

Pro samostatné vyzkoušení lze spouštět `bin/lsl` přímo z rozbaleného balíku,
aniž by se měnila dosavadní instalace. Potřebujete Linux x86_64 a `binutils`.
Stabilní podepsaný aktualizační kanál zůstává na **0.8.9**; `lsl update`
nepovyšuje stabilní instalaci automaticky na tuto betu. Existující správa
generací instalátoru zachovává rollback. Samostatné programy přeložte znovu.

## Samostatný web a dokumentace

Web a české manuály mají vlastní projekt
[LuxAI/LSL-Web](https://git.lux-ai.cz/LuxAI/LSL-Web). Git repozitář compileru
neobsahuje kopii webu ani historické distribuční archivy. `release.json`
připíná konkrétní commit dokumentace a backendu. `prepare_sources.py` z něj
vytvoří odvozený offline snapshot; ten je součástí instalace a zdrojového
release archivu. Manuály se upravují výhradně v LSL-Web, `lsl man` funguje offline.

Postup sestavení a ověření je v [compiler-development](compiler-development.md).
Přesné hashe binárek a důkazy ověření jsou v `tests/release/0.9.0-beta/`.
