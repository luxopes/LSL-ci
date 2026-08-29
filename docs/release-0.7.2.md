# LSL 0.7.2

LSL 0.7.2 je funkční vydání HTTP serveru bez nové syntaxe jazyka. Dynamický
aplikační server nyní přijímá request body, takže čistě LSL aplikace může
obsloužit POST formuláře, JSON API a binární uploady bez cizí HTTP vrstvy.
Statický souborový režim zůstává beze změny a request body dál odmítá.

## Hlavní změny

- `httpserver.serve` (dynamický handler) přijímá požadavky s `Content-Length`
  tělem do dokumentovaného limitu 8 MiB. Handler dostává v requestu nové
  klíče: `body` je vždy `ByteArray` (prázdné bez těla) a `body_text` je
  `String` s UTF-8 dekódovaným tělem, nebo `None`, pokud tělo není platné
  UTF-8. Validace je well-formed RFC 3629: žádné overlong sekvence,
  surrogaty ani hodnoty nad U+10FFFF; raw byte copy runtime primitiva se na
  hranici serveru nikdy nepoužije bez této kontroly.
- Server odpovídá interim `HTTP/1.1 100 Continue` na `Expect: 100-continue`
  před čtením těla, takže curl a podobní klienti neztrácejí sekundu čekáním.
- Tělo se čte se stejným socket timeoutem jako hlavičky: nekompletní tělo je
  `400`, timeout `408`, deklarovaná délka nad 8 MiB `413` bez čtení dat a
  data nad deklarovanou délku `400`. `Transfer-Encoding` zůstává odmítnuté.
- Statický režim (`lsl server --dir`) i HTTPS nginx režim jsou beze změny:
  jen `GET`/`HEAD` a žádná request body. Dynamický handler nyní vidí i další
  metody (`POST`, `PUT`, `DELETE`, ...) a o odpovědi rozhoduje sám.
- Regresní sada `tests/httpserver_conformance.lsl` pokrývá UTF-8 round-trip
  POST, binární tělo (`body_text` je `None`), `Expect: 100-continue`,
  nekompletní tělo po half-close, deklarovanou délku nad limit, prázdné tělo
  (`body_text` je prázdný `String`) a to, že statický server tělo dál
  odmítá.

## Ověření vydání

Vydání prošlo bitově shodným self-host fixed pointem, plnou testovací sadou,
porovnáním configu a kontrolou release ELF (jeden `R E LOAD`, RW
`GNU_STACK`, bez `INTERP` a `DYNAMIC`). Compiler má SHA-256
`cfe35706540168443f7a95982d3cac6f90a40d0775fcedd2cee00bc7a3b9de71`, CLI
`3e21c4e05838d374c756bbb7b48c2d571d1e2b87d7cdda03c4a2744487b60bcb` a test
runner `d91aebca46bc75b07796c62c75bce02881ec10024385efa56a89c28ccf42ab59`.

## Kompatibilita

Request dictionary dynamického handleru má dva nové klíče (`body`,
`body_text`); existující klíče a chování statického serveru se nemění.
Handler, který tělo ignoruje, funguje beze změny.
