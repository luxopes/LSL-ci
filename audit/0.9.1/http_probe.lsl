load httpserver
function handler(request):
    if request["target"] == "/204":
        return {"status": 204, "body": "BADBODY"}
    elif request["target"] == "/304":
        return {"status": 304, "body": "BADBODY"}
    end
    return "ok"
end
listener = httpserver.listen_ipv4("127.0.0.1", 0, 16)
print httpserver.local_port(listener)
print httpserver.serve_listener(listener, -1, handler, 4, False)
