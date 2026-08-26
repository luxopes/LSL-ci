load plugin
load json

worker = arg(1) + "/plugin-process-server"
value = plugin.request(worker, "echo", {"text": "pure", "count": 3})
print json.encode(value)
print plugin.request(worker, "transport", "not-in-argv")
try:
    call plugin.request(worker, "missing", None)
else:
    print last_error()
end
try:
    call plugin.request(worker, "crash", None)
else:
    print last_error()
end
