load json

request = json.decode(arg(1))
if request["abi"] != 1:
    print json.encode({"abi": 1, "ok": False, "error": "ABI mismatch"})
elif request["operation"] == "echo":
    print json.encode({"abi": 1, "ok": True, "value": request["payload"]})
else:
    print json.encode({"abi": 1, "ok": False, "error": "unknown operation"})
end
