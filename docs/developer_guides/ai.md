# AI knihovna 1.0.0 — chat a průběžné SSE

Tento manuál popisuje samostatně aktualizovatelný balíček **`aikit` 1.0.0**
pro LSL 0.8.9 nebo novější. Má stejné rozhraní jako vestavěný modul `ai`.
`ai.stream()` nyní předává části textu **už během HTTP přenosu**.

## Instalace bez aktualizace LSL

```bash
lsl install aikit       # první instalace
lsl update aikit        # další aktualizace pouze této knihovny
lsl origin aikit        # původ a SHA-256 nainstalovaného zdroje
```

Ve skriptu nahraďte `load ai` tímto řádkem:

```lsl
load aikit as ai
print ai.version
print ai.help()
```

Zbytek volání `ai.request`, `ai.stream` apod. může zůstat pod jménem `ai`.
LSL 0.8.9 upřednostňuje vestavěné knihovny před uživatelskými, proto samotné
`load ai` **nenačte aktualizovaný balíček z registru**. Název `aikit` tento
konflikt řeší bez změn kompilátoru nebo systémové instalace.

Importy jsou statické: skript spuštěný přes `lsl soubor.lsl` použije nový
zdroj při příštím spuštění; samostatné ELF programy znovu přeložte.
`lsl man ai` zůstává kopií dodanou s instalací LSL. Aktuální krátká offline
nápověda cestuje s balíčkem (`print ai.help()`); úplný manuál je tato stránka.

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
print ai.content(response)
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

count = ai.stream(
    "https://api.lux-ai.cz/v1/chat/completions",
    env.require("LUX_AI_API"),
    env.get("LUX_AI_MODEL", "flash"),
    [{"role": "user", "content": "Napiš krátký příběh."}],
    {"max_tokens": 8000, "temperature": 0.7, "timeout": 120},
    receive
)
print ""
reply = "".join(parts)
print "Přijatých částí:", count
```

`receive(text)` dostává neprázdné řetězce z `choices[0].delta.content`.
Jeden callback nemusí odpovídat jednomu tokenu modelu. Metadata, prázdné
`choices`, `null` a prázdný `content` se nevypisují. `stream` vrací **počet
textových callbacků**, nikoli Dictionary nebo hotovou odpověď. Nepředávejte
jeho návratovou hodnotu do `ai.content`; text sestavte z přijatých částí.

`print text` přidává nový řádek. `tui.Terminal().emit` a `flush` umožňují
plynulý výpis. Bez `enter()` nepřepínají režim terminálu ani obrazovku.

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
            count = ai.stream(
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

## Rozhraní

| Volání | Výsledek |
|---|---|
| `request(endpoint, token, model, messages, options)` | Dekódovaný JSON providera jako Dictionary; při HTTP chybě výjimka. |
| `stream(endpoint, token, model, messages, options, on_event)` | Průběžně volá `on_event(String)` a vrátí počet volání. |
| `stream_text(text, on_event, cancel=None)` | Parsuje již načtený SSE text; stejný callback a počet volání, bez sítě. |
| `content(response)` | `choices[0].message.content`: String nebo `None` pro JSON `null`; vadná struktura vyvolá chybu. |
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
  chyba providera, vadná struktura nebo nedokončený stream.
- `AICancelled`: zrušení přes callback.
- Chyba callbacku v živém streamu ukončí přenos, uvolní kontext a předá
  se jako `AIProviderError` s původním textem. `stream_text` předá původní
  chybu callbacku přímo. Oba případy lze zachytit přes `try`/`else`.

Dekodéry jsou oddělené podle volání. Vnořené streamování z callbacku i
souběžná volání z více vláken nesdílejí parser nebo textový callback.

## Další parametry a nástroje

`tools`, `tool_choice`, `top_p`, `stop` a další neuvedené parametry nejsou
součástí `options`. Použijte `http.post` s vlastním JSON tělem a následně
`ai.decode_response`. Kompletní příklad nástrojů je v kapitole
[AI aplikace](10-ai-applications.md).

Přístup k síti a prostředí patří do běžného programovacího režimu;
`lsl config` tyto operace nepovoluje.
