# 10. AI aplikace

Tato kapitola vysvětluje, jak v LSL pracovat s AI modely přes
OpenAI-compatible API — od jednoduchého dotazu přes streaming až po
function calling a správu secrets.

Tato kapitola používá AI knihovnu `aikit` 1.0.0 pro LSL 0.8.9+.
Nainstalujte ji přes `lsl install aikit`, později aktualizujte přes
`lsl update aikit`. Import `load aikit as ai` zachová jméno `ai` v příkladech.
Podrobnosti a hotový streamovací chatbot: [manuál AI](ai.md).

## Co k tomu potřebujete

- **API klíč** k OpenAI nebo kompatibilní službě (např. OpenAI,
  Groq, lokální Ollama).
- **Balíček `aikit`** a vestavěné moduly `json`, `http`, `env`.
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
| `http` | HTTP(S) transport přes validovaný curl config na stdin |
| `env` | Runtime hranice pro secrets (API klíče, tokeny) |

## Rychlý start: jednoduchý AI dotaz

```lsl
load aikit as ai
load json
load env

# Načtení API klíče (nikdy ne hardcode!)
token = env.require("OPENAI_API_KEY")

# Příprava messages
messages = [
    {"role": "system", "content": "Jsi užitečný asistent."},
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
        "max_tokens": 500,         # maximální délka odpovědi
        "temperature": 0.7,        # kreativita podle pravidel providera
        "timeout": 30,             # časový limit transportu v sekundách
        "retries": 2               # opakování přechodných chyb
    }
)
```

`options` přijímá pouze `temperature`, `max_tokens`, `timeout`, `retries`,
`cancel` a `transport_chunk`. Neznámé klíče vyvolají `AIProviderError`.
`temperature` a `max_tokens` se posílají providerovi; ostatní řídí LSL.
Pro další parametry API použijte `http.post` s vlastním tělem požadavku.

### ai.content(response)

Extrahuje `choices[0].message.content`. Hodnotu `None` vrátí, pokud je
obsah JSON `null`; při chybějící struktuře vyvolá `AIProviderError`:

```lsl
text = ai.content(response)
if text == None:
    print "Žádná textová odpověď"
else:
    print text
end
```

### ai.stream — SSE odpověď

```lsl
parts = []

function on_token(chunk):
    parts.append(chunk)
    print chunk  # print vypisuje každý kus na samostatný řádek
end

call ai.stream(
    "https://api.openai.com/v1/chat/completions",
    token,
    "gpt-4o",
    messages,
    {"timeout": 30},
    on_token
)

print "Celá odpověď:", "".join(parts)
```

`ai.stream` posílá `stream: True` a předává textové callbacky už během
HTTP přenosu. Posílá také `temperature` a `max_tokens`; `timeout`, `cancel`
a `retries` řídí přenos. Retry se provádí pouze před prvním textovým
callbackem, aby se odpověď nezdvojovala. Volitelný `transport_chunk` dostává
surové části těla, které mohou končit uprostřed JSON nebo UTF-8 znaku.
Živý stream musí skončit značkou `[DONE]`, jinak vyvolá chybu.

`ai.stream_text(text, on_event, cancel)` je samostatný parser již načteného
SSE textu; neposílá HTTP požadavek. Obě varianty rozpoznávají `data:`,
`[DONE]` a chyby providera.

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
    # - AIProviderError: neplatná JSON odpověď nebo parametry
end
```

Podrobnější diagnostika přes `http`:

```lsl
load http

response = http.post(endpoint, {"model": model, "messages": messages},
                     {"Authorization": "Bearer " + token}, 30)
if not response["ok"]:
    print "HTTP chyba:", response["status"]
    print "Tělo:", response["text"]
else:
    data = ai.decode_response(response)
    print ai.content(data)
end
```

`status`, `ok` a `text` patří do odpovědi `http`. `ai.request` už vrací
samotný dekódovaný JSON providera a HTTP chyby převádí na `AIProviderError`.

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
    "Authorization": "Bearer " + token,
    "Content-Type": "application/json"
}
response = http.post("https://api.example.com/query", body, headers, 30)
print response["text"]
```

- `body` — String, List, nebo Dictionary (automaticky se serializuje do JSON).
- `headers` — Dictionary s HTTP hlavičkami.
- `timeout` — maximální doba v sekundách.

