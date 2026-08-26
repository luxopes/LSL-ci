# HTTP/HTTPS orchestration through curl config on stdin. Request bodies,
# authorization headers and other sensitive values never enter process argv.

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
    status_text = output[split + 1:len(output)].strip()
    if len(status_text) != 3:
        return {"status": 0, "text": output, "ok": False}
    end
    for character in status_text:
        code = ord(character)
        if code < 48 or code > 57:
            return {"status": 0, "text": output, "ok": False}
        end
    end
    status = Int(status_text)
    body = output[0:split]
    return {"status": status, "text": body, "ok": status >= 200 and status < 300}
end

function transport_response(output):
    status = capture_status()
    if status != 0:
        message = capture_stderr()
        if len(message) == 0:
            message = "curl exited with status " + String(status)
        end
        return {"status": 0, "text": message, "ok": False}
    end
    return response(output)
end

function validate_url(url):
    value = String(url)
    if __lsl_text_byte_length(String(value)) > 8192:
        Error(HTTPError: "HTTP URL is too long")
    end
    if value.startswith("https://"):
        return value
    end
    loopback = value == "http://127.0.0.1" or value.startswith("http://127.0.0.1/") or value.startswith("http://127.0.0.1:")
    loopback = loopback or value == "http://localhost" or value.startswith("http://localhost/") or value.startswith("http://localhost:")
    loopback = loopback or value == "http://[::1]" or value.startswith("http://[::1]/") or value.startswith("http://[::1]:")
    if loopback:
        return value
    end
    Error(HTTPError: "HTTP transport requires HTTPS or a loopback URL")
end

function config_quote(value):
    text = String(value)
    result = chr(34)
    for character in text:
        code = ord(character)
        if code == 34 or code == 92:
            result += chr(92) + character
        elif code == 9:
            result += chr(92) + "t"
        elif code == 10:
            result += chr(92) + "n"
        elif code == 11:
            result += chr(92) + "v"
        elif code == 13:
            result += chr(92) + "r"
        elif code < 32 or code == 127:
            Error(HTTPError: "curl config value contains an unsupported control character")
        else:
            result += character
        end
    end
    return result + chr(34)
end

function header_name(name):
    value = String(name)
    if len(value) == 0:
        Error(HTTPError: "HTTP header name is empty")
    elif len(value) > 256:
        Error(HTTPError: "HTTP header name is too long")
    end
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-.^_`|~"
    for character in value:
        if character not in allowed:
            Error(HTTPError: "invalid HTTP header name: " + value)
        end
    end
    return value
end

function header_value(value):
    text = String(value)
    if __lsl_text_byte_length(String(text)) > 65536:
        Error(HTTPError: "HTTP header value is too long")
    end
    for character in text:
        code = ord(character)
        if code == 10 or code == 13 or code == 0 or code == 127 or (code < 32 and code != 9):
            Error(HTTPError: "HTTP header value contains a control character")
        end
    end
    return text
end

function config_line(name, value):
    return name + " = " + config_quote(value) + chr(10)
end

function common_config(url, timeout, streaming):
    timeout = Int(timeout)
    if timeout <= 0 or timeout > 3600:
        Error(HTTPError: "HTTP timeout must be between 1 and 3600 seconds")
    end
    result = "silent" + chr(10)
    result += "show-error" + chr(10)
    result += "globoff" + chr(10)
    result += "location" + chr(10)
    if streaming:
        result += "no-buffer" + chr(10)
    end
    result += config_line("max-time", String(timeout))
    result += config_line("max-redirs", "5")
    result += config_line("proto", "=https,http")
    result += config_line("proto-redir", "=https")
    result += config_line("write-out", chr(10) + "%{http_code}")
    result += config_line("url", validate_url(url))
    return result
end

function get_config(url):
    return common_config(url, 60, False)
end

function post_config(url, body, headers, timeout, streaming):
    encoded_body = ""
    if __lsl_type_code(body) == 3 or __lsl_type_code(body) == 2:
        encoded_body = json.encode(body)
    else:
        encoded_body = String(body)
    end
    if __lsl_text_byte_length(String(encoded_body)) > 4000000:
        Error(HTTPError: "HTTP request body exceeds the secure curl-config limit")
    end
    if __lsl_type_code(headers) != 3 or len(headers) > 256:
        Error(HTTPError: "HTTP headers must be a Dictionary with at most 256 entries")
    end
    result = common_config(url, timeout, streaming)
    result += config_line("request", "POST")
    result += config_line("data-raw", encoded_body)
    for key in headers:
        result += config_line("header", header_name(key) + ": " + header_value(headers[key]))
    end
    return result
end

# Transport-injection helpers keep conformance hermetic. Production callers
# normally use get/post/post_stream below with /usr/bin/curl.
function get_with(curl_path, url):
    output = capture_input(curl_path, ["--config", "-"], get_config(url))
    return transport_response(output)
end

function post_with(curl_path, url, body, headers, timeout):
    config = post_config(url, body, headers, timeout, False)
    output = capture_input(curl_path, ["--config", "-"], config)
    return transport_response(output)
end

function post_stream_with(curl_path, url, body, headers, timeout, on_chunk):
    config = post_config(url, body, headers, timeout, True)
    output = capture_input_stream(curl_path, ["--config", "-"], config, on_chunk)
    return transport_response(output)
end

function get(url):
    return get_with("/usr/bin/curl", url)
end

function post(url, body, headers, timeout):
    return post_with("/usr/bin/curl", url, body, headers, timeout)
end

function post_stream(url, body, headers, timeout, on_chunk):
    return post_stream_with("/usr/bin/curl", url, body, headers, timeout, on_chunk)
end
