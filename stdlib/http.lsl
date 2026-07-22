# HTTP/HTTPS orchestration through curl argv, never through a shell.

load json

function response(output):
    split = -1
    index = 0
    while index < len(output):
        if output[index] == chr(10):
            split = index
        end
        index += 1
    end
    if split < 0:
        return {"status": 0, "text": output, "ok": False}
    end
    status = Int(output[split + 1:len(output)].strip())
    body = output[0:split]
    return {"status": status, "text": body, "ok": status >= 200 and status < 300}
end

function get(url):
    arguments = ["--silent", "--show-error", "--location", "--write-out", chr(10) + "%{http_code}", url]
    return response(capture("/usr/bin/curl", arguments))
end

function post_stream(url, body, headers, timeout, on_chunk):
    if __lsl_type_code(body) == 3 or __lsl_type_code(body) == 2:
        body = json.encode(body)
    end
    arguments = ["--silent", "--show-error", "--no-buffer", "--location", "--request", "POST", "--max-time", String(timeout), "--write-out", chr(10) + "%{http_code}", "--data", body]
    for key in headers:
        arguments.append("--header")
        arguments.append(key + ": " + headers[key])
    end
    arguments.append(url)
    return response(capture_stream("/usr/bin/curl", arguments, on_chunk))
end

function post(url, body, headers, timeout):
    if __lsl_type_code(body) == 3 or __lsl_type_code(body) == 2:
        body = json.encode(body)
    end
    arguments = ["--silent", "--show-error", "--location", "--request", "POST", "--max-time", String(timeout), "--write-out", chr(10) + "%{http_code}", "--data", body]
    for key in headers:
        arguments.append("--header")
        arguments.append(key + ": " + headers[key])
    end
    arguments.append(url)
    return response(capture("/usr/bin/curl", arguments))
end
