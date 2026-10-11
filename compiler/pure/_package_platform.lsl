# Veřejné API; operace hostitele poskytuje modul vybraný cílem.

load package_linux_x86_64 as implementation

SYS_FLOCK = implementation.SYS_FLOCK
LOCK_EX = implementation.LOCK_EX
O_RDWR = implementation.O_RDWR
O_CREAT = implementation.O_CREAT
O_CLOEXEC = implementation.O_CLOEXEC
O_NOFOLLOW = implementation.O_NOFOLLOW
SYS_FSTAT = implementation.SYS_FSTAT
S_IFMT = implementation.S_IFMT
S_IFREG = implementation.S_IFREG

function valid_name(name):
    return implementation.valid_name(name)
end

function localhost_http(server):
    return implementation.localhost_http(server)
end

function normalize_server(server):
    return implementation.normalize_server(server)
end

function remove_if_exists(path):
    return implementation.remove_if_exists(path)
end

function cleanup_work(work, stage, check_path, origin_stage):
    return implementation.cleanup_work(work, stage, check_path, origin_stage)
end

function fail_after_cleanup(message, work, stage, check_path, origin_stage):
    return implementation.fail_after_cleanup(message, work, stage, check_path, origin_stage)
end

function write_stage(path, content, message, work, stage, check_path, origin_stage):
    return implementation.write_stage(path, content, message, work, stage, check_path, origin_stage)
end

function provenance_text(name, server, source_url, hash):
    return implementation.provenance_text(name, server, source_url, hash)
end

function parse_provenance(name, content):
    return implementation.parse_provenance(name, content)
end

function origin(name, home):
    return implementation.origin(name, home)
end

function acquire_package_lock(directory, name):
    return implementation.acquire_package_lock(directory, name)
end

function release_package_lock(handle):
    return implementation.release_package_lock(handle)
end

function verified_origin(name, home, sha256_path):
    return implementation.verified_origin(name, home, sha256_path)
end

function fetch(curl_path, server, url):
    return implementation.fetch(curl_path, server, url)
end

function valid_hash(value):
    return implementation.valid_hash(value)
end

function ensure_directory(path):
    return implementation.ensure_directory(path)
end

function user_path(home):
    return implementation.user_path(home)
end

function user_directory(home):
    return implementation.user_directory(home)
end

function work_directory(directory, name):
    return implementation.work_directory(directory, name)
end

function config_names(path):
    return implementation.config_names(path)
end

function install(name, home, server, curl_path, sha256_path, move_path, chmod_path, lsl_path):
    return implementation.install(name, home, server, curl_path, sha256_path, move_path, chmod_path, lsl_path)
end

function dependencies(source):
    return implementation.dependencies(source)
end

function install_graph(name, home, server, curl_path, sha256_path, move_path, chmod_path, lsl_path, active, completed):
    return implementation.install_graph(name, home, server, curl_path, sha256_path, move_path, chmod_path, lsl_path, active, completed)
end

function update(name, home, server, curl_path, sha256_path, move_path, chmod_path, lsl_path):
    return implementation.update(name, home, server, curl_path, sha256_path, move_path, chmod_path, lsl_path)
end

function install_config(path, home, server, curl_path, sha256_path, move_path, chmod_path, lsl_path):
    return implementation.install_config(path, home, server, curl_path, sha256_path, move_path, chmod_path, lsl_path)
end