Transport předává URL, tělo i autorizační hlavičky curlu přes stdin, takže
secrets nejsou v process argv. Vzdálený endpoint musí být HTTPS; HTTP je
povolen pouze pro lokální loopback služby.

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

Od LSL 0.8.9 načte `load env` automaticky `.env` vedle vstupního skriptu
(u přeloženého programu vedle binárky). Exportované proměnné mají přednost.
Podrobnosti: [knihovna env](env.md).

Nastavení proměnné prostředí:

```bash
export OPENAI_API_KEY="sk-..."
lsl muj_ai_program.lsl
```

Nebo inline:

```bash
OPENAI_API_KEY="sk-..." lsl muj_ai_program.lsl
```

## Praktický příklad: AI chatbot

```lsl
load aikit as ai
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

        try:
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
        else:
            print "Chyba:", last_error()
        end
    end
end

token = env.require("OPENAI_API_KEY")
model = env.get("OPENAI_MODEL", "gpt-4o")
call chat_loop(token, model)
```

## AI s nástroji (function calling)

`ai.request` nepřijímá `tools` ani `tool_choice`. Pro službu, která tyto
parametry podporuje, sestavte JSON přes `http.post`. Následující příklad
obsahuje demonstrační údaje o počasí, nikoli skutečnou předpověď.

```lsl
load aikit as ai
load http
load json
load env

endpoint = env.require("AI_ENDPOINT")
token = env.require("OPENAI_API_KEY")
model = env.get("OPENAI_MODEL", "gpt-4o")
headers = {"Authorization": "Bearer " + token, "Content-Type": "application/json"}

tools = [
    {
        "type": "function",
        "function": {
            "name": "get_weather",
            "description": "Získej demonstrační počasí pro město",
            "parameters": {
                "type": "object",
                "properties": {
                    "city": {
                        "type": "string",
                        "description": "Název města"
                    }
                },
                "required": ["city"]
            }
        }
    }
]

function get_weather(city):
    return json.encode({
        "city": city,
        "temperature": 22,
        "condition": "slunečno"
    })
end

messages = [
    {"role": "system", "content": "Jsi asistent s přístupem k demonstračnímu počasí."},
    {"role": "user", "content": "Jaké je počasí v Praze?"}
]
payload = {"model": model, "messages": messages, "tools": tools, "tool_choice": "auto"}
response = ai.decode_response(http.post(endpoint, payload, headers, 30))
message = response["choices"][0]["message"]

if "tool_calls" in message and len(message["tool_calls"]) > 0:
    # Do historie patří i zpráva asistenta, která požaduje použití nástroje.
    messages.append(message)
    for tool_call in message["tool_calls"]:
        if tool_call["function"]["name"] != "get_weather":
            Error(ToolError: "Neznámý nástroj")
        end
        args = json.decode(tool_call["function"]["arguments"])
        result = get_weather(args["city"])
        messages.append({
            "role": "tool",
            "tool_call_id": tool_call["id"],
            "content": result
        })
    end
    response2 = ai.request(endpoint, token, model, messages, {})
    print ai.content(response2)
else:
    print ai.content(response)
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
    "max_tokens": 500,
    "timeout": 30,    # sekundy
    "retries": 2      # výchozí hodnota 0 znamená bez opakování
}

# Při retries > 0 ai.request opakuje přechodné chyby
response = ai.request(endpoint, token, model, messages, options)
```

## Sledování SSE odpovědi

```lsl
load aikit as ai

chunks = []
progress = {"characters": 0}

function on_char(chunk):
    if chunk != None:
        chunks.append(chunk)
        progress["characters"] += len(chunk)
        print "Zpracováno znaků:", progress["characters"]
    end
end

print "AI přemýšlí..."
call ai.stream(endpoint, token, model, messages, options, on_char)
full_text = "".join(chunks)
print "Dokončeno:", len(full_text), "znaků"
```

Textové části se zpracovávají průběžně během příjmu odpovědi. Pro surový
průběh přenosu slouží `transport_chunk`; jeho vstup je SSE, nikoli čistý text.
Příklad chatbota výše uložte například jako `ai_client.lsl` a přeložte:

```bash
lsl compile ai_client.lsl ai-client
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
| `ai.stream(e, t, m, msgs, o, cb)` | `ai` | Požadavek se SSE odpovědí |
| `ai.stream_text(text, cb, cancel)` | `ai` | Parsování již načteného SSE |
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
