# 10. AI aplikace

Tato kapitola vysvětluje, jak v LSL pracovat s AI modely přes
OpenAI-compatible API — od jednoduchého dotazu přes streaming až po
function calling a správu secrets.

## Co k tomu potřebujete

- **API klíč** k OpenAI nebo kompatibilní službě (např. OpenAI,
  Groq, lokální Ollama).
- **Moduly `ai`, `json`, `http`, `env`** — všechny jsou vestavěné.
- **`/usr/bin/curl`** — LSL ho používá jako HTTP transport (bezpečně,
  přes přímé argv, ne přes shell).

## Jak to funguje

1. Váš program sestaví **messages** — seznam zpráv v konverzaci
   (role system/user/assistant).
2. Zavolá `ai.request()` s endpointem, tokenem, modelem a messages.
3. LSL pošle HTTP POST na OpenAI API.
4. Odpověď (JSON) se naparsuje a vrátí jako Dictionary.
5. `ai.content(response)` z něj bezpečně extrahuje text.

## Architektura AI stacku

| Modul | Odpovědnost |
|---|---|
| `ai` | OpenAI-compatible request, validace response, streaming |
| `json` | Enkódování a dekódování JSON |
| `http` | HTTP(S) transport přes curl (bezpečný argv) |
| `env` | Runtime hranice pro secrets (API klíče, tokeny) |

## Rychlý start: jednoduchý AI dotaz

```lsl
load ai
load json
load env

# Načtení API klíče (nikdy ne hardcode!)
token = env.require("OPENAI_API_KEY")

# Příprava messages
messages = [
    {"role": "system", "content": "Jsi užitečný asistent."}
    {"role": "user", "content": "Vysvětli, co je LSL za 3 věty."}
]

# Odeslání požadavku
response = ai.request(
    "https://api.openai.com/v1/chat/completions",   # endpoint
    token,                                            # API klíč
    "gpt-4o",                                        # model
    messages,                                         # messages
    {"max_tokens": 200, "temperature": 0.7}           # options
)

# Získání odpovědi
text = ai.content(response)
print "AI odpověď:", text
```

## Modul ai — API

### ai.request(endpoint, token, model, messages, options)

Odešle synchronní požadavek a vrátí Dictionary s odpovědí.

```lsl
response = ai.request(
    "https://api.openai.com/v1/chat/completions",
    token,
    "gpt-4o",
    messages,
    {
        "max_tokens": 500          # maximální délka odpovědi
        "temperature": 0.7         # kreativita (0.0–2.0)
        "top_p": 0.9               # nucleus sampling
        "stop": ["###", "---"]     # stop sekvence
    }
)
```

Options je Dictionary odpovídající OpenAI API parametrům.

### ai.content(response)

Bezpečně extrahuje první textovou odpověď:

```lsl
text = ai.content(response)
if text == None:
    print "Žádná textová odpověď"
else:
    print text
end
```

### ai.stream — streamování odpovědi

```lsl
full_response = ""

function on_token(token):
    # Token je část odpovědi (String)
    full_response = full_response + token
    print token  # okamžitý výpis (bez newline pro postupný efekt)
end

call ai.stream_text(
    "https://api.openai.com/v1/chat/completions",
    token,
    "gpt-4o",
    messages,
    {"max_tokens": 500},
    on_token
)

print ""  # newline po streamu
print "Celá odpověď:", full_response
```

`ai.stream_text` validuje OpenAI SSE (Server-Sent Events) formát, `data:`
eventy, `[DONE]`, provider errors a předává content chunky do callbacku.

### Chybové stavy

```lsl
try:
    response = ai.request(endpoint, token, model, messages, options)
    text = ai.content(response)
    print text
else:
    err = last_error()
    print "AI chyba:", err
    # Může být:
    # - AIProviderError: chyba od provideru (4xx, 5xx)
    # - AICancelled: operace zrušena
    # - JsonError: neplatná JSON odpověď
end
```

Podrobnější diagnostika:

```lsl
response = ai.request(endpoint, token, model, messages, options)

# Kontrola struktury odpovědi
if response == None:
    print "Prázdná odpověď"
elif not response["ok"]:
    print "HTTP chyba:", response["status"]
    print "Tělo:", response["text"]
else:
    text = ai.content(response)
    if text != None:
        print "Úspěch:", text
    else:
        print "Neočekávaná struktura odpovědi"
        print json.pretty(response)
    end
end
```

