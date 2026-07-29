# AI aplikace v LSL

LSL odděluje orchestrace od numerických kernelů:

- `ai` poskytuje OpenAI-compatible `request`, validaci response a `content`;
- `json` poskytuje `encode`, `decode`, `pretty`;
- `http` poskytuje `get(url)` a `post(url, body, headers, timeout)`; odpověď je Dictionary s `status`, `text`, `ok`;
- `env` poskytuje runtime hranici pro secrets: `get`, `require`, `has`;
- čistý config režim síť a environment staticky zakazuje.

HTTP(S) transport používá systémový `/usr/bin/curl` spuštěný přímým `execve` s odděleným argv; shell se nespouští a hodnoty se neinterpolují do command stringu. stdout zachytává pure-LSL `pipe`/`dup2` runtime.

`ai.request(endpoint, token, model, messages, options)` podporuje timeout, omezený počet retry pro transport/408/429/5xx, cancellation callback před každým pokusem a strukturované `AIProviderError`/`AICancelled` výjimky. Response je validované JSON Dictionary; `ai.content(response)` bezpečně získá první textovou odpověď. `ai.stream` a `ai.stream_text` validují OpenAI SSE `data:` events, `[DONE]`, provider errors a předávají content chunks do callbacku s cancellation mezi eventy. `http.post_stream` používá curl `--no-buffer` a `capture_stream`, takže volitelný `transport_chunk` callback dostává raw síťové chunks už během přenosu; finální SSE content parser současně zachovává deterministickou kontrolu celé response.

OpenAI-compatible příklad je v `examples/ai_client.lsl` a čistým compilerem se překládá do samostatného ELF.

Pure-LSL Tensor s volitelným CUDA workerem a omezený self-contained ET_DYN
Int64 kernel ABI jsou podporované; obecné libc/shared-object relocations a
přímý in-process GPU driver ABI nikoli. Přesný scope je v
`docs/native-plugins.md` a `docs/cuda.md`.
