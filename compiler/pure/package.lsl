# Per-user LSL source library installer. Downloads use curl argv directly,
# validate a registry-published SHA-256, compile the source, and atomically move
# it into the user module directory. No shell is involved.

SYS_FLOCK = 73
LOCK_EX = 2
O_RDWR = 2
O_CREAT = 64
O_CLOEXEC = 524288
O_NOFOLLOW = 131072
SYS_FSTAT = 5
S_IFMT = 61440
S_IFREG = 32768

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
    if exists(path):
        call unlink(path)
    end
end

function cleanup_work(work, stage, check_path, origin_stage):
    call remove_if_exists(stage)
    call remove_if_exists(check_path)
    call remove_if_exists(origin_stage)
    call rmdir(work)
end

function fail_after_cleanup(message, work, stage, check_path, origin_stage):
    call cleanup_work(work, stage, check_path, origin_stage)
    Error(PackageError: message)
end

function write_stage(path, content, message, work, stage, check_path, origin_stage):
    failed = False
    try:
        call writefile(path, content)
    else:
        failed = True
    end
    if failed:
        call fail_after_cleanup(message, work, stage, check_path, origin_stage)
    end
end

function provenance_text(name, server, source_url, hash):
    return "format=1" + chr(10) + "name=" + name + chr(10) + "origin=" + server + chr(10) + "source=" + source_url + chr(10) + "sha256=" + hash + chr(10)
end

function parse_provenance(name, content):
    text = String(content)
    if len(text) == 0 or __lsl_text_byte_length(text) > 8192:
        Error(PackageError: "package provenance has an invalid size: " + name)
    end
    values = {}
    for line in text.split(chr(10)):
        if line == "":
            continue
        end
        for character in line:
            code = ord(character)
            if code < 32 or code > 126:
                Error(PackageError: "package provenance must use printable ASCII: " + name)
            end
        end
        separator = line.find("=")
        if separator <= 0:
            Error(PackageError: "package provenance contains an invalid field: " + name)
        end
        key = line[0:separator]
        value = line[separator + 1:len(line)]
        if key != "format" and key != "name" and key != "origin" and key != "source" and key != "sha256":
            Error(PackageError: "package provenance contains an unknown field: " + key)
        elif key in values:
            Error(PackageError: "package provenance contains a duplicate field: " + key)
        end
        values[key] = value
    end
    for required in ["format", "name", "origin", "source", "sha256"]:
        if required not in values:
            Error(PackageError: "package provenance is missing " + required + ": " + name)
        end
    end
    if values["format"] != "1" or values["name"] != name:
        Error(PackageError: "package provenance identity differs: " + name)
    end
    values["origin"] = normalize_server(values["origin"])
    expected_source = values["origin"] + "/" + name + ".lsl"
    if values["source"] != expected_source or not valid_hash(values["sha256"]):
        Error(PackageError: "package provenance URL or SHA-256 is invalid: " + name)
    end
    return values
end

function origin(name, home):
    if not valid_name(name):
        Error(PackageError: "invalid library name: " + String(name))
    end
    destination = user_directory(home) + "/" + name + ".lsl"
    if not exists(destination):
        Error(PackageError: "library is not installed: " + name)
    end
    sidecar = destination + ".origin"
    if not exists(sidecar):
        Error(PackageError: "library has no recorded origin; update it with LSL 0.7: " + name)
    end
    return parse_provenance(name, readfile(sidecar))
end

function acquire_package_lock(directory, name):
    # Keep one persistent inode per package. flock is released by close or
    # process exit, so a crash cannot leave a stale lock directory behind.
    path = directory + "/." + name + ".lock"
    handle = __lsl_fd_open(path, O_RDWR + O_CREAT + O_CLOEXEC + O_NOFOLLOW)
    if handle < 0:
        Error(PackageError: "cannot open package lock: " + name)
    end
    metadata = __lsl_byte_zeros(144)
    if __lsl_syscall(SYS_FSTAT, handle, __lsl_data_address(metadata), 0, 0) < 0 or ((metadata[24] + metadata[25] * 256) & S_IFMT) != S_IFREG:
        call __lsl_fd_close(handle)
        Error(PackageError: "package lock is not a regular file: " + name)
    end
    if __lsl_syscall(SYS_FLOCK, handle, LOCK_EX, 0, 0) < 0:
        call __lsl_fd_close(handle)
        Error(PackageError: "cannot lock package: " + name)
    end
    return handle
end

function release_package_lock(handle):
    call __lsl_fd_close(Int(handle))
end

function verified_origin(name, home, sha256_path):
    if not valid_name(name):
        Error(PackageError: "invalid library name: " + String(name))
    end
    directory = user_directory(home)
    lock = acquire_package_lock(directory, name)
    result = None
    failure = None
    try:
        result = origin(name, home)
        destination = directory + "/" + name + ".lsl"
        hash_output = capture_clean(sha256_path, [destination])
        hash_status = capture_status()
        if hash_status != 0 or len(hash_output) < 64 or not valid_hash(hash_output[0:64]):
            Error(PackageError: "cannot verify installed library SHA-256: " + name)
        elif hash_output[0:64] != result["sha256"]:
            Error(PackageError: "installed library differs from recorded provenance: " + name)
        end
    else:
        failure = last_error()
    end
    call release_package_lock(lock)
    if failure != None:
        Error(PackageError: failure)
    end
    return result
