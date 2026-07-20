# AI aplikace v LSL

LSL odděluje orchestrace od numerických kernelů:

- `json` poskytuje `encode`, `decode`, `pretty`;
- `http` poskytuje `get(url)` a `post(url, body, headers, timeout)`; odpověď je Dictionary s `status`, `text`, `ok`;
- `env` poskytuje runtime hranici pro secrets: `get`, `require`, `has`;
- čistý config režim síť a environment staticky zakazuje.

HTTP(S) transport používá systémový `/usr/bin/curl` spuštěný přímým `execve` s odděleným argv; shell se nespouští a hodnoty se neinterpolují do command stringu. stdout zachytává pure-LSL `pipe`/`dup2` runtime.

OpenAI-compatible příklad je v `examples/ai_client.lsl` a čistým compilerem se překládá do samostatného ELF.

Nativní tensor/plugin ABI zatím není podporované; stav a podmínky budoucí implementace jsou v `docs/native-plugins.md`. Tato mezera není vydávána za hotovou.
