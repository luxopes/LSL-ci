load cuda
load fd
load plugin

worker = arg(1)
if worker == None:
    worker = "./cuda/lsl-cuda-worker"
end
duplicate = "{\"abi\":1,\"" + chr(92) + "u0061bi\":1,\"operation\":\"cuda.sum\",\"payload\":{\"values\":[]}}"
output = capture_input_clean(worker, [], duplicate)
if output.find("duplicate key abi") < 0:
    Error(TestFailure: "escaped duplicate CUDA key was accepted")
end
surrogate = "{\"abi\":1,\"operation\":\"cuda.sum\",\"payload\":{\"values\":[],\"x\":\"" + chr(92) + "ud800\"}}"
output = capture_input_clean(worker, [], surrogate)
if output.find("unpaired JSON Unicode surrogate") < 0:
    Error(TestFailure: "unpaired CUDA JSON surrogate was accepted")
end

for header in ["", "{\"abi\":1,\"bytes\":0,\"operation\":\"info\"}", "{\"abi\":2,\"bytes\":16000008,\"operation\":\"upload\"}"]:
    output = plugin.capture_with_timeout(worker, ["--session"], "", 10)
    path = plugin.checked_response(output)
    handle = fd.connect_unix(path)
    size = len(header)
    prefix = __lsl_byte_zeros(4)
    prefix[0] = size
    call cuda.session_send(handle, __lsl_text_from_bytes(prefix, 0, 4) + String(header), monotonic() + 5.0)
    caught = False
    try:
        call cuda.session_read(handle, 4, monotonic() + 5.0)
    else:
        caught = True
    end
    call fd.close(handle)
    if not caught or exists(path):
        Error(TestFailure: "malformed CUDA frame did not close and clean the session")
    end
end
print "cuda-protocol-ok"
