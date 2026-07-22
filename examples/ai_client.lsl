# OpenAI-compatible HTTP request. Secret se čte až za běhu, nikdy v pure configu.
load ai
load env

endpoint = "http://127.0.0.1:11434/v1/chat/completions"
token = env.get("LSL_AI_TOKEN", "local")
messages = [
    {"role": "user", "content": "Odpověz jednou krátkou větou."}
]
response = ai.request(endpoint, token, "local-model", messages, {"timeout": 60, "retries": 2})
print ai.content(response)
