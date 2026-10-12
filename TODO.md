# LSL TODO

Jen otevřená práce. Hotové položky jsou v `TODO-historie.md`; při dokončení
se položka přesune tam pod nadpis vydání s řádkem „Stav X.Y.Z: …“ a důkazem.

Formát položky:

```text
- [ ] **Oblast:** co udělat.
  Přijetí: čím se ověří, že je hotovo.
```

Pro každou položku platí: fixed point, rychlá i plná sada testů, release
preflight a CPU benchmark proti předchozímu vydání — překlad ani běh nesmí
být pomalejší.

## Plán 0.10: LSL jen jazyk, vše strojové a platformní v LuxIR

LSL řeší co nejméně: parser, sémantiku, typovou inferenci, validaci,
diagnostiku a překlad do jednotného LuxIR. Generování a optimalizace kódu,
runtime, přístup k operačnímu systému, formát binárky a linkování řeší
backend LuxIR (jeho plán: `TODO.md` v repozitáři LuxAI/LuxIR). Stejný LuxIR z
LSL pak poslouží pro Linux, Windows, macOS i Android.

Inventura stavu 0.9.2 (co dnes LSL dělá samo a má odejít do LuxIR):
runtime emitory strojového kódu x86_64 `compiler/pure/*_runtime_linux_x86_64.lsl`
(heap/GC 4 689, I/O 2 664, procesy 964, native 596 + plugin 701, vlákna 513,
runtime 194 řádků), starý přímý backend `backend_x86_64.lsl` (5 298) s
`x86_64.lsl`, `assembler_x86_64.lsl`, `elf_image.lsl`, `relocations_x86_64.lsl`,
`abi_x86_64.lsl`; platformní moduly stdlib `stdlib/_*_linux_x86_64.lsl`
(2 857 řádků) a intrinsiky `__lsl_syscall`, `__lsl_fd_*`; 62 runtime funkcí
volaných z `qbe_emit.lsl`; linkování přes binutils `as` + `ld` v
`qbe_toolchain.lsl`; optimalizace v `qbe_emit` (konstantní větve, guarded
specializace funkcí, podmínka smyčky `rang` z 0.9.2).

### Rozhraní LSL ↔ LuxIR

- [ ] **Kontrakt:** sepsat a verzovat rozhraní LSL ↔ LuxIR — layout objektů
  (hlavička, kód typu, délka, ukazatelové mapy pro GC), kořeny GC, safepointy,
  chybový tok, řetězcové literály, globály, vstupní bod. Frontend popisuje
  *co*, LuxIR rozhoduje *jak*.
  Přijetí: dokument v repozitáři LuxIR a qbe_emit generuje jen podle něj.
- [ ] **Verze:** `release.json` a test runner pinují verzi LuxIR i verzi jeho
  runtime ABI.
  Přijetí: nekompatibilní kombinace selže při překladu srozumitelnou chybou.

### Runtime a OS do LuxIR (pořadí podle rizika)

- [ ] **I/O:** soubory, stdout/stdin, adresáře a terminál přes OS vrstvu LuxIR
  (luxrt).
  Přijetí: odpovídající emitory v `io_runtime_linux_x86_64.lsl` odstraněné.
- [ ] **Procesy:** spawn, pipes, wait, exit a signály přes luxrt.
  Přijetí: `process_runtime_linux_x86_64.lsl` odstraněný, fault injection
  přesunutý do testů luxrt.
- [ ] **Vlákna:** vlákna, zámky a atomiky přes luxrt a instrukce LuxIR.
  Přijetí: `thread_runtime_linux_x86_64.lsl` odstraněný.
- [ ] **Nativní volání:** moduly `native` a `plugin` přes volací konvence LuxIR.
  Přijetí: `native_runtime_*` a `native_plugin_runtime_*` odstraněné.
