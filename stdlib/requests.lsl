# HTTP klient nad společným transportem http, včetně JSON a streamování.

load http
load json

class Response(True):
    ctype Public

    function init(self, status, text):
        self.status = Int(status)
        self.status_code = self.status
        self.text = String(text)
        self.ok = self.status >= 200 and self.status < 300
    end

    function json(self):
        if len(self.text) == 0:
            Error(JsonError: "empty response body cannot be decoded as JSON")
        end
        return json.decode(self.text)
    end

    function raise_for_status(self):
        if self.status == 0:
            Error(ConnectionError: "HTTP request failed: " + self.text)
        elif not self.ok:
            Error(HTTPStatusError: "HTTP " + String(self.status) + ": " + self.text)
        end
        return self
    end
end

function response_of(result):
    return Response(result["status"], result["text"])
end

function headers_of(headers):
    if headers == None:
        return {}
    end
    if type(headers) != "Dictionary":
        Error(HTTPError: "HTTP headers must be a Dictionary with at most 256 entries")
    end
    return Dictionary(headers)
end

function body_headers(data, headers):
    result = headers_of(headers)
    if type(data) == "Dictionary" or type(data) == "List":
        for name in result:
            if String(name).lower() == "content-type":
                return result
            end
        end
        result["Content-Type"] = "application/json"
    end
    return result
end

function body_of(data):
    if data == None:
        return ""
    end
    return data
end

function timeout_of(timeout):
    if timeout == None:
        return 60
    end
    return timeout
end

function get(url, headers=None, timeout=None):
    return response_of(http.get(url, headers_of(headers), timeout_of(timeout)))
end

function post(url, data=None, headers=None, timeout=None):
    return response_of(http.post(url, body_of(data), body_headers(data, headers), timeout_of(timeout)))
end

function put(url, data=None, headers=None, timeout=None):
    return response_of(http.post(url, body_of(data), body_headers(data, headers), timeout_of(timeout), "PUT"))
end

function patch(url, data=None, headers=None, timeout=None):
    return response_of(http.post(url, body_of(data), body_headers(data, headers), timeout_of(timeout), "PATCH"))
end

function delete(url, data=None, headers=None, timeout=None):
    return response_of(http.post(url, body_of(data), body_headers(data, headers), timeout_of(timeout), "DELETE"))
end

function head(url, headers=None, timeout=None):
    return response_of(http.post(url, "", headers_of(headers), timeout_of(timeout), "HEAD"))
end

function request(method, url, data=None, headers=None, timeout=None):
    method = String(method).upper()
    if method == "GET":
        return response_of(http.get(url, headers_of(headers), timeout_of(timeout)))
    end
    return response_of(http.post(url, body_of(data), body_headers(data, headers), timeout_of(timeout), method))
end

function post_stream(url, data, headers, timeout, on_chunk, method="POST"):
    return response_of(http.post_stream(url, body_of(data), body_headers(data, headers), timeout_of(timeout), on_chunk, String(method).upper()))
end
