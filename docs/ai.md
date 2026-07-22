# AI aplikace v LSL

LSL odděluje orchestrace od numerických kernelů:

- `ai` poskytuje OpenAI-compatible `request`, validaci response a `content`;
- `json` poskytuje `encode`, `decode`, `pretty`;
- `http` poskytuje `get(url)` a `post(url, body, headers, timeout)`; odpověď je Dictionary s `status`, `text`, `ok`;
- `env` poskytuje runtime hranici pro secrets: `get`, `require`, `has`;
- čistý config režim síť a environment staticky zakazuje.

HTTP(S) transport používá systémový `/usr/bin/curl` spuštěný přímým `execve` s odděleným argv; shell se nespouští a hodnoty se neinterpolují do command stringu. stdout zachytává pure-LSL `pipe`/`dup2` runtime.

`ai.request(endpoint, token, model, messages, options)` podporuje timeout, omezený počet retry pro transport/408/429/5xx, cancellation callback před každým pokusem a strukturované `AIProviderError`/`AICancelled` výjimky. Response je validované JSON Dictionary; `ai.content(response)` bezpečně získá první textovou odpověď. `ai.stream` a `ai.stream_text` validují OpenAI SSE `data:` events, `[DONE]`, provider errors a předávají content chunks do callbacku s cancellation mezi eventy. Curl transport zatím bufferuje HTTP response, takže callbacky začnou až po dokončení přenosu; parser/API jsou streamové, síťová hranice ještě ne.

OpenAI-compatible příklad je v `examples/ai_client.lsl` a čistým compilerem se překládá do samostatného ELF.

Nativní tensor/plugin ABI zatím není podporované; stav a podmínky budoucí implementace jsou v `docs/native-plugins.md`. Tato mezera není vydávána za hotovou.
