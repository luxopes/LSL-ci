# AI 1.0.0: chat a průběžné SSE; samostatný balíček: lsl install aikit.
# Použití balíčku v LSL 0.8.9: load aikit as ai; dokumentace: https://lsl.lux-ai.cz/#ai

load http
load json
load time

version = "1.0.0"
_MAX_EVENT_BYTES = 1048576
_contexts = {}
_context_lock = IntArray()
_context_lock.append(0)

function help():
    return "AI " + version + "\nload aikit as ai\n\nrequest(endpoint, token, model, messages, options) -> Dictionary\ncontent(response) -> String | None\nstream(endpoint, token, model, messages, options, on_event) -> Int\nstream_text(text, on_event, cancel=None) -> Int\n\non_event(text) dostava neprázdné části odpovědi už během HTTP přenosu.\nVýsledek stream je počet callbacků, nikoli celá odpověď.\nOptions: temperature (0..2), max_tokens (>0), timeout (1..3600 s, výchozí 60),\nretries (0..10, výchozí 0), cancel (Function | None), transport_chunk (Function | None).\nPo prvním textovém callbacku se požadavek neopakuje. Živý stream vyžaduje [DONE].\nPro výpis bez newline použijte tui.Terminal().emit(text) a flush().\nAktualizace pouze knihovny: lsl update aikit\nÚplný manuál a chatbot: https://lsl.lux-ai.cz/#ai"
end

function _byte_length(text):
    unsafe:
        return __lsl_text_byte_length(String(text))
    end
end

function _checked_callback(callback, name, optional):
    if optional and callback == None:
        return
    end
    if type(callback) != "Function":
        Error(AIProviderError: name + " must be a Function")
    end
end

function checked_request(endpoint, token, model, messages, options):
    if type(endpoint) != "String" or len(endpoint) == 0 or _byte_length(endpoint) > 8192:
        Error(AIProviderError: "AI endpoint must be a non-empty URL String")
    elif type(token) != "String" or _byte_length(token) > 65536 or chr(0) in token:
        Error(AIProviderError: "AI token is invalid or too long")
    elif type(model) != "String" or len(model) == 0 or len(model) > 256:
        Error(AIProviderError: "AI model name is invalid")
    elif type(messages) != "List" or len(messages) > 4096:
        Error(AIProviderError: "AI messages must be a bounded List")
    elif type(options) != "Dictionary" or len(options) > 32:
        Error(AIProviderError: "AI options must be a bounded Dictionary")
    end
    for key in options:
        if type(key) != "String" or key not in ["temperature", "max_tokens", "timeout", "retries", "cancel", "transport_chunk"]:
            Error(AIProviderError: "unknown AI request option: " + String(key))
        end
    end
    for bounds in [["timeout", 1, 3600], ["retries", 0, 10], ["max_tokens", 1, 9223372036854775807]]:
        name = bounds[0]
        if name in options:
            value = options[name]
            if type(value) != "Int" or value < bounds[1] or value > bounds[2]:
                Error(AIProviderError: name + " must be an Int between " + String(bounds[1]) + " and " + String(bounds[2]))
            end
        end
    end
    if "temperature" in options:
        value = options["temperature"]
        if (type(value) != "Int" and type(value) != "Float") or value != value or value < 0 or value > 2:
            Error(AIProviderError: "temperature must be a finite number between 0 and 2")
        end
    end
    call _checked_callback(options.get("cancel", None), "cancel", True)
    call _checked_callback(options.get("transport_chunk", None), "transport_chunk", True)
end

function _cancelled(cancel):
    if cancel != None and cancel():
        Error(AICancelled: "request cancelled")
    end
end

function bounded_provider_text(value):
    text = String(value)
    if len(text) > 4096:
        return text[0:4096]
    end
    return text
end

function provider_message(data, fallback):
    if type(data) == "Dictionary" and "error" in data:
        error = data["error"]
        if type(error) == "Dictionary" and "message" in error:
            return bounded_provider_text(error["message"])
        end
        return bounded_provider_text(error)
    end
    return bounded_provider_text(fallback)
end

function decode_response(response):
    status = response["status"]
    text = response["text"]
    if not response["ok"]:
        message = "HTTP " + String(status)
        if len(text) > 0:
            try:
                data = json.decode(text)
                message = provider_message(data, text)
            else:
                message = bounded_provider_text(text)
            end
        end
        Error(AIProviderError: message)
    end
    try:
        data = json.decode(text)
    else:
        Error(AIProviderError: "provider returned invalid JSON")
    end
    if type(data) != "Dictionary":
        Error(AIProviderError: "provider response must be a Dictionary")
    end
    if "error" in data:
        Error(AIProviderError: provider_message(data, "provider failed"))
    end
    return data
