# 17. CLI, knihovny a terminálový manuál

LSL 0.8.0 přidává přehlednou správu knihoven, barevnou nápovědu a TUI.
Od 0.8.2 jsou grafické knihovny volitelnými balíčky (`lsl install gfx`,
`lsl install ui`, `lsl install display`). Deklarované závislosti se nejprve
ověří a nainstalují automaticky. Cyklus či neplatný hash instalaci zastaví;
již úspěšné závislosti mohou zůstat nainstalované.

Chybové zprávy jsou barevné na terminálu. `NO_COLOR` má přednost před
`FORCE_COLOR`; `FORCE_COLOR=1` vynutí barvy i do pipe a `FORCE_COLOR=0` je
zakáže. Bez vynucení zůstávají pipes a `TERM=dumb` bez ANSI sekvencí.
Zdrojová diagnostika zachovává svůj dosavadní výstupní kanál; běhové chyby
píší na stderr. IDE nastavující `NO_COLOR=1` musí barvy povolit na své straně.
Celá klientská implementace je v LSL. Pro stahování se používá systémový
curl, pro ověřování SHA-256 systémový sha256sum; nepoužívají se shellové
instalační skripty balíčků.

## Přehled a kontrola instalace

```bash
lsl list
lsl check random
lsl check textkit
```

`list` vypíše veřejné knihovny dodané s LSL (`bundled`) a uživatelské moduly
v `~/.local/lib/lsl/stdlib` (`user`), včetně jejich cest. Interní moduly
začínající podtržítkem nejsou veřejné balíčky. Bundled knihovny mají přednost
před stejnojmennými uživatelskými soubory. Moduly vedle jednotlivých projektů
se do globálního seznamu nezahrnují.

`check NAME` končí stavem 0, pokud existuje nainstalovaný soubor knihovny,
jinak stavem 1. Neprovádí kompilaci ani spuštění a nepotřebuje síť. Ani jeden
z těchto příkazů nevytváří adresáře v HOME. Pro ověření SHA-256 a původu
uživatelské instalace slouží `lsl origin NAME`.

## Hledání a instalace

```bash
lsl search
lsl search text
lsl install textkit
lsl update textkit
```

`search [QUERY]` vyhledává v názvech i popisech bez rozlišení velikosti písmen.
Bez dotazu ukáže celý katalog. U výsledků uvádí verzi, popis, stav instalace
a příkaz k instalaci. Nenalezený výsledek končí stavem 1; neplatné argumenty
stavem 2. Síťová chyba je chyba, nikoli prázdný katalog.

Produkční registry je `https://lsl.lux-ai.cz/packages`; pro vývoj lze nastavit
`LSL_REGISTRY`. Katalog v1 se stahuje z `catalog.json`. Metadata obsahují
jméno, verzi, popis, licenci, velikost, zdroj a SHA-256. Klient odmítá
neplatná jména, duplicitní položky, nebezpečné cesty a řídicí znaky.

Výsledek hledání potvrzuje dostupnost v katalogu, ne úspěch budoucí kompilace:
instalace znovu ověří skutečný zdroj, SHA-256 a jeho přeložitelnost. Knihovnu
nespouští. Uživatelské knihovny instalujte bez sudo. Bundled moduly se
aktualizují spolu s LSL.

## TUI správce balíčků

```bash
lsl install --tui
```

- Šipky, Home/End a PageUp/PageDown procházejí katalog.
- `/` otevře filtr podle názvu nebo popisu; Enter ho potvrdí, Esc zruší.
- Mezerník nebo Enter označí knihovnu; označení zůstává i při změně filtru.
- `i` nabídne instalaci vybraných položek; teprve `y` ji potvrdí.
- Již nainstalované uživatelské knihovny lze přeinstalovat. Bundled položky
  správce nepřepisuje.
- `q`, Ctrl-C nebo Ctrl-D zavře aplikaci a obnoví terminál.

Pokud jedna instalace selže, dřívější úspěšné instalace zůstávají zachované
a neúspěšné/neprovedené položky zůstávají označené. Nejde o transakci celého
výběru. TUI vyžaduje interaktivní stdin/stdout a terminál jiný než `dumb`.

## Offline manuál a nápověda

Od 0.8.6 prohlížeč i `lsl man --plain` formátují Markdown: nadpisy, odrážky,
kódové bloky, tabulky se zarovnanými sloupci, inline kód a odkazy se zobrazí
jako terminálové formátování. Bez terminálu zůstává struktura bez barev.
Instalátor a `lsl update` zobrazují průběh v procentech (na terminálu se
přepisuje na místě; v pipe se nevypisuje).

```bash
lsl man
lsl man random
lsl man --plain reference
lsl help install
```

Manuál obsahuje stejné Markdown kapitoly jako web, přibalené ke konkrétnímu
vydání. Nevyžaduje internet. V obsahu otevře Enter kapitolu; šipky a PageUp/
PageDown posouvají text. `/` hledá v obsahu kapitolu, v otevřené kapitole text;
`n` pokračuje na další výskyt. Esc vrací na obsah, `q` zavírá. Text se zalamuje
podle šířky terminálu. Markdown včetně příkladů zůstává čitelný jako text.

Volba `--plain` nebo přesměrovaný výstup zvolí textový režim. Bez tématu
vypíše obsah; s tématem celou kapitolu. Téma může být jednoznačná část ID,
například `random`, `cuda` nebo úplné `04-collections`.

V samotném jazyce lze nadále použít `help()` a nově také:

```lsl
help("print")
topic = "install"
help(topic)
help("random")
```

