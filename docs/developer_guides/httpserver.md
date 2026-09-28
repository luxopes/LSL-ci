# Knihovna httpserver

`load httpserver`

Omezený HTTP/1.1 server pro Linux x86-64 s čistě syscallovým transportem.
Statické soubory se otevírají relativně k jedné připnuté adresářové
handle přes `openat2(RESOLVE_BENEATH|NO_MAGICLINKS|NO_SYMLINKS)`, takže
úniky cestou URL a symlinků selhávají v jádře, ne na stringové kontrole.

Za `lsl server` stojí právě tato knihovna.

## Spouštění

```lsl
httpserver.serve(handler, address, port, maximum_requests)
httpserver.serve_static(root, address, port, maximum_requests)
httpserver.serve_listener(listener, root_handle, handler, maximum_requests, announce)
httpserver.serve_static_tls(root, address, port, certificate, private_key, maximum_requests)
```

- `handler` je funkce `(request) -> response`; `None` znamená statický
  režim nad `root`.
- `maximum_requests` omezí počet obsloužených požadavků; `0` = bez limitu.
- HTTPS režim (`serve_static_tls`) používá systémový nginx/OpenSSL
  frontend; `--max-requests` nepodporuje.
- `httpserver.set_body_limit(limit)` / `httpserver.body_limit()` nastaví
  a přečte limit těla požadavku (výchozí bez limitu).

## Request a response handleru

Handler dostane Dictionary:

```lsl
{"ok": Bool, "method": String, "target": String, "version": String,
 "headers": Dictionary, "body": ByteArray, "body_text": String|None}
```

Vrátit může:

```lsl
{"body": "text", "content_type": "text/plain; charset=utf-8"}
{"status": 404, "body": "nenalezeno"}   # vlastní status
```

Chyba uvnitř handleru se přeloží na `500 Internal Server Error`; po každém
požadavku se uvolní alokátor, takže dlouhoběžící listener nevyčerpá paměť.

## Příklad

```lsl
load httpserver

function handler(request):
    return {"body": request["method"] + " " + request["target"] + chr(10)}
end

call httpserver.serve(handler, "127.0.0.1", 8080, 0)
```

## Chyby

- `ServerError` — chyby transportu a naslouchání (např. obsazený port).

## Související stránky

- `lsl man http` / `lsl man requests` — klient
- `lsl man fd` — nízkoúrovňové I/O
- `lsl man sandbox` — capability sandbox pro nasazení
