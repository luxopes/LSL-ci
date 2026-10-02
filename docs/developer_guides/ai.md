# AI knihovna 1.1.0 — chat, nástroje a průběžné SSE

Tento manuál popisuje samostatně aktualizovatelný balíček **`aikit` 1.1.0**
pro LSL 0.8.9 nebo novější. Má stejné rozhraní jako vestavěný modul `ai`
a nově podporuje **nativní volání nástrojů** (function calling), **živé
streamování tool callů** a volitelnou spolehlivost streamu.

## Instalace bez aktualizace LSL

```bash
lsl install aikit       # první instalace
lsl update aikit        # další aktualizace pouze této knihovny
lsl origin aikit        # původ a SHA-256 nainstalovaného zdroje
```

Ve skriptu nahraďte `load ai` tímto řádkem:

```lsl
load aikit as ai
printl "Verze knihovny: {ai.version}"
```

Zbytek volání `ai.request`, `ai.stream` apod. může zůstat pod jménem `ai`.
LSL 0.8.9 upřednostňuje vestavěné knihovny před uživatelskými, proto samotné
`load ai` **nenačte aktualizovaný balíček z registru**. Název `aikit` tento
konflikt řeší bez změn kompilátoru nebo systémové instalace.

Importy jsou statické: skript spuštěný přes `lsl soubor.lsl` použije nový
zdroj při příštím spuštění; samostatné ELF programy znovu přeložte.
`lsl man ai` zůstává kopií dodanou s instalací LSL. Aktuální krátká offline
nápověda cestuje s balíčkem (`printl "{ai.help()}"`); úplný manuál je tato stránka.

## Základní požadavek

```lsl
load aikit as ai
load env

token = env.require("LUX_AI_API")
model = env.get("LUX_AI_MODEL", "flash")
messages = [{"role": "user", "content": "Ahoj, představ se jednou větou."}]
response = ai.request(
    "https://api.lux-ai.cz/v1/chat/completions",
    token, model, messages,
    {"max_tokens": 500, "temperature": 0.7, "timeout": 60}
)
printl "Odpověď: {ai.content(response)}"
```

`load env` v LSL 0.8.9 načítá `.env` vedle vstupního skriptu; proměnné
prostředí mají přednost. Knihovna samotná token nikam neukládá. Transport
používá `/usr/bin/curl` s konfigurací na stdin, takže hlavička Authorization
není v argumentech procesu. HTTPS je povinné mimo číselný loopback.

## Skutečné průběžné streamování

```lsl
load aikit as ai
load env
load tui

parts = []
output = tui.Terminal()

function receive(text):
    parts.append(text)
    call output.emit(text)
    call output.flush()
end

result = ai.stream(
    "https://api.lux-ai.cz/v1/chat/completions",
    env.require("LUX_AI_API"),
    env.get("LUX_AI_MODEL", "flash"),
    [{"role": "user", "content": "Napiš krátký příběh."}],
    {"max_tokens": 8000, "temperature": 0.7, "timeout": 120},
    receive
)
print ""
printl "Přijatých částí: {result[\"events\"]}, tool callů: {len(result[\"tool_calls\"])}"
```

`receive(text)` dostává neprázdné řetězce z `choices[0].delta.content`.
Jeden callback nemusí odpovídat jednomu tokenu modelu. Metadata, prázdné
`choices`, `null` a prázdný `content` se nevypisují. `stream` vrací Dictionary
`{"events": počet textových callbacků, "tool_calls": seznam volání}`,
nikoli hotovou odpověď. Nepředávejte ho do `ai.content`; text sestavte
z přijatých částí.

`print text` přidává nový řádek; pro plynulý výpis bez konců řádků použijte
`tui.Terminal().emit` a `flush` jako výše. `printl "..."` interpoluje výrazy
ve složených závorkách a je vhodné pro celé řádky — viz předchozí příklad.

## Celý chatbot s historií a obsluhou chyb

```lsl
load aikit as ai
load env
load tui

parts = []
output = tui.Terminal()

function receive(text):
    parts.append(text)
    call output.emit(text)
    call output.flush()
end

function chat(token, model):
    messages = [
        {"role": "system", "content": "You are a friendly AI assistant LuxAI Flash."}
    ]
    print "LuxAI chatbot — napiš 'exit' pro ukončení"
    loop:
        user_input = input "Ty: "
        if user_input == "quit" or user_input == "exit":
            break
        end
        if user_input == "":
            continue
        end
        messages.append({"role": "user", "content": user_input})
        parts.clear()
        call output.emit("AI: ")
        call output.flush()
        try:
            result = ai.stream(
                "https://api.lux-ai.cz/v1/chat/completions",
                token, model, messages,
                {"max_tokens": 8000, "temperature": 0.7, "timeout": 120},
                receive
            )
            print ""
            messages.append({"role": "assistant", "content": "".join(parts)})
        else:
            print ""
            printl "Chyba: {last_error()}"
            # Neúspěšný dotaz a částečnou odpověď nedáváme do historie.
            call messages.pop()
        end
    end
end

call chat(env.require("LUX_AI_API"), env.get("LUX_AI_MODEL", "flash"))
```

