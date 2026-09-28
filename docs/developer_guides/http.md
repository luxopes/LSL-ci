# Knihovna http

`load http`

Nízký HTTP/HTTPS klient řízený curl konfigurací na stdin. Těla požadavků,
autorizační hlavičky a další citlivé hodnoty nikdy nevstupují do argv
procesu — konfigurace se předává curl přes standardní vstup.

Pro běžné použití je pohodlnější knihovna `requests`, která vrací objekt
`Response` a nabízí `json()` a `raise_for_status()`. `http` vrací
strukturu:

```lsl
{"status": Int, "text": String, "ok": Bool}
```

- `status` — HTTP status; `0` znamená selhání transportu (chybová zpráva
  je pak v `text`).
- `ok` — `True` pro statusy 200–299.

## Požadavky

```lsl
http.get(url, headers=None, timeout=None)
http.post(url, body, headers, timeout, method="POST")
http.post_stream(url, body, headers, timeout, on_chunk, method="POST")
```

- `body` je String, nebo List/Dictionary — ty se zakódují do JSON.
- `headers` je Dictionary s nejvýše 256 záznamy.
- `timeout` je 1..3600 sekund; výchozí 60.
- `post_stream` volá `on_chunk(text)` s každým kusem odpovědi.
- Prosté HTTP je povoleno jen pro číselný loopback `127.0.0.1`/`[::1]`;
  ostatní adresy vyžadují HTTPS (TLS 1.2+).

## Injekce transportu pro testy

```lsl
http.get_with(curl_path, url, headers=None, timeout=None)
http.post_with(curl_path, url, body, headers, timeout, method="POST")
http.post_stream_with(curl_path, url, body, headers, timeout, on_chunk, method="POST")
```

Varianta `_with` spouští místo `/usr/bin/curl` zadaný program a je určena
pro hermetické conformance testy.

## Validace

- `http.validate_url(url)` — délka 1..8192 bytů, jen bezpečné ASCII znaky,
  bez user-info a fragmentů, platný host a port.
- `http.method_name(method)` — token 1..32 znaků; odmítá řídicí znaky.
- Limit odpovědi: 16 MiB (`max-filesize`). Limit těla požadavku: 4 MB
  zakódovaných (8 MB po escapování).

## Chyby

- `HTTPError` — neplatná URL, hlavička, metoda, timeout nebo příliš velké
  tělo.

## Související stránky

- `lsl man requests` — pohodlnější klient s objektem Response
- `lsl man httpserver` — HTTP server