Nápověda je zabudovaná do programu: funguje i v samostatném ELF bez instalace
LSL. Přijímá nula nebo jeden argument typu String a vrací None. Neznámé téma
vyvolá zachytitelný HelpError; `help()` vypíše seznam podporovaných témat.
Detailní reference všech API je v manuálu.

## Editor lsl --tui

`lsl --tui [SOUBOR]` otevře terminálový editor ve stylu Vimu se zvýrazňováním
syntaxe LSL. Bez souboru začne s prázdným bufferem a `:w SOUBOR` jej uloží.

| Mód | Klávesy |
| --- | --- |
| Normální | `h j k l` nebo šipky, `w` / `b` slovo vpřed / zpět, `0` / `$` začátek / konec řádku, `gg` / `G` začátek / konec souboru, PgUp / PgDn |
| Normální | `x` smaže znak, `dd` smaže řádek (do schránky), `yy` zkopíruje řádek, `p` / `P` vloží pod / nad, `u` vrátí poslední změnu |
| Normální | `i` / `a` / `A` / `I` vkládání na kurzoru / za ním / na konci / na začátku řádku, `o` / `O` nový řádek pod / nad |
| Normální | `/text` hledá, `n` další výskyt, `:` příkazový řádek |
| Příkazy | `:w [SOUBOR]` uloží, `:q` ukončí (odmítne neuložené změny), `:q!` ukončí bez uložení, `:wq` uloží a ukončí |
| Vkládací | text, Enter (převezme odsazení řádku), Backspace (na začátku řádku spojí s předchozím), Delete, Tab = čtyři mezery, šipky, Esc zpět do normálního módu |

Stavový řádek ukazuje mód, název souboru, `[+]` u neuložených změn a pozici
kurzoru. Editor pracuje se soubory do 4 MiB, nic nespouští a nevolá shell;
program spustíte po uložení příkazem `lsl SOUBOR`.

## Knihovny a sudo

Uživatelské knihovny (`lsl install NAME`) leží v `~/.local/lib/lsl/stdlib`
uživatele, který příkaz spustil. `sudo` na Debianu nastaví `HOME=/root`,
takže `sudo lsl list`, `sudo lsl check NAME` ani `sudo lsl program.lsl`
knihovny běžného uživatele nevidí a `sudo lsl install NAME` je nainstaluje
rootovi. Aktualizace LSL (`lsl update`, `sudo lsl update --system`)
uživatelské knihovny nemaže — ověřujte je bez `sudo`.

## lsl about

`lsl about` vypíše, co LSL je, jeho verzi, web a licenci. `lsl about NAME`
vypíše krátký popis knihovny: vestavěné knihovny (`random`, `os`, `tui`, …)
mají popisy zabudované, knihovny z registru se popisují úvodním komentářem
svého zdroje (`# ...` řádky na začátku souboru až po první prázdný řádek).
Stejný popis začíná výstup `help("NAME")` v programu, takže `help()` funguje
i pro nainstalované uživatelské knihovny.

```text
lsl about
lsl about random
lsl about term
```

## Barvy a systémové aktualizace

Nápověda, stav instalace a diagnostika používají barvy jen na terminálu.
`NO_COLOR=1 lsl list` je vypne. Při přesměrování nejsou ve výstupu ANSI barvy.
TUI i bez barev potřebuje řídicí sekvence pro pohyb kurzoru a zvýraznění výběru.

```bash
lsl update --check
sudo /usr/local/bin/lsl update --system
sudo /usr/local/bin/lsl update --system --rollback
```

`--system` samo nezvyšuje oprávnění. Úplná cesta funguje i tehdy, když sudo
nemá `/usr/local/bin` ve svém PATH. Podepsaný updater uchovává předchozí
generaci pro rollback.

### Jednorázový přechod z 0.7.8

Skutečné CLI 0.7.8 má chybu převodu nulového offsetu při čtení tar archivu;
`lsl update` skončí `Int expects Int, Float, String, or Bool` ještě před
změnou instalace. V 0.8.0 je chyba opravená a regresní testy pokrývají také
interní ABI CLI (nejen veřejné testovací drivery).

Z 0.7.8 proto jednou použijte instalační program z nového archivu:

```bash
curl -fSLO https://lsl.lux-ai.cz/downloads/lsl-0.8.7-linux-x86_64.tar.gz
curl -fSLO https://lsl.lux-ai.cz/downloads/SHA256SUMS
sha256sum --ignore-missing -c SHA256SUMS
tar -xzf lsl-0.8.7-linux-x86_64.tar.gz
sudo ./lsl-0.8.7/bin/lsl-install /usr/local
```

Instalátor 0.8.7 rozpozná stávající spravovanou instalaci a nepřepisuje
soubory přes symlinky: připraví novou generaci, otestuje ji a atomicky přepne
aktivní verzi. Zachová předchozí verzi pro rollback. U legacy instalace
v `/usr/local` nebo `~/.local` nejprve vytvoří její snapshot. Pro uživatelskou
instalaci použijte bez sudo `./lsl-0.8.7/bin/lsl-install "$HOME/.local"`.

Při přechodu z 0.8.2 aktualizujte nainstalované X11 příkazem `lsl update x11`,
ideálně před `lsl update`. X11 0.8.3 používá `time.monotonic()` místo
číselného `clock()` a podporuje obě verze. `clock()` v LSL 0.8.3 vrací
čitelný UTC String; pro intervaly používejte `monotonic()` nebo modul `time`.
Další aktualizace z opravené 0.8.0 již používají běžné `lsl update`.