Již vypsaný text nelze při chybě vzít zpět. Do historie jej ukládejte až po
úspěšném návratu `stream`, jako v příkladu výše.

## Volání nástrojů (function calling)

Nástroje se popisují stejným schématem jako u OpenAI. Definici předáte
v `options["tools"]` a model buď odpoví textem, nebo vrátí volání nástroje.
Následující příklad modelu vnutí volání přes `tool_choice: "required"`,
vykoná ho lokálně a výsledek vrátí zpět zprávou role `tool`:

```lsl
load aikit as ai
load json
load env

endpoint = "https://api.lux-ai.cz/v1/chat/completions"
token = env.require("LUX_AI_API")
model = env.get("LUX_AI_MODEL", "flash")

tools = [
    {"type": "function", "function": {
        "name": "get_weather",
        "description": "Aktuální počasí pro město.",
        "parameters": {
            "type": "object",
            "properties": {"city": {"type": "string"}},
            "required": ["city"]
        }
    }}
]

function get_weather(city):
    # Zde voláte skutečnou službu; v příkladu vracíme ukázková data.
    return json.encode({"city": city, "temperature": 22, "condition": "slunečno"})
end

messages = [{"role": "user", "content": "Jaké je počasí v Praze?"}]
response = ai.request(endpoint, token, model, messages,
                      {"tools": tools, "tool_choice": "required", "timeout": 120})
calls = ai.tool_calls(response)

if len(calls) > 0:
    assistant_calls = []
    for call in calls:
        assistant_calls.append({"id": call["id"], "type": "function",
                                "function": {"name": call["name"],
                                             "arguments": call["arguments"]}})
    end
    messages.append({"role": "assistant", "content": None, "tool_calls": assistant_calls})
    for call in calls:
        args = json.decode(call["arguments"])
        messages.append(ai.tool_message(call["id"], call["name"],
                                        get_weather(args["city"])))
    end
    follow_up = ai.request(endpoint, token, model, messages,
                           {"tools": tools, "timeout": 120})
    printl "Odpověď: {ai.content(follow_up)}"
else:
    printl "Odpověď: {ai.content(response)}"
end
```

`ai.tool_calls(response)` vrací List `{id, name, arguments}`. `arguments` je
String s JSON objektem; parametry si dekódujete přes `json.decode`.
`ai.tool_message(id, name, result)` sestaví zprávu role `tool` — ta patří
v historii vždy za asistentovu zprávu s `tool_calls`. Pak požadavek zopakujte.

Model může volat i více nástrojů najednou: `tool_calls` pak obsahuje více
položek a každé volání dostane vlastní `tool_message`. Při `tool_choice:
"required"` provider tool call garantuje; u `auto` se připravte i na čistě
textovou odpověď (viz větev `else`).

## Živé streamování tool callů

Ve streamovacím režimu přicházejí tool cally po částech (`delta.tool_calls`)
a knihovna je skládá dohromady. Po dokončení celého volání zavolá
`on_tool_call` a hotové volání přidá do `result["tool_calls"]`:

```lsl
load aikit as ai
load json
load env

tools = [
    {"type": "function", "function": {
        "name": "get_weather",
        "description": "Aktuální počasí pro město.",
        "parameters": {
            "type": "object",
            "properties": {"city": {"type": "string"}},
            "required": ["city"]
        }
    }}
]

hook_calls = []
parts = []

function on_text(text):
    parts.append(text)
end

function on_tool(call):
    hook_calls.append(call)
    printl "Nástroj {call[\"name\"]} volán s {call[\"arguments\"]}"
end

result = ai.stream(
    "https://api.lux-ai.cz/v1/chat/completions",
    env.require("LUX_AI_API"),
    env.get("LUX_AI_MODEL", "flash"),
    [{"role": "user", "content": "Jaké je počasí v Brně?"}],
    {"tools": tools, "tool_choice": "required", "on_tool_call": on_tool, "timeout": 120},
    on_text
)
check(len(hook_calls) == len(result["tool_calls"]), "hook a výsledek se liší")
printl "Dokončeno: {len(result[\"tool_calls\"])} volání, {result[\"events\"]} textových částí"
```

Callback dostává úplné `{id, name, arguments}`; argumenty jsou v té chvíli
celé (složené ze všech chunků). Textové části — pokud model vedle volání
nástroje píše i text — chodí do `on_text` jako obvykle. Volání nástroje
bez `id` nebo `name` vyvolá `AIProviderError` jako neúplný stream.

## Rozhraní

