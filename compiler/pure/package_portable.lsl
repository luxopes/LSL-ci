# Knihovny z registru na Windows a macOS zatím nejsou. Rozhraní
# package_linux_x86_64.lsl; čisté funkce (jména, hashe, adresa registru,
# cesta uživatelských knihoven pro lsl list) fungují, ostatní operace hlásí
# srozumitelnou chybu.
load _platform as platform

# Absolutní cesta: "/" na macOS, "X:/" nebo "X:\" na Windows.
function absolute_home(home):
    text = String(home)
    if platform.NAME.startswith("windows-"):
        return len(text) >= 3 and text[1] == ":" and (text[2] == "/" or text[2] == chr(92))
    end
    return text[0] == "/"
end
LOCK_EX = 2
O_CLOEXEC = -1
O_CREAT = -1
O_NOFOLLOW = -1
O_RDWR = -1
SYS_FLOCK = -1
SYS_FSTAT = -1
S_IFMT = -1
S_IFREG = -1

function valid_name(name):
    if type(name) != "String" or len(name) == 0 or len(name) > 64:
        return False
    end
    index = 0
    for character in name:
        code = ord(character)
        if index == 0:
            if code < 97 or code > 122:
                return False
            end
        elif not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95):
            return False
        end
        index += 1
    end
    return True
end

function localhost_http(server):
    # Numeric loopback only: a mutable hosts/NSS configuration must not turn a
    # development-only plain-HTTP exception into a remote cleartext request.
    prefixes = ["http://127.0.0.1"]
    for prefix in prefixes:
        if server.startswith(prefix):
            if len(server) == len(prefix):
                return True
            end
            boundary = server[len(prefix)]
            if boundary == ":" or boundary == "/":
                return True
            end
        end
    end
    return False
end

function normalize_server(server):
    if type(server) != "String":
        Error(PackageError: "registry URL must be a String")
    end
    while len(server) > 0 and server[len(server) - 1] == "/":
        server = server[0:len(server) - 1]
    end
    if len(server) == 0 or len(server) > 2048:
        Error(PackageError: "registry URL is empty")
    end
    for character in server:
        code = ord(character)
        if code <= 32 or code == 127 or code > 127 or character == "?" or character == "#" or character == chr(92) or character == "@":
            Error(PackageError: "registry URL contains an unsafe character")
        end
    end
    if not server.startswith("https://") and not localhost_http(server):
        Error(PackageError: "registry must use HTTPS (localhost HTTP is allowed for tests)")
    end
    scheme_length = 8
    if server.startswith("http://"):
        scheme_length = 7
    end
    remainder = server[scheme_length:len(server)]
    slash = remainder.find("/")
    if slash < 0:
        slash = len(remainder)
    end
    authority = remainder[0:slash]
    if authority == "":
        Error(PackageError: "registry URL has an empty authority")
    end
    colon = authority.find(":")
    host = authority
    if colon >= 0:
        host = authority[0:colon]
        port = authority[colon + 1:len(authority)]
        if len(port) == 0 or len(port) > 5:
            Error(PackageError: "registry URL has an invalid port")
        end
        for character in port:
            code = ord(character)
            if code < 48 or code > 57:
                Error(PackageError: "registry URL has a non-numeric port")
            end
        end
        if Int(port) <= 0 or Int(port) > 65535:
            Error(PackageError: "registry URL port is out of range")
        end
    end
    if host == "":
        Error(PackageError: "registry URL host is empty")
    end
    for character in host:
        code = ord(character)
        if not ((code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or character == "." or character == "-" or character == "_"):
            Error(PackageError: "registry URL has an invalid host")
        end
    end
    return server
end

function remove_if_exists(path):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function cleanup_work(work, stage, check_path, origin_stage):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function fail_after_cleanup(message, work, stage, check_path, origin_stage):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function write_stage(path, content, message, work, stage, check_path, origin_stage):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function provenance_text(name, server, source_url, hash):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function parse_provenance(name, content):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function origin(name, home):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function acquire_package_lock(directory, name):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function release_package_lock(handle):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function verified_origin(name, home, sha256_path):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function fetch(curl_path, server, url):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function valid_hash(value):
    if len(value) != 64:
        return False
    end
    for character in value:
        code = ord(character)
        if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
            return False
        end
    end
    return True
end

function ensure_directory(path):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function user_path(home):
    if type(home) != "String" or len(home) == 0 or __lsl_text_byte_length(String(home)) > 4095 or not absolute_home(home):
        Error(PackageError: "HOME must be an absolute path")
    end
    for character in home:
        code = ord(character)
        if code == 0 or code < 32 or code == 127:
            Error(PackageError: "HOME contains a control character")
        end
    end
    for component in String(home).replace(chr(92), "/").split("/"):
        if component == "..":
            Error(PackageError: "HOME must not contain parent traversal")
        end
    end
    return home + "/.local/lib/lsl/stdlib"
end

function user_directory(home):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function work_directory(directory, name):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function config_names(path):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function install(name, home, server, curl_path, sha256_path, move_path, chmod_path, lsl_path):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function dependencies(source):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function install_graph(name, home, server, curl_path, sha256_path, move_path, chmod_path, lsl_path, active, completed):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function update(name, home, server, curl_path, sha256_path, move_path, chmod_path, lsl_path):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function install_config(path, home, server, curl_path, sha256_path, move_path, chmod_path, lsl_path):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end