end

function _headers(token, streaming):
    headers = {"Content-Type": "application/json"}
    if len(token) > 0:
        headers["Authorization"] = "Bearer " + token
    end
    if streaming:
        headers["Accept"] = "text/event-stream"
    end
    return headers
end

function _payload(model, messages, options, streaming):
    payload = {"model": model, "messages": messages}
    for name in ["temperature", "max_tokens"]:
        if name in options:
            payload[name] = options[name]
        end
    end
    if streaming:
        payload["stream"] = True
    end
    return payload
end

function _retryable(response):
    status = response["status"]
    return status == 0 or status == 408 or status == 429 or status >= 500
end

function request(endpoint, token, model, messages, options):
    call checked_request(endpoint, token, model, messages, options)
    headers = _headers(token, False)
    payload = _payload(model, messages, options, False)
    timeout = options.get("timeout", 60)
    retries = options.get("retries", 0)
    cancel = options.get("cancel", None)
    raw = options.get("transport_chunk", None)
    attempt = 0
    loop:
        call _cancelled(cancel)
        response = None
        if raw == None:
            response = http.post(endpoint, payload, headers, timeout)
        else:
            response = http.post_stream(endpoint, payload, headers, timeout, raw)
        end
        call _cancelled(cancel)
        if response["ok"] or not _retryable(response) or attempt >= retries:
            return decode_response(response)
        end
        attempt += 1
        call time.sleep(min(2.0, Float(attempt) * 0.1))
    end
end

function _decoder(on_event, cancel, raw):
    return {"line": ByteArray(), "data": [], "bytes": 0, "skip_lf": False, "first": True, "done": False, "delivered": 0, "on_event": on_event, "cancel": cancel, "raw": raw}
end

function _dispatch(state):
    if state["done"] or len(state["data"]) == 0:
        return
    end
    call _cancelled(state["cancel"])
    payload = chr(10).join(state["data"])
    state["data"] = []
    state["bytes"] = 0
    if payload.strip() == "[DONE]":
        state["done"] = True
        return
    elif payload.strip() == "":
        return
    end
    try:
        event = json.decode(payload)
    else:
        Error(AIProviderError: "provider returned invalid stream JSON")
    end
    if type(event) != "Dictionary":
        Error(AIProviderError: "stream event must be a Dictionary")
    elif "error" in event:
        Error(AIProviderError: provider_message(event, "provider stream failed"))
    end
    choices = event.get("choices", [])
    if type(choices) != "List":
        Error(AIProviderError: "stream choices must be a List")
    elif len(choices) == 0:
        return
    end
    choice = choices[0]
    if type(choice) != "Dictionary":
        Error(AIProviderError: "stream choice must be a Dictionary")
    end
    delta = choice.get("delta", {})
    if type(delta) != "Dictionary":
        Error(AIProviderError: "stream delta must be a Dictionary")
    end
    text = delta.get("content", None)
    if text == None or text == "":
        return
    elif type(text) != "String":
        Error(AIProviderError: "stream content must be a String or null")
    end
    # Po callbacku již nelze bezpečně opakovat požadavek: uživatel mohl text vypsat.
    state["delivered"] += 1
    callback = state["on_event"]
    call callback(text)
end

function _line(state):
    bytes = ByteArray(state["line"])
    unsafe:
        line = __lsl_text_from_bytes(bytes, 0, len(bytes))
    end
    state["line"] = ByteArray()
    if state["first"]:
        state["first"] = False
        if line.startswith(chr(65279)):
            line = line[1:len(line)]
        end
    end
    if line == "":
        call _dispatch(state)
    elif line == "data" or line.startswith("data:"):
        data = ""
        if line != "data":
            data = line[5:len(line)]
            if data.startswith(" "):
                data = data[1:len(data)]
            end
        end
        state["bytes"] += _byte_length(data) + 1
        if state["bytes"] > _MAX_EVENT_BYTES:
            Error(AIProviderError: "stream event exceeds 1 MiB")
        end
        state["data"].append(data)
    end
end

