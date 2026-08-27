# HTTP/HTTPS orchestration through curl config on stdin. Request bodies,
# authorization headers and other sensitive values never enter process argv.

load json

function byte_text_slice(source, start, stop):
    count = stop - start
    output = __lsl_byte_zeros(count)
    index = 0
    while index < count:
        output[index] = __lsl_text_byte(source, start + index)
        index += 1
    end
    return __lsl_text_from_bytes(output, 0, count)
end

function response(output):
    source = String(output)
    count = __lsl_text_byte_length(source)
    split = -1
    index = 0
    while index < count:
        if __lsl_text_byte(source, index) == 10:
            split = index
        end
        index += 1
    end
    if split < 0:
        return {"status": 0, "text": output, "ok": False}
    end
    if count - split - 1 != 3:
        return {"status": 0, "text": output, "ok": False}
    end
    status = 0
    index = split + 1
    while index < count:
        code = __lsl_text_byte(source, index)
        if code < 48 or code > 57:
            return {"status": 0, "text": output, "ok": False}
        end
        status = status * 10 + code - 48
        index += 1
    end
    body = byte_text_slice(source, 0, split)
    return {"status": status, "text": body, "ok": status >= 200 and status < 300}
end

function transport_response(output):
    status = capture_status()
    if status != 0:
        message = capture_stderr()
        if len(message) == 0:
            message = "curl exited with status " + String(status)
        elif len(message) > 4096:
            message = message[0:4096]
        end
        return {"status": 0, "text": message, "ok": False}
    end
    return response(output)
end

function url_port(text):
    if len(text) == 0 or len(text) > 5:
        Error(HTTPError: "HTTP URL has an invalid port")
    end
    for character in text:
        code = ord(character)
        if code < 48 or code > 57:
            Error(HTTPError: "HTTP URL has a non-numeric port")
        end
    end
    port = Int(text)
    if port <= 0 or port > 65535:
        Error(HTTPError: "HTTP URL port is out of range")
    end
    return port
end

function validate_url(url):
    value = String(url)
    byte_length = __lsl_text_byte_length(value)
    if byte_length == 0 or byte_length > 8192:
        Error(HTTPError: "HTTP URL must contain 1..8192 bytes")
    end
    for character in value:
        code = ord(character)
        if code <= 32 or code == 127 or code > 127 or character == chr(92) or character == "#":
            Error(HTTPError: "HTTP URL contains an unsafe character")
        end
    end
    if value.startswith("https://"):
        scheme_length = 8
        secure = True
    elif value.startswith("http://"):
        scheme_length = 7
        secure = False
    else:
        Error(HTTPError: "HTTP transport requires HTTPS or a loopback HTTP URL")
    end
    remainder = value[scheme_length:len(value)]
    authority_end = len(remainder)
    slash = remainder.find("/")
    query = remainder.find("?")
    if slash >= 0 and slash < authority_end:
        authority_end = slash
    end
    if query >= 0 and query < authority_end:
        authority_end = query
    end
    authority = remainder[0:authority_end]
    if len(authority) == 0 or authority.find("@") >= 0:
        Error(HTTPError: "HTTP URL authority is empty or contains user information")
    end
    host = authority
    port_text = ""
    if authority.startswith("["):
        close = authority.find("]")
        if close <= 1:
            Error(HTTPError: "HTTP URL has an invalid IPv6 authority")
        end
        host = authority[0:close + 1]
        suffix = authority[close + 1:len(authority)]
        if suffix != "":
            if not suffix.startswith(":"):
                Error(HTTPError: "HTTP URL has data after its IPv6 host")
            end
            port_text = suffix[1:len(suffix)]
        end
        for character in host[1:len(host) - 1]:
            if character not in "0123456789abcdefABCDEF:.":
                Error(HTTPError: "HTTP URL has an invalid IPv6 host")
            end
        end
    else:
        colon = authority.find(":")
        if colon >= 0:
            host = authority[0:colon]
            port_text = authority[colon + 1:len(authority)]
            if port_text.find(":") >= 0:
                Error(HTTPError: "HTTP URL has an invalid authority")
            end
        end
        if len(host) == 0:
            Error(HTTPError: "HTTP URL host is empty")
        end
        for character in host:
            if character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_":
                Error(HTTPError: "HTTP URL has an invalid host")
            end
        end
    end
    if port_text != "":
        call url_port(port_text)
    elif authority.endswith(":"):
        Error(HTTPError: "HTTP URL port is empty")
    end
    if not secure and host != "127.0.0.1" and host != "[::1]":
        Error(HTTPError: "plain HTTP is restricted to numeric loopback hosts")
    end
    return value
end

function config_quote(value):
    text = String(value)
    count = __lsl_text_byte_length(text)
    if count > 4000000:
        Error(HTTPError: "curl config value exceeds 4 MB")
    end
    # Curl config escaping is byte-oriented. A growing String copied the whole
    # request body on every character and allowed a trivial CPU/memory DoS.
    result = __lsl_byte_zeros(0)
    result.append(34)
    index = 0
    while index < count:
        code = __lsl_text_byte(text, index)
        if code == 34 or code == 92:
            result.append(92)
            result.append(code)
        elif code == 9:
            result.append(92)
            result.append(116)
        elif code == 10:
            result.append(92)
            result.append(110)
        elif code == 11:
            result.append(92)
            result.append(118)
        elif code == 13:
            result.append(92)
            result.append(114)
        elif code < 32 or code == 127:
            Error(HTTPError: "curl config value contains an unsupported control character")
        else:
            result.append(code)
        end
        if len(result) > 8000001:
            Error(HTTPError: "escaped curl config value exceeds 8 MB")
        end
        index += 1
    end
    result.append(34)
    return __lsl_text_from_bytes(result, 0, len(result))
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
    checked_url = validate_url(url)
    result = "silent" + chr(10)
    result += "show-error" + chr(10)
    result += "globoff" + chr(10)
    if streaming:
        result += "no-buffer" + chr(10)
    end
    result += config_line("max-time", String(timeout))
    result += config_line("max-filesize", "16777216")
    if checked_url.startswith("https://"):
        result += config_line("proto", "=https")
        result += "tlsv1.2" + chr(10)
    else:
        result += config_line("proto", "=http")
    end
    result += config_line("write-out", chr(10) + "%{http_code}")
    result += config_line("url", checked_url)
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
    pieces = [common_config(url, timeout, streaming)]
    pieces.append(config_line("request", "POST"))
    pieces.append(config_line("data-raw", encoded_body))
    for key in headers:
        pieces.append(config_line("header", header_name(key) + ": " + header_value(headers[key])))
    end
    return "".join(pieces)
end

# Transport-injection helpers keep conformance hermetic. Production callers
# normally use get/post/post_stream below with /usr/bin/curl.
function get_with(curl_path, url):
    output = capture_input_clean(curl_path, ["-q", "--config", "-"], get_config(url))
    return transport_response(output)
end

function post_with(curl_path, url, body, headers, timeout):
    config = post_config(url, body, headers, timeout, False)
    output = capture_input_clean(curl_path, ["-q", "--config", "-"], config)
    return transport_response(output)
end

function post_stream_with(curl_path, url, body, headers, timeout, on_chunk):
    config = post_config(url, body, headers, timeout, True)
    output = capture_input_stream_clean(curl_path, ["-q", "--config", "-"], config, on_chunk)
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
