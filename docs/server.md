# HTTP/HTTPS server v LSL 0.7

Příkaz `lsl server` od 0.7 spouští server; informace o původu knihoven se
přesunula do `lsl origin`.

## Statický HTTP server

```text
lsl server --dir public --bind 127.0.0.1 --port 8080
lsl server --dir public --port 8080 --once
lsl server --dir public --port 8080 --max-requests 100
```

Výchozí hodnoty jsou `--dir .`, `--bind 127.0.0.1`, `--port 8080` a
neomezený počet požadavků. Bind adresa musí být číselná IPv4 a port musí být
v rozsahu 1–65535.

Nativní LSL frontend záměrně implementuje malou podmnožinu HTTP/1.1:

- přijímá pouze `GET` a `HEAD`, jedno spojení obslouží jeden požadavek;
- omezuje hlavičku na 16 KiB, 64 polí a target na 2048 bytů;
- vyžaduje neprázdný `Host` v HTTP/1.1 a odmítá duplicate/folded hlavičky, request body
  i `Transfer-Encoding`;
- nastavuje read/write timeout a odpovědi vždy zavírá;
- root drží přes otevřený directory descriptor a soubory otevírá pomocí
  `openat2(RESOLVE_BENEATH | NO_MAGICLINKS | NO_SYMLINKS)`, takže `..`, symlink
  ani změna pracovního adresáře nemohou opustit document root;
- po `fstat` obslouží jen běžný soubor; FIFO, socket ani device nemohou
  zablokovat server při otevření;
- jednotlivý soubor je omezen na 8 MiB.

URL cesty používají úzkou ASCII podmnožinu. Percent-encoding, backslash,
prázdná komponenta a `.`/`..` se odmítají. `/` mapuje na `index.html`.

## HTTPS

LSL neimplementuje vlastní TLS ani kryptografii. HTTPS režim spustí udržovaný
systémový nginx/OpenSSL stack s privátně vygenerovanou konfigurací:

```text
lsl server --dir public --bind 0.0.0.0 --port 8443 \
  --tls-cert /etc/lsl/fullchain.pem \
  --tls-key /etc/lsl/private-key.pem
```

Oba PEM soubory musí být zadány společně. Jejich cesty i document root se
nejdřív kanonizují; do nginx konfigurace se vkládají pouze jako escapované
quoted hodnoty. Povolené jsou TLS 1.2 a 1.3, session tickets jsou vypnuté,
symlinky a autoindex zakázané. HTTPS režim je statický a nepodporuje
`--max-requests`; pro dlouhodobou produkci je stále vhodnější spravovaný
reverse proxy/service-manager setup s rotací certifikátů a logy.

HTTPS vyžaduje `/usr/sbin/nginx` (nebo `/usr/bin/nginx`). Pokud chybí, příkaz
selže zavřeně a nespustí prostý HTTP fallback.

## Server z LSL kódu

```lsl
load httpserver

function application(request):
    return {
        "status": 200,
        "content_type": "application/json",
        "body": "{\"ok\":true}" + chr(10)
    }
end

call httpserver.serve(application, "127.0.0.1", 8080, 0)
```

Handler dostane Dictionary s `method`, `target`, `version`, `headers`,
`body` a `body_text`. Od 0.7.2 dynamický server přijímá request body a od
0.7.3 bez pevného limitu (výchozí stav; `httpserver.set_body_limit(bytes)`
nastaví strop, `0` jej vypne — veřejně vystavený server by měl limit vždy
nastavit): `body` je vždy `ByteArray` (prázdné bez těla) a `body_text` je UTF-8
dekódovaný `String`, nebo `None`, když tělo není well-formed UTF-8 (RFC
3629, bez overlong sekvencí a surrogatů). Na `Expect: 100-continue` server
odpoví interim `HTTP/1.1 100 Continue` před čtením těla. Nekompletní tělo je
`400`, timeout `408`, deklarovaná délka nad nastavený limit `413` a
`Transfer-Encoding` zůstává odmítnuté. Buffer těla roste podle skutečně
přijatých dat, takže deklarovaná délka nealokuje paměť dopředu. Dynamický handler vidí i `POST`, `PUT` a další metody a
o odpovědi rozhoduje sám; statický režim dál obsluhuje jen `GET`/`HEAD` bez
request body.
Handler může vrátit String/ByteArray (status 200), nebo Dictionary s `status`,
`reason`, `body` a `content_type`. Odpověď handleru omezuje stejný
konfigurovatelný limit (výchozí bez limitu) a jeho
zachytitelná chyba se změní na request-local 500; listener pak pokračuje.
Dynamický handler běží ve stejném procesu;
pro nedůvěryhodný kód nebo dostupnostně kritickou službu jej spusťte pomocí
`lsl sandbox --profile server` a před něj postavte TLS reverse proxy.

## Původ instalované knihovny

```text
lsl origin
lsl origin textkit
```

První příkaz vypíše aktivní registry endpoint. Varianta se jménem vezme
per-package lock, přísně načte `NAME.lsl.origin`, znovu spočítá SHA-256
instalovaného `NAME.lsl` a metadata vypíše pouze při shodě. Nekontaktuje síť;
ručně změněný zdroj nebo přerušený update skončí chybou integrity.
