# LSL 0.8.0

Vydání přidává správu knihoven, TUI a tematickou nápovědu v čistém LSL.

- Barevná nápověda, stav instalace a diagnostika, s automatickým vypnutím
  barev při přesměrování nebo s NO_COLOR.
- `lsl list` a `lsl check NAME` rozlišují bundled a uživatelské knihovny.
- `lsl search [QUERY]` hledá v produkčním katalogu podle názvu a popisu.
- `lsl install --tui` nabízí označení více knihoven, filtr a potvrzenou
  instalaci přes stávající SHA-256/compile/atomic-install cestu.
- `lsl man [TOPIC]` otevírá offline kopii webového manuálu, se všemi
  17 kapitolami, referencí, bezpečnostním modelem a changelogem.
  `--plain` a pipes poskytují čistý text.
- `help()` zůstává; `help("TOPIC")` nově podporuje runtime String argument,
  zachytitelné chyby a samostatné ELF bez instalace LSL.
- Vylepšené klávesové TUI vstupy a obnovení stavu terminálu.
- Opraveno čtení tar archivu v interním ABI skutečného CLI. Z 0.7.8 je
  nutný jednorázový přechod přes nový `lsl-install`; ten nově umí atomicky
  přeinstalovat spravovaný prefix a zachovat rollback, bez přepisu symlinků.
- Odstraněné staré BUG*.md a netlify.toml jsou dostupné v historii Gitu.

Použití a přesná sémantika příkazů:
[CLI, knihovny a terminálový manuál](developer_guides/17-cli-and-packages.md).

Compiler, runtime, CLI i testy zůstávají self-hosted LSL. CUDA worker se
nemění. Systémové nástroje jsou používány pouze přes přímé argv, bez shellu.
Formát podepsaného kanálu se nemění. Přechod z 0.7.8 vyžaduje výše uvedený
jednorázový instalační postup; následující aktualizace z 0.8.0 již fungují.
