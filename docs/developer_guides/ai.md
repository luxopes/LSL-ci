# Knihovna ai

`load ai`

Orchestrace AI služeb kompatibilních s OpenAI: chat se
strukturovanými chybami providera, retry a SSE streamováním. Transport
sdílí s knihovnou `http` (curl config na stdin, citlivé hlavičky mimo
argv).

## Funkce

### ai.request(endpoint, token, model, messages, options)

Synchronní chat požadavek. Vrací dekódovanou odpověď providera.

### ai.stream(endpoint, token, model, messages, options, on_event)

Požadavek se SSE odpovědí: `on_event(text)` dostává obsah po kusech
po dokončení přenosu. `transport_chunk` dostává surové části těla už během
přenosu. Varianta `stream` zatím neposílá `temperature`/`max_tokens`
a neopakuje požadavky přes `retries`.

### ai.decode_response(response)

Strukturované dekódování odpovědi `http`: mapuje stav 429/5xx na chyby
providera s omezeným textem.

### ai.content(response)

Vybere `choices[0].message.content`. JSON `null` vrátí jako `None`;
chybějící struktura vyvolá `AIProviderError`.

### ai.stream_text(text, on_event, cancel)

Zparsuje SSE text na události; `cancel()` vrací `True` pro předčasné
ukončení; místo callbacku lze předat `None`.

## Options

```lsl
{"temperature": Float, "max_tokens": Int, "timeout": Int,
 "retries": Int, "cancel": Function, "transport_chunk": Function}
```

`request` přijímá pouze uvedené klíče. Pro `tools`, `tool_choice` nebo
další parametry použijte `http.post` a `ai.decode_response`; viz příklad
v kapitole [AI aplikace](10-ai-applications.md).

## Příklad

```lsl
load ai

response = ai.request("https://api.example.com/v1/chat/completions",
                      "sk-token", "gpt-4o-mini",
                      [{"role": "user", "content": "Ahoj"}],
                      {"timeout": 30})
print ai.content(response)
```

## Chyby

- `AIProviderError` — chyba hlášená providerem (rate limit, chyba
  serveru), s omezeným textem odpovědi.
- `AIProviderError` — také neplatná konfigurace nebo JSON odpověď.
- `AICancelled` — zrušení přes callback `cancel`.

## Související stránky

- `lsl man 10-ai-applications` — kapitola o AI aplikacích
- `lsl man requests` / `lsl man http` — HTTP transport
- `lsl man json` — dekódování odpovědí
