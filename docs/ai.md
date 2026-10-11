# AI aplikace v LSL

Samostatná AI knihovna `aikit` 1.1.0 funguje s LSL 0.8.9 a novějšími.
Instalace: `lsl install aikit`, další aktualizace: `lsl update aikit`.
Ve skriptu použijte `load aikit as ai`; vestavěný název `ai` má v LSL 0.8.9
přednost před uživatelskými balíčky, proto se tímto importem vybírá nová kopie.

`ai.request` vrací JSON Dictionary. `ai.stream` předává textové části
callbacku už během HTTP přenosu a vrací Dictionary `{events, tool_calls}`.
Podporuje timeout, cancel, surový transportní callback a omezené retry
před prvním textem. `temperature`, `max_tokens`, `tools` a `tool_choice`
se posílají i ve streamovací variantě. Parser zpracovává rozdělené
UTF-8/JSON, LF/CRLF/CR, BOM a víceřádkové SSE. Neúplný živý stream bez
`[DONE]` vyvolá `AIProviderError`.

Nástroje (function calling) jsou nativní: `ai.tool_calls(response)` přečte
volání `{id, name, arguments}`, `ai.tool_message(id, name, result)` sestaví
odpověď role `tool`. Ve streamu se tool cally skládají po částech
(`delta.tool_calls`) a hotové volání dostane `on_tool_call`.

Podrobné API, limity, chování při chybách a celý chatbot:
[manuál AI knihovny](https://git.lux-ai.cz/LuxAI/LSL-Web/src/branch/main/public/ai.md).
Krátká offline nápověda je přímo v balíčku: `printl "{ai.help()}"`.

Knihovna používá `http`, `json` a `time`; token předává curlu přes konfiguraci
na stdin, bez shellu a bez tajných údajů v argumentech procesu.
AI knihovnu lze aktualizovat bez vydání nové verze LSL. Samostatně přeložené
programy je po změně knihovny nutné přeložit znovu.