| Volání | Výsledek |
|---|---|
| `request(endpoint, token, model, messages, options)` | Dekódovaný JSON providera jako Dictionary; při HTTP chybě výjimka. |
| `stream(endpoint, token, model, messages, options, on_event)` | Průběžně volá `on_event(String)`; vrátí `{"events": Int, "tool_calls": List}`. |
| `stream_text(text, on_event, cancel=None)` | Parsuje již načtený SSE text; stejný callback, vrací počet volání, bez sítě. |
| `content(response)` | `choices[0].message.content`: String nebo `None` pro JSON `null`; vadná struktura vyvolá chybu. |
| `tool_calls(response)` | `message.tool_calls` jako List `{id, name, arguments}`; bez volání `[]`. |
| `tool_message(id, name, result)` | Zpráva role `tool` pro navazující požadavek. |
| `decode_response(response)` | Zpracuje Dictionary z `http` (`status`, `ok`, `text`) a vrátí JSON Dictionary nebo vyvolá chybu. |
| `help()` / `version` | Krátká nápověda / verze AI knihovny, nezávislá na verzi LSL. |

`messages` je List zpráv, nejvýše 4096 položek. `options` je Dictionary.
Chybějící možnosti použijí výchozí hodnoty; neznámé klíče se odmítají.

| Možnost | Hodnota / výchozí stav | Chování |
|---|---|---|
| `temperature` | Int nebo Float 0–2; nepřítomná se neposílá | Posílá se providerovi v `request` i `stream`. |
| `max_tokens` | Kladný Int; nepřítomný se neposílá | Posílá se providerovi v obou variantách. |
| `timeout` | Int 1–3600, výchozí 60 sekund | Limit jednoho HTTP pokusu včetně přenosu. |
| `retries` | Int 0–10, výchozí 0 | Počet dalších pokusů pro transportní chybu nebo HTTP 408/429/5xx. |
| `cancel` | Function bez argumentů nebo `None` | Pravdivý výsledek vyvolá `AICancelled`. |
| `transport_chunk` | Function s jedním argumentem nebo `None` | Dostává surové části HTTP těla; nezastupuje textový callback. |
| `tools` | List 1–128 definic `{type: "function", function: {name, description?, parameters?}}` | Posílá se providerovi v `request` i `stream`; název 1–256 znaků. |
| `tool_choice` | `auto` (výchozí), `none`, `required` nebo `{type: "function", function: {name}}` | Řídí, zda a který nástroj model použije. |
| `on_tool_call` | Function s jedním argumentem nebo `None` | Po dokončení streamovaného volání nástroje dostává `{id, name, arguments}`. |
| `stream_reliability` | `live` (výchozí) nebo `transactional`; posílá se jen při streamu | Úroveň spolehlivosti, kterou má provider použít; služba, která ji nezná, volbu odmítne. |

Ve streamu se retry provede pouze **před prvním textovým callbackem**.
Po vypsání části odpovědi se žádný nový pokus automaticky nespouští.
Vadné SSE/JSON, chyby událostí, chybějící `[DONE]`, chyby callbacků ani
zrušení se neopakují. Prodleva před dalším pokusem roste po 0,1 s, nejvýše
na 2 s. `transport_chunk` může při retry vidět tělo každého pokusu.

`cancel()` se kontroluje před pokusem, během příjmu SSE a mezi událostmi.
Při čekání na další síťová data se callback neprovádí; čekání omezuje
`timeout`. U nestreamovaného `request` se kontroluje před a po HTTP pokusu.
Callback, který změní stav zrušení, má být krátký a nemá blokovat.

`transport_chunk` dostává String obsahující surové bajty, které mohou
končit uprostřed JSON nebo vícebajtového UTF-8 znaku. Pro běžný chatbot
používejte textový `on_event`; ten dostává celé dekódované části obsahu.

## SSE a chybové stavy

Parser podporuje LF, CRLF i CR, BOM na začátku, komentáře, více `data:`
řádků jedné události a libovolné hranice síťových bloků včetně UTF-8.
Živý `stream` očekává `[DONE]`; předčasný konec hlásí jako neúplnou odpověď.
`stream_text` pro kompatibilitu dovoluje i konečný SSE úryvek bez `[DONE]`.
Po `[DONE]` se další události ignorují.

Jednotlivý SSE řádek i složená událost mají limit 1 MiB. Současný HTTP
transport uchovává také celé tělo a omezuje ho na 16 MiB; průběžný callback
proto neznamená konstantní spotřebu paměti.

- `AIProviderError`: neplatné parametry, HTTP chyba, vadný JSON/SSE,
  chyba providera, vadná struktura, neúplný stream nebo neúplný tool call.
- `AICancelled`: zrušení přes callback.
- Chyba callbacku v živém streamu ukončí přenos, uvolní kontext a předá
  se jako `AIProviderError` s původním textem. `stream_text` předá původní
  chybu callbacku přímo. Oba případy lze zachytit přes `try`/`else`.

Dekodéry jsou oddělené podle volání. Vnořené streamování z callbacku i
souběžná volání z více vláken nesdílejí parser nebo textový callback.

## Další parametry

`top_p`, `stop`, `seed` a další parametry, které `options` nezná, pošlete
přes `http.post` s vlastním JSON tělem a odpověď zpracujte přes
`ai.decode_response`. U nástrojů to obvykle není potřeba — `tools` a
`tool_choice` pokrývají běžný function calling.

Přístup k síti a prostředí patří do běžného programovacího režimu;
`lsl config` tyto operace nepovoluje.
