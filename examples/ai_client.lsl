# OpenAI-compatible HTTP request. Secret se čte až za běhu, nikdy v pure configu.
load env
load http
load json

endpoint = "http://127.0.0.1:11434/v1/chat/completions"
token = env.get("LSL_AI_TOKEN", "local")
request = {
    "model": "local-model"
    "messages": [
        {"role": "user", "content": "Odpověz jednou krátkou větou."}
    ]
}
headers = {
    "Authorization": "Bearer " + token
}

response = http.post(endpoint, request, headers, 60)
if response.ok:
    data = json.decode(response.text)
    print json.pretty(data)
else:
    print "HTTP", response.status, response.text
end
