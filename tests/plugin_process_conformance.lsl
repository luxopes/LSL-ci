load plugin
load json

value = plugin.request("/tmp/lsl-plugin-process-server", "echo", {"text": "pure", "count": 3})
print json.encode(value)
try:
    call plugin.request("/tmp/lsl-plugin-process-server", "missing", None)
else:
    print last_error()
end
