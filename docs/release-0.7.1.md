# LSL 0.7.1

LSL 0.7.1 je stabilizační vydání bez nové syntaxe. Uzavírá chyby nalezené při
auditu aplikačních hranic přidaných v řadě 0.7 a doplňuje cílené regrese pro
server, balíčky, linker, compiler ABI a dočasné artefakty CLI. Živý manuál je
aktualizovaný; samostatný kopírovaný snapshot zůstává pro základní vydání
0.7.0.

## Hlavní změny

- Safe/unsafe validace nyní prochází také výraz `step` ve slice. Stejná
  kontrola se uplatní na celý uživatelský importní graf.
- Linker cachuje moduly podle vyřešené cesty a používá deterministické interní
  prefixy. Moduly z různých adresářů se stejně pojmenovaným `helper.lsl` se už
  navzájem nezamění.
- Samostatná modulová funkce `origin()` se správně odlišuje od
  `origin.method()` používaného pro volání metody předka.
- Interní raw ABI self-host compileru je označené explicitní provenance
  markerem. Běžná cesta obsahující text `compiler/pure/` už nemůže obejít
  veřejné tagged Any kontroly.
- Instalace a aktualizace knihoven jsou serializované per-package zámkem.
  `lsl origin NAME` znovu ověřuje SHA-256 nainstalovaného zdroje, zámek odmítá
  symlink a nesouborové objekty a chybové větve uklízejí staging data.
- HTTP server přijímá přesně dokumentovaný limit 64 hlaviček, vyžaduje
  neprázdný HTTP/1.1 `Host` a statické soubory otevírá neblokujícím způsobem.
  FIFO, zařízení a sockety odmítne; chyba aplikačního handleru vrátí pro daný
  požadavek 500 a listener pokračuje. Aplikační odpověď má limit 8 MiB.
- Config evaluator považuje procesový `check` a formátovací `printl` za
  nečisté operace. CLI vytváří dočasný ELF až po úspěšném překladu a uklízí
  chybové cesty configu i sandboxu.

## Ověření vydání

Vydání prošlo bitově shodným self-host fixed pointem, fast i full testovací
sadou, čistou instalací, fixed pointem z instalované kopie, porovnáním configu
a kontrolou release ELF. Compiler má SHA-256
`b907fc2b8d68b55ae94d2838531bf705e8ab663f0e22002695840ecec64eb899` a CLI
`d11dc6cb2cd26273555c64d807d53e640588f3cd4d2720f2e89967b3f87fbb57`.
Distribuční archivy jsou vytvořené deterministicky;
jejich kontrolní součty jsou v
`docs/developer_guides/downloads/SHA256SUMS`.