end

function fetch(curl_path, server, url):
    if exists(curl_path):
        protocols = "=https"
        if localhost_http(server):
            protocols = "=http,https"
        end
        arguments = [
            "-q",
            "--fail",
            "--show-error",
            "--silent",
            "--max-time", "120",
            "--max-filesize", "1048576",
            "--proto", protocols,
            url
        ]
        output = capture_clean(curl_path, arguments)
        tool = "curl"
    elif server == "https://luxos-registry-temp-2026.netlify.app/lsl" and exists("/bin/wget"):
        # The diskless image has pinned BusyBox and CA roots but intentionally
        # omits curl. Keep this fallback scoped to the temporary HTTPS origin.
        output = capture_clean("/bin/wget", ["-q", "-T", "120", "-O", "-", url])
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
    elif __lsl_text_byte_length(output) > 1048576:
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
    if type(home) != "String" or len(home) == 0 or __lsl_text_byte_length(String(home)) > 4095 or home[0] != "/":
        Error(PackageError: "HOME must be an absolute path")
    end
    for character in home:
        code = ord(character)
        if code == 0 or code < 32 or code == 127:
            Error(PackageError: "HOME contains a control character")
        end
    end
    for component in home.split("/"):
        if component == "..":
            Error(PackageError: "HOME must not contain parent traversal")
        end
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

function work_directory(directory, name):
    process = __lsl_syscall(39, 0, 0, 0, 0)
    attempt = 0
    while attempt < 128:
        path = directory + "/." + name + ".install-" + String(process) + "-" + String(attempt)
        if __lsl_mkdir_private(path) == 0:
            return path
        end
        attempt += 1
    end
    Error(PackageError: "cannot create a private package staging directory")
end

function config_names(path):
    if type(path) != "String" or len(path) == 0 or not exists(path):
        Error(PackageError: "package config does not exist: " + String(path))
    end
    content = readfile(path)
    if len(content) == 0 or __lsl_text_byte_length(String(content)) > 65536:
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
    if __lsl_text_byte_length(source) == 0:
        Error(PackageError: "downloaded library is empty")
    elif chr(0) in source:
        Error(PackageError: "downloaded library contains a NUL byte")
    elif not valid_hash(expected):
        Error(PackageError: "registry returned an invalid SHA-256")
    end

    destination = directory + "/" + name + ".lsl"
    # Atomic mkdir gives every invocation a private 0700 staging boundary.
    # Other local users cannot replace a verified file between hash and rename.
    work = work_directory(directory, name)
    stage = work + "/source.lsl"
    check_path = work + "/compiled-check"
    origin_stage = work + "/source.origin"
    call write_stage(stage, source, "cannot write package staging source", work, stage, check_path, origin_stage)

    hash_output = capture_clean(sha256_path, [stage])
    hash_status = capture_status()
    if hash_status != 0 or len(hash_output) < 64:
        call fail_after_cleanup("cannot calculate downloaded SHA-256", work, stage, check_path, origin_stage)
    end
    actual = hash_output[0:64]
    if not valid_hash(actual) or actual != expected:
        call fail_after_cleanup("SHA-256 mismatch for " + name, work, stage, check_path, origin_stage)
    end
    if run_clean(chmod_path, ["0644", "--", stage]) != 0:
        call fail_after_cleanup("cannot set safe library permissions", work, stage, check_path, origin_stage)
    end
    if run_clean(lsl_path, ["compile", stage, check_path]) != 0:
        call fail_after_cleanup("downloaded library does not compile", work, stage, check_path, origin_stage)
    end
    call remove_if_exists(check_path)
    call write_stage(origin_stage, provenance_text(name, server, source_url, expected), "cannot write package provenance staging file", work, stage, check_path, origin_stage)
    if run_clean(chmod_path, ["0644", "--", origin_stage]) != 0:
        call fail_after_cleanup("cannot set safe provenance permissions", work, stage, check_path, origin_stage)
    end
    lock = -1
    lock_failure = None
    try:
        lock = acquire_package_lock(directory, name)
    else:
        lock_failure = last_error()
    end
    if lock_failure != None:
        call cleanup_work(work, stage, check_path, origin_stage)
        Error(PackageError: lock_failure)
    end
    # Publish metadata first. If the source rename then fails, consumers keep
    # executing the previous verified source and `lsl origin` detects the
    # temporary mismatch instead of new code being paired with stale metadata.
    if run_clean(move_path, ["-f", "--", origin_stage, destination + ".origin"]) != 0:
        call release_package_lock(lock)
        call fail_after_cleanup("atomic provenance installation failed", work, stage, check_path, origin_stage)
    end
    if run_clean(move_path, ["-f", "--", stage, destination]) != 0:
        call release_package_lock(lock)
        call cleanup_work(work, stage, check_path, origin_stage)
        Error(PackageError: "provenance updated but library installation failed: " + name)
    end
    call release_package_lock(lock)
    call rmdir(work)
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