## Modul http — HTTP/HTTPS komunikace

### http.get(url)

```lsl
response = http.get("https://api.example.com/status")
print response["status"]    # HTTP status kód (Int)
print response["ok"]        # Bool: 200–299
print response["text"]      # Tělo odpovědi (String)
```

### http.post(url, body, headers, timeout)

```lsl
body = {"query": "Hello"}
headers = {
    "Authorization": "Bearer " + token
    "Content-Type": "application/json"
}
response = http.post("https://api.example.com/query", body, headers, 30)
print response["text"]
```

- `body` — String, List, nebo Dictionary (automaticky se serializuje do JSON).
- `headers` — Dictionary s HTTP hlavičkami.
- `timeout` — maximální doba v sekundách.

### http.post_stream(url, body, headers, timeout, on_chunk)

Streamovaný POST pro SSE a dlouhé odpovědi:

```lsl
function handle_chunk(chunk):
    print "Přijato:", len(chunk), "bytů"
end

response = http.post_stream(endpoint, body, headers, 30, handle_chunk)
```

## Modul json

```lsl
load json

# Enkódování
data = {"name": "Ada", "scores": [95, 87, 92]}
encoded = json.encode(data)
print encoded    # '{"name":"Ada","scores":[95,87,92]}'

# Prettifikace
pretty = json.pretty(data)
print pretty     # totéž + newline

# Dekódování
parsed = json.decode('{"key": "value", "list": [1, 2, 3]}')
print parsed["key"]
print parsed["list"][0]
```

## Modul env — secrets management

**Nikdy nehardcodujte API klíče do zdrojového kódu!**

```lsl
load env

# Čtení s výchozí hodnotou
token = env.get("OPENAI_API_KEY", "")
model = env.get("OPENAI_MODEL", "gpt-4o")

# Povinná proměnná
token = env.require("OPENAI_API_KEY")

# Kontrola existence
if not env.has("OPENAI_API_KEY"):
    print "Nastavte OPENAI_API_KEY!"
    exit(1)
end
```

Nastavení proměnné prostředí:

```bash
export OPENAI_API_KEY="sk-..."
./muj_ai_program.lsl
```

Nebo inline:

```bash
OPENAI_API_KEY="sk-..." ./muj_ai_program.lsl
```

## Praktický příklad: AI chatbot

```lsl
load ai
load json
load env

function chat_loop(token, model):
    messages = [
        {"role": "system", "content": "Jsi vtipný asistent. Odpovídej česky."}
    ]

    print "AI Chatbot — napiš 'exit' pro ukončení"
    print "—" * 40

    loop:
        user_input = input "Ty: "
        if user_input == "exit" or user_input == "quit":
            break
        end
        if user_input == "":
            continue
        end

        messages.append({"role": "user", "content": user_input})

        safe:
            response = ai.request(
                "https://api.openai.com/v1/chat/completions",
                token,
                model,
                messages,
                {"max_tokens": 500, "temperature": 0.8}
            )
            reply = ai.content(response)
            if reply != None:
                print "AI:", reply
                messages.append({"role": "assistant", "content": reply})
            else:
                print "AI: [prázdná odpověď]"
            end
        end
        if last_error() != None:
            print "Chyba:", last_error()
        end
    end
end

token = env.require("OPENAI_API_KEY")
model = env.get("OPENAI_MODEL", "gpt-4o")
call chat_loop(token, model)
```

## AI s nástroji (function calling)

