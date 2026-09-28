# Knihovna requests

`load requests`

HTTP klient ve stylu Python `requests`, postavený na společném transportu
`http`. Každý požadavek vrátí objekt `Response` s poli `status`, `text`
a `ok`; `json()` dekóduje tělo, `raise_for_status()` převede selhání
transportu a HTTP chyby na zachytitelné výjimky.

Transport používá systémový `/usr/bin/curl` spuštěný přímým `execve`
s konfigurací na stdin — těla požadavků, hlavičky s autorizací a jiné
citlivé hodnoty se nikdy neobjeví v argv procesu. Prosté HTTP je povoleno
jen pro číselný loopback `127.0.0.1`/`[::1]`; jinak se vyžaduje HTTPS.

## Třída Response

```lsl
r = requests.get(url)
r.status_code  # alias r.status
r.status   # Int: HTTP status; 0 = selhání transportu
r.text     # String: tělo odpovědi (nebo chybová zpráva transportu)
r.ok       # Bool: 200–299
r.json()   # dekóduje tělo jako JSON
r.raise_for_status()  # chyba při selhání; jinak vrátí self
```

`Response(status, text)` lze vytvořit i přímo, např. v testech.

## Požadavky

```lsl
requests.get(url, headers=None, timeout=None)
requests.post(url, data=None, headers=None, timeout=None)
requests.put(url, data=None, headers=None, timeout=None)
requests.patch(url, data=None, headers=None, timeout=None)
requests.delete(url, data=None, headers=None, timeout=None)
requests.head(url, headers=None, timeout=None)
requests.request(method, url, data=None, headers=None, timeout=None)
requests.post_stream(url, data, headers, timeout, on_chunk, method="POST")
```

- `data` je String, nebo List/Dictionary — ty se před odesláním zakódují
  do JSON (`None` znamená prázdné tělo). Pro JSON se automaticky doplní
  `Content-Type: application/json`, pokud tuto hlavičku nezadáte sami.
- `headers` je Dictionary s nejvýše 256 záznamy; vstupní slovník se nemění.
- `request` přijímá i malé názvy metod, například `"get"`.
- Přesměrování se automaticky nenásledují; stav mimo 200–299 má `ok=False`.
- `timeout` je 1..3600 sekund; výchozí 60.
- `post_stream` volá `on_chunk(text)` s každým příchozím kusem a vrací
  `Response` se statusem a nahromaděným tělem.

## Příklad

```lsl
load requests

response = requests.get("https://api.example.com/data")
if response.ok:
    print response.json()["items"]
else:
    print "HTTP", response.status
end

body = {"name": "LSL"}
created = requests.post("https://api.example.com/items", body, {"Content-Type": "application/json"})
call created.raise_for_status()
```

## Chyby

- `ConnectionError` — selhání transportu (`status == 0`).
- `HTTPStatusError` — stav mimo 200–299.
- `JsonError` — prázdné nebo neplatné JSON v `json()`.
- `HTTPError` — neplatná URL, hlavička, metoda, timeout nebo příliš velké
  tělo (validace sdílená s knihovnou `http`).

## Související stránky

- `lsl man http` — nízký transport s injekcí pro testy
- `lsl man httpserver` — HTTP server
- `lsl man json` — kódování a dekódování JSON