function _feed(state, chunk):
    call _cancelled(state["cancel"])
    for index in rang(_byte_length(chunk)):
        if state["done"]:
            return
        end
        unsafe:
            byte = __lsl_text_byte(String(chunk), index)
        end
        if state["skip_lf"]:
            state["skip_lf"] = False
            if byte == 10:
                continue
            end
        end
        if byte == 10 or byte == 13:
            state["skip_lf"] = byte == 13
            call _line(state)
        else:
            if len(state["line"]) >= _MAX_EVENT_BYTES:
                Error(AIProviderError: "stream line exceeds 1 MiB")
            end
            state["line"].append(byte)
        end
    end
end

function _finish(state, require_done):
    call _cancelled(state["cancel"])
    if not state["done"]:
        if len(state["line"]) > 0:
            call _line(state)
        end
        call _dispatch(state)
    end
    if require_done and not state["done"]:
        Error(AIProviderError: "stream ended before [DONE]; response may be incomplete")
    end
    return state["delivered"]
end

function stream_text(text, on_event, cancel=None):
    if type(text) != "String":
        Error(AIProviderError: "SSE input must be a String")
    end
    call _checked_callback(on_event, "on_event", False)
    call _checked_callback(cancel, "cancel", True)
    state = _decoder(on_event, cancel, None)
    call _feed(state, text)
    return _finish(state, False)
end

# HTTP callback nemá parametr pro kontext. Krátký zámek chrání pouze mapu;
# vlastní dekodéry a zásobníky vnořených volání jsou oddělené podle vlákna.
function _thread():
    unsafe:
        return String(__lsl_syscall(186, 0, 0, 0, 0))
    end
end

function _lock():
    while atomic_cas(_context_lock, 0, 0, 1) != 0:
        call atomic_pause()
    end
end

function _push_context(key, state):
    call _lock()
    if key not in _contexts:
        _contexts[key] = []
    end
    _contexts[key].append(state)
    call atomic_xchg(_context_lock, 0, 0)
end

function _pop_context(key):
    call _lock()
    call _contexts[key].pop()
    if len(_contexts[key]) == 0:
        del(_contexts[key])
    end
    call atomic_xchg(_context_lock, 0, 0)
end

function _receive(chunk):
    key = _thread()
    call _lock()
    state = _contexts[key][-1]
    call atomic_xchg(_context_lock, 0, 0)
    call _cancelled(state["cancel"])
    raw = state["raw"]
    if raw != None:
        call raw(chunk)
    end
    call _feed(state, chunk)
end

function _stream_failure(failure):
    # LSL nemá rethrow; zachováme veřejné AI typy a původní text callbacku.
    if failure.startswith("AICancelled: "):
        Error(AICancelled: failure[len("AICancelled: "):len(failure)])
    elif failure.startswith("AIProviderError: "):
        Error(AIProviderError: failure[len("AIProviderError: "):len(failure)])
    end
    Error(AIProviderError: "stream callback or transport failed: " + failure)
end

function stream(endpoint, token, model, messages, options, on_event):
    call checked_request(endpoint, token, model, messages, options)
    call _checked_callback(on_event, "on_event", False)
    headers = _headers(token, True)
    payload = _payload(model, messages, options, True)
    timeout = options.get("timeout", 60)
    retries = options.get("retries", 0)
    cancel = options.get("cancel", None)
    raw = options.get("transport_chunk", None)
    attempt = 0
    loop:
        call _cancelled(cancel)
        state = _decoder(on_event, cancel, raw)
        key = _thread()
        call _push_context(key, state)
        response = None
        failure = None
        try:
            response = http.post_stream(endpoint, payload, headers, timeout, _receive)
        else:
            failure = last_error()
        end
        call _pop_context(key)
        if failure != None:
            call _stream_failure(String(failure))
        end
        call _cancelled(cancel)
        if response["ok"]:
            return _finish(state, True)
        elif state["delivered"] > 0 or not _retryable(response) or attempt >= retries:
            return decode_response(response)
        end
        attempt += 1
        call time.sleep(min(2.0, Float(attempt) * 0.1))
    end
end

function content(response):
    if type(response) != "Dictionary" or "choices" not in response or type(response["choices"]) != "List" or len(response["choices"]) == 0:
        Error(AIProviderError: "provider response has no choices")
    end
    choice = response["choices"][0]
    if type(choice) != "Dictionary" or "message" not in choice or type(choice["message"]) != "Dictionary" or "content" not in choice["message"]:
        Error(AIProviderError: "provider response has no message content")
    end
    text = choice["message"]["content"]
    if text != None and type(text) != "String":
        Error(AIProviderError: "provider message content must be a String or null")
    end
    return text
end
