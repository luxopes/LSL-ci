load ai
load json

success = {"status": 200, "text": "{\"choices\":[{\"message\":{\"content\":\"hello\"}}]}", "ok": True}
data = ai.decode_response(success)
print ai.content(data)

provider_error = {"status": 429, "text": "{\"error\":{\"message\":\"rate limited\"}}", "ok": False}
caught = ""
try:
    call ai.decode_response(provider_error)
else:
    caught = last_error()
end
print caught

invalid = {"status": 200, "text": "not-json", "ok": True}
try:
    call ai.decode_response(invalid)
else:
    caught = last_error()
end
print caught

events = []
function receive(chunk):
    events.append(chunk)
end
function keep_streaming():
    return False
end
stream_body = "data: {\"choices\":[{\"delta\":{\"content\":\"hel\"}}]}\n\n" + "data: {\"choices\":[{\"delta\":{\"content\":\"lo\"}}]}\n\n" + "data: [DONE]\n"
print ai.stream_text(stream_body, receive, keep_streaming), events

try:
    call ai.content({"choices": []})
else:
    caught = last_error()
end
print caught

reasoned = {"status": 200, "text": "{\"choices\":[{\"message\":{\"content\":\"answer\",\"reasoning_content\":\"thinking\"}}]}", "ok": True}
data = ai.decode_response(reasoned)
print ai.reasoning(data), ai.content(data), ai.reasoning(ai.decode_response(success))
try:
    call ai.checked_request("https://example.invalid/v1", "token", "model", [{"role": "user", "content": "hi"}], {"reasoning": {"depth": 1}})
else:
    caught = last_error()
end
print caught
