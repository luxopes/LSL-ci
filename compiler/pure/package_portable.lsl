# Knihovny z registru na Windows a macOS zatím nejsou. Rozhraní
# package_linux_x86_64.lsl; operace hlásí srozumitelnou chybu.
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
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function localhost_http(server):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function normalize_server(server):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
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
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function ensure_directory(path):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
end

function user_path(home):
    Error(PackageError: "registry libraries are not available on Windows and macOS yet")
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
