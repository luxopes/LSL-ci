load json

request = json.decode(arg(1))
operation = request.get("operation", "")
payload = request.get("payload", {})
value = None

if operation == "cuda.devices":
    value = [{"index": 0, "name": "LSL CUDA test device", "compute_capability": "9.0", "memory_bytes": 8589934592}]
elif operation == "cuda.sum":
    total = 0.0
    for item in payload["values"]:
        total += Float(item)
    end
    value = total
elif operation == "cuda.dot":
    total = 0.0
    index = 0
    while index < len(payload["left"]):
        total += Float(payload["left"][index]) * Float(payload["right"][index])
        index += 1
    end
    value = total
elif operation == "cuda.axpy":
    value = []
    index = 0
    while index < len(payload["x"]):
        value.append(Float(payload["alpha"]) * Float(payload["x"][index]) + Float(payload["y"][index]))
        index += 1
    end
elif operation == "cuda.matmul":
    value = []
    row = 0
    while row < Int(payload["m"]):
        column = 0
        while column < Int(payload["n"]):
            total = 0.0
            inner = 0
            while inner < Int(payload["k"]):
                total += Float(payload["left"][row * Int(payload["k"]) + inner]) * Float(payload["right"][inner * Int(payload["n"]) + column])
                inner += 1
            end
            value.append(total)
            column += 1
        end
        row += 1
    end
else:
    print json.encode({"abi": 1, "ok": False, "error": "unsupported CUDA test operation"})
    exit(0)
end

print json.encode({"abi": 1, "ok": True, "value": value})
