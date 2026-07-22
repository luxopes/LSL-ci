# OpenAI-compatible AI orchestration with structured provider errors and retries.

load http
load json

function provider_message(data, fallback):
    if __lsl_type_code(data) == 3 and "error" in data:
        error = data["error"]
        if __lsl_type_code(error) == 3 and "message" in error:
            return String(error["message"])
        end
        return String(error)
    end
    return fallback
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
                message = text
            end
        end
        Error(AIProviderError: message)
    end
    try:
        data = json.decode(text)
    else:
        Error(AIProviderError: "provider returned invalid JSON")
    end
    if __lsl_type_code(data) != 3:
        Error(AIProviderError: "provider response must be a Dictionary")
    end
    if "error" in data:
        Error(AIProviderError: provider_message(data, "provider failed"))
    end
    return data
end

function request(endpoint, token, model, messages, options):
    headers = {"Content-Type": "application/json"}
    if len(token) > 0:
        headers["Authorization"] = "Bearer " + token
    end
    payload = {"model": model, "messages": messages}
    if "temperature" in options:
        payload["temperature"] = options["temperature"]
    end
    if "max_tokens" in options:
        payload["max_tokens"] = options["max_tokens"]
    end
    timeout = 60
    if "timeout" in options:
        timeout = Int(options["timeout"])
    end
    retries = 0
    if "retries" in options:
        retries = Int(options["retries"])
    end
    attempt = 0
    while True:
        if "cancel" in options and options["cancel"] != None:
            cancelled = options["cancel"]
            if cancelled():
                Error(AICancelled: "request cancelled")
            end
        end
        response = http.post(endpoint, payload, headers, timeout)
        status = response["status"]
        retryable = status == 0 or status == 408 or status == 429 or status >= 500
        if response["ok"] or not retryable or attempt >= retries:
            return decode_response(response)
        end
        attempt += 1
    end
end

function stream_text(text, on_event, cancel):
    delivered = 0
    lines = text.split(chr(10))
    for raw_line in lines:
        line = raw_line.strip()
        if line.startswith("data:"):
            payload = line[5:len(line)].strip()
            if payload == "[DONE]":
                break
            end
            if cancel != None and cancel():
                Error(AICancelled: "stream cancelled")
            end
            try:
                event = json.decode(payload)
            else:
                Error(AIProviderError: "provider returned invalid stream JSON")
            end
            if "error" in event:
                Error(AIProviderError: provider_message(event, "provider stream failed"))
            end
            if "choices" in event and len(event["choices"]) > 0:
                choice = event["choices"][0]
                if "delta" in choice and "content" in choice["delta"]:
                    chunk = choice["delta"]["content"]
                    call on_event(chunk)
                    delivered += 1
                end
            end
        end
    end
    return delivered
end

function stream(endpoint, token, model, messages, options, on_event):
    headers = {"Content-Type": "application/json"}
    if len(token) > 0:
        headers["Authorization"] = "Bearer " + token
    end
    payload = {"model": model, "messages": messages, "stream": True}
    timeout = 60
    if "timeout" in options:
        timeout = Int(options["timeout"])
    end
    response = http.post(endpoint, payload, headers, timeout)
    if not response["ok"]:
        return decode_response(response)
    end
    cancel = None
    if "cancel" in options:
        cancel = options["cancel"]
    end
    return stream_text(response["text"], on_event, cancel)
end

function content(response):
    if "choices" not in response or len(response["choices"]) == 0:
        Error(AIProviderError: "provider response has no choices")
    end
    choice = response["choices"][0]
    if "message" not in choice or "content" not in choice["message"]:
        Error(AIProviderError: "provider response has no message content")
    end
    return choice["message"]["content"]
end
