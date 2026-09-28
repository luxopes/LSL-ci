# Release LSL 0.8.9

Vydání z 28. 9. 2026. Compiler a host runtime zůstávají pure LSL.

## Automatické .env

`load env` za běhu načte `.env` vedle vstupního skriptu; u zkompilovaného
programu vedle binárky, u stdin v pracovním adresáři. Proměnné prostředí
mají přednost včetně prázdných hodnot. Podporuje komentáře, uvozovky,
UTF-8/CRLF a `export`; nespouští shell ani interpolaci. Chybějící soubor
nevadí, neplatný vyvolá chybu bez zveřejnění hodnot. Limitem je 1 MiB.
`env.load_dotenv(path)` umožní explicitní načtení. Prostředí potomků se nemění.
Podrobnosti: [env](developer_guides/env.md).

## Requests a manuály

`requests` je součástí instalace a shodný zdroj je i v LSL-Packages.
Poskytuje GET/POST/PUT/PATCH/DELETE/HEAD, obecný request, JSON, timeout,
vlastní hlavičky a streamování. Response nabízí `status`/`status_code`,
`text`, `ok`, `json()` a `raise_for_status()`. Transport používá curl
s konfigurací na stdin; autorizace ani těla nejsou v argv.
HTTP je povoleno pouze na číselném loopbacku, jinak HTTPS.
Přesměrování se automaticky nenásledují.

Všechny veřejné standardní knihovny mají vlastní offline stránku,
například `lsl man env`, `lsl man requests`, `lsl man httpserver`.
Jsou zahrnuté do instalátoru, webového i ZIP manuálu a TUI prohlížeče.

## Opravy chyb a příkladů AI

`last_error()` bezpečně vrací `None` před první chybou a po úspěšném
`safe`/`try`; stará chyba nezůstává ani při `return`, `break` či `continue`.
Zachycená chyba zůstává dostupná pro obsluhu, stav je oddělený po vláknech.
Kapitola AI aplikací má opravené čárky, parametry požadavků, SSE volání
a kompletní příklad nástrojů přes `http.post`.

## Přechod

Spusťte `lsl update`, u systémové instalace
`sudo /usr/local/bin/lsl update --system`. Z archivu použijte
`bin/lsl-install "$HOME/.local"`. Starší generace se zachová pro rollback.
Samostatně zkompilované programy je pro novou podporu potřeba přeložit znovu.
Registrový balíček requests vyžaduje LSL 0.8.9 nebo novější.

Máte-li už původní 0.8.9, stáhněte aktualizovaný archiv a spusťte jeho
`bin/lsl-install "$HOME/.local"`, u systémové instalace
`sudo ./bin/lsl-install /usr/local`. Shodné číslo verze samotné `lsl update`
nepřeinstaluje; instalátor zachová předchozí generaci pro rollback.
