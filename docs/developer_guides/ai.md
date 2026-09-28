# Knihovna ai

`load ai`

Orchestrace AI služeb kompatibilních s OpenAI: chat a embeddingy se
strukturovanými chybami providera, retry a SSE streamováním. Transport
sdílí s knihovnou `http` (curl config na stdin, citlivé hlavičky mimo
argv).

## Funkce

### ai.request(endpoint, token, model, messages, options)

Synchronní chat/embedding požadavek. Vrací dekódovanou odpověď providera.

### ai.stream(endpoint, token, model, messages, options, on_event)

Streamovaná varianta (SSE): `on_event(text)` dostává obsah po kusech.

### ai.decode_response(response)

Strukturované dekódování odpovědi `http`: mapuje stav 429/5xx na chyby
providera s omezeným textem.

### ai.content(response)

Vybere text obsahu z odpovědi providera.

### ai.stream_text(text, on_event, cancel)

Zparsuje SSE text na události; `cancel()` vrací `True` pro předčasné
ukončení.

## Options

```lsl
{"temperature": Float, "max_tokens": Int, "timeout": Int,
 "retries": Int, "cancel": Function, "transport_chunk": Function}
```

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
- `AIError` — neplatná konfigurace požadavku.

## Související stránky

- `lsl man 10-ai-applications` — kapitola o AI aplikacích
- `lsl man requests` / `lsl man http` — HTTP transport
- `lsl man json` — dekódování odpovědí