```lsl
load ai
load json

# Definice nástrojů
tools = [
    {
        "type": "function"
        "function": {
            "name": "get_weather"
            "description": "Získej aktuální počasí pro město"
            "parameters": {
                "type": "object"
                "properties": {
                    "city": {
                        "type": "string"
                        "description": "Název města"
                    }
                }
                "required": ["city"]
            }
        }
    }
]

# Funkce pro provedení nástroje
function get_weather(city):
    # V reálné aplikaci: HTTP volání na weather API
    return json.encode({
        "city": city
        "temperature": 22
        "condition": "slunečno"
    })
end

# Hlavní konverzace
messages = [
    {"role": "system", "content": "Jsi asistent s přístupem k počasí."}
    {"role": "user", "content": "Jaké je počasí v Praze?"}
]

response = ai.request(
    endpoint, token, model, messages,
    {"tools": tools, "tool_choice": "auto"}
)

# Zpracování tool calls
text = ai.content(response)
if text == None:
    # Získej tool calls z response (dle OpenAI formátu)
    tool_calls = response["choices"][0]["message"]["tool_calls"]
    for call in tool_calls:
        if call["function"]["name"] == "get_weather":
            args = json.decode(call["function"]["arguments"])
            result = get_weather(args["city"])
            messages.append({
                "role": "tool"
                "tool_call_id": call["id"]
                "content": result
            })
        end
    end

    # Druhé volání — AI zpracuje výsledek
    response2 = ai.request(endpoint, token, model, messages, {})
    print ai.content(response2)
    end
else:
    print text
end
```

## Bezpečnostní aspekty

### Ochrana secrets

```lsl
# SPRÁVNĚ — z environment proměnné
token = env.require("API_TOKEN")

# ŠPATNĚ — nikdy hardcodované!
token = "sk-1234abcd"   # NIKDY!
```

### Neočekávané odpovědi

```lsl
try:
    response = ai.request(endpoint, token, model, messages, options)
    text = ai.content(response)
    if text != None:
        print text
    else:
        print "Neočekávaný formát odpovědi"
        print json.pretty(response)   # pro debugging
    end
else:
    print "Selhalo:", last_error()
end
```

### Timeouty a retry

Modul `ai` podporuje:

- **Timeout** — maximální doba na požadavek.
- **Omezený počet retry** pro transport/408/429/5xx.
- **Cancellation callback** — možnost zrušit požadavek před dalším pokusem.

```lsl
options = {
    "max_tokens": 500
    "timeout": 30     # sekundy
}

# ai.request interně zkouší znovu při transient chybách
response = ai.request(endpoint, token, model, messages, options)
```

## Streaming s progress indikátorem

```lsl
load ai

full_text = ""
char_count = 0

function on_char(token):
    if token != None:
        full_text = full_text + token
        char_count = char_count + len(token)

        # Progress každých 50 znaků
        if char_count % 50 == 0:
            print "."  # tečka značí progress (bez newline)
        end
    end
end

print "AI přemýšlí...",
call ai.stream_text(endpoint, token, model, messages, options, on_char)
print ""  # newline
print "Dokončeno:", len(full_text), "znaků"
```

## Kompletní AI klient

Příklad kompletního AI klienta včetně zpracování chyb, více modelů a
ukládání historie najdete v souboru `examples/ai_client.lsl`. Tento
soubor lze přeložit do samostatného ELF:

```bash
./lsl compile examples/ai_client.lsl ai-client
./ai-client
```

## Konfigurační režim a AI

V čistém `lsl config` režimu jsou moduly `ai`, `http` a `env` **zakázány**,
protože konfigurace musí být plně reprodukovatelná a nesmí záviset na síti
nebo environment proměnných. Pro AI aplikace vždy používejte **běžný
programovací režim**.

## Shrnutí API

| Funkce | Modul | Popis |
|---|---|---|
| `ai.request(e, t, m, msgs, opts)` | `ai` | Synchronní AI požadavek |
| `ai.content(response)` | `ai` | Extrakce textu z odpovědi |
| `ai.stream_text(e, t, m, msgs, o, cb)` | `ai` | Streamování textové odpovědi |
| `http.get(url)` | `http` | HTTP GET |
| `http.post(url, body, hdrs, to)` | `http` | HTTP POST |
| `http.post_stream(url, body, hdrs, to, cb)` | `http` | Streamovaný POST |
| `json.encode(value)` | `json` | Serializace do JSON |
| `json.decode(text)` | `json` | Deserializace z JSON |
| `json.pretty(value)` | `json` | Prettifikovaný JSON |
| `env.get(name, default)` | `env` | Čtení proměnné prostředí |
| `env.has(name)` | `env` | Test existence |
| `env.require(name)` | `env` | Povinná proměnná |

## Kam dál

- [11 — Výkon a optimalizace](11-performance-and-optimization.md): optimalizace, tenzory, nativní pluginy
- [12 — Interní architektura compileru](12-compiler-internals.md): jak compiler funguje
