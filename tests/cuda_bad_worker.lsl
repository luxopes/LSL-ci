load json

if arg(1) != None:
    print "short"
    exit(0)
end
request = json.decode(input(""))
if request.get("operation", "") == "cuda.probe":
    print json.encode({"abi": 1, "ok": True, "value": {"backend": "nvidia-cuda-runtime", "verified": True, "binary": True}})
else:
    print json.encode({"abi": 1, "ok": True, "value": "invalid"})
end
