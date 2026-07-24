# Per-user LSL source library installer. Downloads use curl argv directly,
# validate a registry-published SHA-256, compile the source, and atomically move
# it into the user module directory. No shell is involved.

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
    prefixes = ["http://127.0.0.1", "http://localhost"]
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
    if len(server) == 0:
        Error(PackageError: "registry URL is empty")
    end
    for character in server:
        code = ord(character)
        if code <= 32 or code == 127 or character == "?" or character == "#":
            Error(PackageError: "registry URL contains an unsafe character")
        end
    end
    if not server.startswith("https://") and not localhost_http(server):
        Error(PackageError: "registry must use HTTPS (localhost HTTP is allowed for tests)")
    end
    return server
end

function remove_if_exists(path):
    if exists(path):
        call unlink(path)
    end
end

function fail_after_cleanup(message, stage, check_path):
    call remove_if_exists(stage)
    call remove_if_exists(check_path)
    Error(PackageError: message)
end

function fetch(curl_path, server, url):
    if exists(curl_path):
        protocols = "=https"
        if localhost_http(server):
            protocols = "=http,https"
        end
        arguments = [
            "--fail",
            "--show-error",
            "--silent",
            "--location",
            "--max-time", "120",
            "--max-filesize", "1048576",
            "--proto", protocols,
            "--proto-redir", protocols,
            url
        ]
        output = capture(curl_path, arguments)
        tool = "curl"
    elif server == "https://luxos-registry-temp-2026.netlify.app/lsl" and exists("/bin/wget"):
        # The diskless image has pinned BusyBox and CA roots but intentionally
        # omits curl. Keep this fallback scoped to the temporary HTTPS origin.
        output = capture("/bin/wget", ["-q", "-T", "120", "-O", "-", url])
        tool = "wget"
    else:
        Error(PackageError: "curl is required for this registry")
    end
    status = capture_status()
    if status != 0:
        detail = capture_stderr().strip()
        if detail == "":
            detail = tool + " exited with status " + String(status)
        end
        Error(PackageError: "download failed: " + detail)
    elif len(output) > 1048576:
        Error(PackageError: "download exceeds 1 MiB")
    end
    return output
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
    if not exists(path):
        status = mkdir(path)
        if status != 0:
            Error(PackageError: "cannot create directory " + path)
        end
    end
end

function user_directory(home):
    if type(home) != "String" or len(home) == 0 or home[0] != "/":
        Error(PackageError: "HOME must be an absolute path")
    end
    base = home + "/.local"
    call ensure_directory(base)
    base += "/lib"
    call ensure_directory(base)
    base += "/lsl"
    call ensure_directory(base)
    directory = base + "/stdlib"
    call ensure_directory(directory)
    return directory
end

function config_names(path):
    if type(path) != "String" or len(path) == 0 or not exists(path):
        Error(PackageError: "package config does not exist: " + String(path))
    end
    content = readfile(path)
    if len(content) == 0 or len(content) > 65536:
        Error(PackageError: "package config has an invalid size")
    end
    for character in content:
        code = ord(character)
        if character != chr(10) and (code < 32 or code > 126):
            Error(PackageError: "package config must use printable UTF-8 ASCII and LF")
        end
    end
    names = []
    seen = {}
    line_number = 0
    for line in content.split(chr(10)):
        line_number += 1
        if line == "" or line.startswith("#"):
            continue
        elif not valid_name(line):
            Error(PackageError: "config:" + String(line_number) + ": invalid library name: " + line)
        elif line in seen:
            Error(PackageError: "config:" + String(line_number) + ": duplicate library: " + line)
        end
        seen[line] = True
        names.append(line)
        if len(names) > 256:
            Error(PackageError: "package config contains too many entries")
        end
    end
    if len(names) == 0:
        Error(PackageError: "package config contains no library names")
    end
    return names
end

function install(name, home, server, curl_path, sha256_path, move_path, chmod_path, lsl_path):
    if not valid_name(name):
        Error(PackageError: "invalid library name: " + String(name))
    end
    server = normalize_server(server)
    directory = user_directory(home)

    source_url = server + "/" + name + ".lsl"
    hash_url = server + "/" + name + ".sha256"
    print "Fetching", source_url
    source = fetch(curl_path, server, source_url)
    expected = fetch(curl_path, server, hash_url).strip()
    if len(source) == 0:
        Error(PackageError: "downloaded library is empty")
    elif chr(0) in source:
        Error(PackageError: "downloaded library contains a NUL byte")
    elif not valid_hash(expected):
        Error(PackageError: "registry returned an invalid SHA-256")
    end

    destination = directory + "/" + name + ".lsl"
    # Content-addressed staging prevents different concurrent downloads of the
    # same name from modifying a file after another process verified its hash.
    stage = directory + "/." + name + "." + expected + ".new"
    check_path = directory + "/." + name + "." + expected + ".check"
    call remove_if_exists(stage)
    call remove_if_exists(check_path)
    call writefile(stage, source)

    hash_output = capture(sha256_path, [stage])
    hash_status = capture_status()
    if hash_status != 0 or len(hash_output) < 64:
        call fail_after_cleanup("cannot calculate downloaded SHA-256", stage, check_path)
    end
    actual = hash_output[0:64]
    if not valid_hash(actual) or actual != expected:
        call fail_after_cleanup("SHA-256 mismatch for " + name, stage, check_path)
    end
    if run(chmod_path, ["0644", "--", stage]) != 0:
        call fail_after_cleanup("cannot set safe library permissions", stage, check_path)
    end
    if run(lsl_path, ["compile", stage, check_path]) != 0:
        call fail_after_cleanup("downloaded library does not compile", stage, check_path)
    end
    call remove_if_exists(check_path)
    if run(move_path, ["-f", "--", stage, destination]) != 0:
        call fail_after_cleanup("atomic library installation failed", stage, check_path)
    end
    print "Installed", name, "into", destination + "."
end

function update(name, home, server, curl_path, sha256_path, move_path, chmod_path, lsl_path):
    if not valid_name(name):
        Error(PackageError: "invalid library name: " + String(name))
    end
    destination = user_directory(home) + "/" + name + ".lsl"
    if not exists(destination):
        Error(PackageError: "library is not installed: " + name)
    end
    call install(name, home, server, curl_path, sha256_path, move_path, chmod_path, lsl_path)
end

function install_config(path, home, server, curl_path, sha256_path, move_path, chmod_path, lsl_path):
    # Validate every line before the first download. Network or filesystem
    # failures can still leave an earlier requested library installed.
    names = config_names(path)
    for name in names:
        call install(name, home, server, curl_path, sha256_path, move_path, chmod_path, lsl_path)
    end
end
