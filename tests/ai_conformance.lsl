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

try:
    call ai.content({"choices": []})
else:
    caught = last_error()
end
print caught
