load json

request_text = arg(1)
if request_text == None:
    request_text = input("")
end
request = json.decode(request_text)
if request["abi"] != 1:
    print json.encode({"abi": 1, "ok": False, "error": "ABI mismatch"})
elif request["operation"] == "echo":
    print json.encode({"abi": 1, "ok": True, "value": request["payload"]})
elif request["operation"] == "transport":
    print json.encode({"abi": 1, "ok": True, "value": arg_count() - 1})
elif request["operation"] == "crash":
    exit(9)
else:
    print json.encode({"abi": 1, "ok": False, "error": "unknown operation"})
end
