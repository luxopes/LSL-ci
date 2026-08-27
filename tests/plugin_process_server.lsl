load json
load env

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
    clean = env.get("PATH", None) == None and env.get("HOME", None) == None
    print json.encode({"abi": 1, "ok": True, "value": {"arguments": arg_count() - 1, "clean_environment": clean}})
elif request["operation"] == "crash":
    exit(9)
elif request["operation"] == "hang":
    loop:
        call __lsl_sleep(1.0)
    end
else:
    print json.encode({"abi": 1, "ok": False, "error": "unknown operation"})
end
