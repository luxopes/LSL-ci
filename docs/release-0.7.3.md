# LSL 0.7.3

LSL 0.7.3 ruší pevný 8MiB limit request a response body dynamického HTTP
serveru. Limit je nyní runtime konfigurace s výchozím stavem bez limitu;
statický souborový server zůstává beze změny.

## Hlavní změny

- `httpserver.set_body_limit(bytes)` nastavuje limit request i response body
  dynamického handleru; `0` znamená bez limitu a je výchozí hodnota.
  `httpserver.body_limit()` vrací aktuální stav. Deklarovaná délka nad limit
  je `413` s limitem v hlášce; response nad limit zůstává request-local
  `500`.
- Čtení request body používá postupně rostoucí buffer (start 16 MiB nebo
  deklarovaná délka, je-li menší; růst zdvojováním podle skutečně přijatých
  dat). Nepřátelsky deklarovaná `Content-Length` proto nealokuje paměť
  dopředu; paměť roste jen s daty, která opravdu dorazila.
- Statický režim (`lsl server --dir`) je beze změny: request body odmítá a
  jednotlivý soubor zůstává omezen na 8 MiB.
- Regresní sada pokrývá 9MiB request/response round-trip při výchozím stavu,
  runtime nastavený limit (`413`), návrat k neomezenému stavu a dále
  dokumentuje kontrakt `__lsl_fd_write` v test klientech: builtin dokončí
  celý buffer interně a vrací status `0`/`-errno`, nikoli počet bajtů.

## Ověření vydání

Vydání prošlo bitově shodným self-host fixed pointem, plnou testovací sadou
(včetně nových body-limit konformancí), porovnáním configu a kontrolou
release ELF. Compiler má SHA-256
`de0097e8921d217af1b74d18c8b0d22e6588b6cdf5243396b81c16da2a7275b3`, CLI
`5b39893f4f5245e28591814553fae799241b7b1af65fbc07dc60f4513a188f02` a test
runner `1cb44cb88ebed259a754dc79004a8ebd7b5a06e3b5b122e699c396b0a6fba434`.

## Kompatibilita

Aplikace, které spoléhaly na implicitní 8MiB strop, si jej mohou vrátit
voláním `httpserver.set_body_limit(8388608)` před `httpserver.serve`.
Veřejně vystavený server by měl limit nastavit vždy; bez něj může klient
poslat libovolně velké tělo, které se drží v paměti procesu.
