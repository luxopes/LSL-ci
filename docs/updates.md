# Podepsané aktualizace LSL

```text
lsl update                    # samotné LSL, stabilní kanál
lsl update textkit            # pouze knihovna
lsl update --check            # ověření dostupné verze, bez instalace
lsl update --rollback         # návrat k předchozí funkční instalaci
sudo /usr/local/bin/lsl update --system
```

Klient podporuje Linux x86_64 a aktivní instalaci v `~/.local` nebo
`/usr/local`. Prefix určuje skutečný `/proc/self/exe`, ne PATH ani aktuální
adresář. Checkout a vlastní instalační prefixy se automaticky nepřepisují;
`--check` funguje i z checkoutu. Systémové změny potřebují současně UID 0
a explicitní `--system`, také při rollbacku. Symlinkové prefixy a adresáře
zapisovatelné jinými uživateli/skupinou se odmítají.
`bin` a deployment store v `lib` musí být na stejném souborovém systému;
jinak atomický přesun bezpečně selže před aktivací nové verze.

## Důvěra a limity

Stabilní manifest je výhradně
`https://lsl.lux-ai.cz/updates/channels/stable.json`, podpis je raw 64bytový
Ed25519 na stejné URL s `.sig`. Veřejný PEM klíč i jeho ID jsou zabudované
v `compiler/pure/update.lsl`:

```text
6930f9769efdaa1f62183875d540b340bab10f40060082f29eedd5dcead8231a
```

Klíč ze serveru ani `LSL_REGISTRY` nemohou změnit důvěru updateru. Ověřují se
přesné původní bajty JSON před jeho dekódováním a použitím URL archivu.
JSON odmítá duplicitní/neznámá pole, nesprávné typy, kanál, produkt, key ID,
nekanonickou verzi, neplatné datum, duplicitní platformy a jiný layout.
`released_at` přijímá UTC `YYYY-MM-DDTHH:MM:SSZ`, jak jej zapisuje vydavatel.
Datum samo není důkazem čerstvosti: protokol nemá expiraci ani transparentní
log; starší verzi než právě aktivní klient odmítne. Výslovný vývojářský
přepínač `--allow-downgrade` dovolí nižší podepsanou verzi, nikdy však
neobchází podpis, integritu ani platformu. Stejná verze je no-op.

HTTPS používá systémové CA a přesnou doménu `lsl.lux-ai.cz`; přesměrování,
HTTP, porty, query, fragmenty, credentials a alternativní origin se nepovolují.
Manifest je omezen na 64 KiB, podpis na 64 B, komprimovaný archiv na 32 MiB
a rozbalený tar na 64 MiB. Čas i velikost jsou omezeny během přenosu/rozbalování
také přes kernelové resource limits, nezávisle na HTTP Content-Length.
Velikost a SHA-256 archivu musí přesně odpovídat podepsanému manifestu.

Tar parser je LSL, nikoli výstup parsovaný z `tar -t`. Před prvním zápisem
prověří všechny hlavičky a checksumy; povolí jen regulární soubory a adresáře
v jediném deklarovaném kořeni. Odmítá absolutní/rodičovské/duplicitní cesty,
chybějící rodiče, symlinky, hardlinky, FIFO, zařízení, sparse, PAX a GNU
extension records. Podporuje běžný ustar a GNU tar bez rozšíření, nejvýše
4096 členů, jednotlivý soubor do 16 MiB a žádné setuid/setgid/sticky bity.
Očekávaný `bin/lsl-install` musí být spustitelný Linux x86_64 PIE ELF.

## Transakce a obnova

Celá instalace je připravena v nové generaci
`PREFIX/lib/lsl-updates/generations/g-PID-N`. Podepsaný installer běží až po
ověření archivu, pouze s tímto staging prefixem. Kontroluje se deklarovaná
verze CLI a skutečný překlad/spuštění programu používajícího standardní JSON
knihovnu. Data se před zveřejněním flushnou na disk.

Při první migraci vznikne také funkční kopie staré instalace. Známé nástroje
v `PREFIX/bin` se postupně změní na odkazy přes `lsl-updates/current`, který
stále ukazuje na starou kopii. Samotná aktivace mění jediný odkaz přes atomický
`rename(2)`. Spuštěné staré programy mohou bezpečně doběhnout. Původní
`PREFIX/lib/lsl`, instalované knihovny a nesouvisející nástroje zůstanou.

Pod zámkem `flock` se před přepnutím uloží `previous` a trvalý journal
`pending`. Selže-li kontrola po přepnutí, obnoví se starý odkaz. Při pádu či
výpadku proudu během transakce příští `lsl update` nejprve obnoví `previous`.
`--rollback` provede tutéž ověřenou transakci bez sítě. Současné aktualizace
se odmítnou, zámek uvolní i ukončení procesu. Generace se automaticky nemažou,
aby zůstaly dostupné pro obnovu; odstraní se pouze vlastní privátní scratch.
Při násilném ukončení může zůstat scratch nebo neaktivní generace na disku.

Rollback do staršího vydání bez self-updateru obnoví i jeho staré CLI. Další
obnova pak vyžaduje novější updater nebo ruční instalaci ověřeného vydání.
Tento klient sám nepřepisuje publikované archivy ani manifesty; bude součástí
příštího zveřejněného buildu.

## Systémové nástroje a testy

Řídicí logika, parser, kontroly a transakce jsou v LSL. Důvěryhodné systémové
programy z `/usr/bin` nebo `/bin` poskytují HTTPS (`curl`), Ed25519 (`openssl`
s podporou `pkeyutl -rawin`), SHA-256 (`sha256sum`), gzip dekompresi (`gzip`),
limity (`timeout`, `prlimit`) a úklid scratch (`rm`). Spouštějí se přímým argv
bez shellu a s prázdným prostředím. Bez těchto závislostí updater bezpečně
selže; diskless wget fallback knihoven není náhradou ověřování self-updateru.
Použité rozhraní popisují [curl](https://curl.se/docs/manpage.html),
[OpenSSL](https://docs.openssl.org/3.0/man1/openssl-pkeyutl/) a
[Linux rename(2)](https://man7.org/linux/man-pages/man2/rename.2.html).

Běžný test runner obsahuje offline negativní testy a veřejný podepsaný
manifest 0.7.7. Soukromý produkční klíč se pro testování nepoužívá.
Volitelný integrační test se skutečným veřejným archivem:

```text
./compiler/pure/lslc-direct tests/compiler/update_release_integration.lsl /tmp/update-release-test
/tmp/update-release-test /absolute/path/lsl-0.7.7-linux-x86_64.tar.gz
```

Test vytvoří izolovaný privátní prefix, ověří podpis i archiv, provede
instalaci, migraci, aktivaci, rollback a překlady, potom svůj prefix odstraní.
Nezasahuje do skutečné uživatelské ani systémové instalace.

`tests/compiler/update_online_integration.lsl` navíc ověřuje celý produkční
HTTPS přenos a upgrade. Používá testovací frontend
`tests/compiler/update_cli_fixture.lsl`, který pouze hlásí starou verzi 0.7.6;
updater, podpis, archiv i installer jsou skutečné. Test očekává veřejnou
stabilní 0.7.7 a argumenty: bezpečný rodičovský adresář pro dočasný testovací
HOME (ne pod world-writable `/tmp`), přeložený testovací frontend a cestu
k `lsl-install`. Nevytváří ani nepodepisuje produkční release.
