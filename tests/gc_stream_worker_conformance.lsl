# gc() z hlavního vlákna, zatímco worker čte proud podprocesu přes
# capture_stream a v chunk callbacku skládá a dekóduje SSE řádky (cesta
# http.post_stream → curl → on_chunk → parser). Každá událost se musí přečíst
# celá, ve správném pořadí a s nepoškozeným obsahem.
load json

ROUNDS = 12
EVENTS = 300
done = IntArray()
done.append(0)
failures = IntArray()
failures.append(0)
received = IntArray()
received.append(0)
pending = [""]
expected = IntArray()
expected.append(0)
payload_text = "abcdefghijklmnopqrstuvwxyz0123456789" * 4

function take_line(line):
    if not line.startswith("data: "):
        failures[0] += 1
        return None
    end
    event = json.decode(line[6:len(line)])
    if event["n"] != expected[0] or event["text"] != payload_text or event["items"] != [event["n"], event["n"] + 1, "x"]:
        failures[0] += 1
    end
    expected[0] += 1
    received[0] += 1
end

function on_chunk(chunk):
    buffer = pending[0] + chunk
    lines = buffer.split(chr(10))
    for index in rang(len(lines) - 1):
        if lines[index] != "":
            call take_line(lines[index])
        end
    end
    pending[0] = lines[len(lines) - 1]
end

function stream_worker():
    script = "i=0; while [ $i -lt " + String(EVENTS) + " ]; do printf 'data: {\"n\": %d, \"text\": \"%s\", \"items\": [%d, %d, \"x\"]}\\n\\n' $i '" + payload_text + "' $i $((i+1)); i=$((i+1)); done"
    for round in rang(ROUNDS):
        expected[0] = 0
        pending[0] = ""
        output = capture_stream("/bin/sh", ["-c", script], on_chunk)
        if capture_status() != 0 or pending[0] != "" or expected[0] != EVENTS or len(output) == 0:
            failures[0] += 1
        end
    end
    call atomic_xchg(done, 0, 1)
    return None
end

collections = 0
unsafe:
    worker = thread_spawn(stream_worker)
    while atomic_add(done, 0, 0) == 0:
        garbage = [String(collections) * 50 for k in rang(200)]
        call gc()
        collections += 1
    end
    call thread_join(worker)
end
print "events", received[0], "failures", failures[0], "collected", collections > 0