- [ ] **Alokátor a GC:** přesný GC v runtime knihovně LuxIR; frontend dodá jen
  ukazatelové mapy a safepointy.
  Přijetí: benchmarky alokace, GC a kolekcí stejné nebo rychlejší; teprve pak
  odstranit `heap_runtime_linux_x86_64.lsl`.
- [ ] **Převody a řetězce:** Int/Float ↔ text (přesný Eisel-Lemire a nejkratší
  formát z 0.9.2) a řetězcové primitivy (UTF-8, hledání, porovnání, hash)
  v runtime LuxIR.
  Přijetí: kopie v `dynamic_stdlib.lsl` a runtime emitorech odstraněné, fuzz
  proti Pythonu beze změny.
- [ ] **Chybový tok:** místo kontroly příznaku po každém volání použít „volání,
  které může selhat“ z LuxIR.
  Přijetí: menší a stejně rychlý nebo rychlejší kód, shodné výstupy chyb.

### Knihovny a nástroje

- [ ] **Stdlib:** nahradit `stdlib/_*_linux_x86_64.lsl` a `__lsl_syscall`
  přenositelnými voláními luxrt; `target.lsl` jen předá cíl.
  Přijetí: v LSL nezůstane platformní větev.
- [ ] **Linkování:** v `qbe_toolchain.lsl` místo `as` + `ld` volat linker LuxIR.
  Přijetí: instalace, dokumentace ani web nevyžadují binutils.
- [ ] **Úklid backendu:** odstranit `backend_x86_64.lsl`, přímé x86 enkodéry,
  ELF writer, `qbe_runtime_dump.lsl` a `runtime.o`.
  Přijetí: nic z nich se nepoužívá, překladač je v pevném bodu.
- [ ] **Optimalizace:** optimalizace, které převezme LuxIR (inlinování,
  smyčky včetně podmínky `rang` z 0.9.2, konstanty, specializace, odstranění
  mrtvého kódu), smazat z `qbe_emit`.
  Přijetí: LuxIR dává stejný nebo lepší výkon; inlinování (`function_calls`,
  ~1 takt volání na iteraci v 0.9.2) je úkol LuxIR.

### Platformy

- [ ] **Pořadí:** linux-x86_64 převedený beze ztráty výkonu → windows-x86_64 →
  linux-arm64 → macos-arm64 a macos-x86_64 → android-arm64 → linux-rv64.
  Přijetí: každý cíl vydaný jako samostatná verze.
- [ ] **Cíle:** v `target.lsl` označit cíl dostupný, až LuxIR dodá runtime,
  linker a testy pro daný systém.
  Přijetí: CI matice překladu a testů pro každý cíl.
- [ ] **Instalace:** instalátor a `lsl update` pro Windows (výměna běžícího
  `.exe`, `%LOCALAPPDATA%`, zip balík) a macOS (ad-hoc podpis Mach-O,
  Gatekeeper, `~/Library`).
  Přijetí: instalace, aktualizace a rollback na skutečném systému.
- [ ] **Distribuce:** podepsaný stabilní kanál s artefaktem pro každou
  platformu; na webu přepnout karty platforem ze „zatím ne“ na stažení.
  Přijetí: jen skutečně vydané a ověřené buildy.
- [ ] **Testy na systému:** Windows ve Wine průběžně a na skutečném Windows
  před vydáním, macOS na skutečném Macu (ověří uživatel), Android na zařízení
  nebo emulátoru ARM64.
  Přijetí: výsledky v evidenci vydání `tests/release/X.Y.Z/`.

## Testy a robustnost

- [ ] **Procesy:** syntetický fault injection pro větve wait a read (fork je
  hotový v 0.9.2, `tests/process_fork_fault_conformance.lsl`).
  Deterministické vyvolání vyžaduje vlastní obsluhu signálů nebo syscallový
  hook v runtime; v plánu 0.10 může přejít do testů luxrt.
  Přijetí: wait i read skončí čistou chybou bez úniku popisovačů.
