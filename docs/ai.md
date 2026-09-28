# AI aplikace v LSL

Samostatná AI knihovna `aikit` 1.0.0 funguje s LSL 0.8.9 a novějšími.
Instalace: `lsl install aikit`, další aktualizace: `lsl update aikit`.
Ve skriptu použijte `load aikit as ai`; vestavěný název `ai` má v LSL 0.8.9
přednost před uživatelskými balíčky, proto se tímto importem vybírá nová kopie.

`ai.request` vrací JSON Dictionary. `ai.stream` předává textové části
callbacku už během HTTP přenosu a vrací jejich počet. Podporuje timeout,
cancel, surový transportní callback a omezené retry před prvním textem.
`temperature` a `max_tokens` se posílají i ve streamovací variantě.
Parser zpracovává rozdělené UTF-8/JSON, LF/CRLF/CR, BOM a víceřádkové SSE.
Neúplný živý stream bez `[DONE]` vyvolá `AIProviderError`.

Podrobné API, limity, chování při chybách a celý chatbot:
[manuál AI knihovny](developer_guides/ai.md).
Krátká offline nápověda je přímo v balíčku: `print ai.help()`.

Knihovna používá `http`, `json` a `time`; token předává curlu přes konfiguraci
na stdin, bez shellu a bez tajných údajů v argumentech procesu.
AI knihovnu lze aktualizovat bez vydání nové verze LSL. Samostatně přeložené
programy je po změně knihovny nutné přeložit znovu.
