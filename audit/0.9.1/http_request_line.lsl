load httpserver, json
function handler(request):
    return json.encode({"method": request["method"], "target": request["target"], "header": request["headers"].get("x-test", "")})
end
listener = httpserver.listen_ipv4("127.0.0.1", 0, 16)
print httpserver.local_port(listener)
print httpserver.serve_listener(listener, -1, handler, 3, False)
