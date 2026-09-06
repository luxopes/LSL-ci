# Filesystem transaction for the signed updater. Only the caller's private
# staging tree and the LSL-owned deployment store are written. No shell.
load fd

TOOLS = ["lsl", "lslc", "lsl-configure", "lsl-test", "lsl-install"]

function fail(message):
    Error(UpdateError: message)
end

function cstring(value):
    text = String(value)
    call fd.checked_path(text)
    result = __lsl_byte_zeros(__lsl_text_byte_length(text) + 1)
    index = 0
    while index < len(result) - 1:
        result[index] = __lsl_text_byte(text, index)
        index += 1
    end
    return result
end

function little(buffer, offset, width):
    data = ByteArray(buffer)
    value = 0
    index = __lsl_typed_int(width) - 1
    while index >= 0:
        value = value * 256 + data[offset + index]
        index -= 1
    end
    return value
end

function dirname(path):
    parts = String(path).split("/")
    return "/".join(parts[0:len(parts) - 1])
end

function metadata(path):
    encoded = cstring(path)
    data = __lsl_byte_zeros(144)
    status = __lsl_syscall(6, __lsl_data_address(encoded), __lsl_data_address(data), 0, 0)
    if status == -2:
        return None
    elif status < 0:
        call fail("cannot inspect path: " + path)
    end
    return {"mode": little(data, 24, 4), "uid": little(data, 28, 4), "size": little(data, 48, 8), "links": little(data, 16, 8)}
end

function owned_directory(path):
    info = metadata(path)
    uid = __lsl_syscall(107, 0, 0, 0, 0)
    if info == None or (info["mode"] & 61440) != 16384 or info["uid"] != uid or (info["mode"] & 18) != 0:
        call fail("directory must be owned by the invoking user, not writable by others, and not a symlink: " + path)
    end
end

function directory(path):
    if metadata(path) == None:
        if __lsl_mkdir_private(path) != 0:
            call fail("cannot create private directory: " + path)
        end
    end
    call owned_directory(path)
end

function public_directory(path):
    call owned_directory(path)
    encoded = cstring(path)
    if __lsl_syscall(90, __lsl_data_address(encoded), 493, 0, 0) < 0:
        call fail("cannot make deployment directory accessible: " + path)
    end
end

function private_work(parent):
    pid = String(__lsl_syscall(39, 0, 0, 0, 0))
    for attempt in rang(128):
        path = parent + "/g-" + pid + "-" + String(attempt)
        if __lsl_mkdir_private(path) == 0:
            return path
        end
    end
    call fail("cannot create private update staging directory")
end

function sync_path(path):
    handle = fd.open(path, 524288)
    status = __lsl_syscall(74, handle, 0, 0, 0)
    call fd.close(handle)
    if status < 0:
        call fail("fsync failed: " + path)
    end
end

function rename(source, destination):
    first = cstring(source)
    second = cstring(destination)
    if __lsl_syscall(82, __lsl_data_address(first), __lsl_data_address(second), 0, 0) < 0:
        call fail("atomic rename failed: " + destination)
    end
end

function link(target, destination):
    first = cstring(target)
    second = cstring(destination)
    if __lsl_syscall(88, __lsl_data_address(first), __lsl_data_address(second), 0, 0) < 0:
        call fail("cannot create deployment link: " + destination)
    end
end

function read_link(path):
    encoded = cstring(path)
    buffer = __lsl_byte_zeros(4096)
    count = __lsl_syscall(89, __lsl_data_address(encoded), __lsl_data_address(buffer), 4096, 0)
    if count < 1 or count >= 4096:
        call fail("invalid deployment link: " + path)
    end
    return __lsl_text_from_bytes(buffer, 0, count)
end

function switch_link(target, destination, scratch):
    # scratch is in a private directory on the same filesystem. rename(2)
    # replaces the symlink itself, never follows the destination.
    call link(target, scratch)
    call rename(scratch, destination)
    call sync_path(dirname(destination))
end

function tool(name):
    for prefix in ["/usr/bin/", "/bin/"]:
        if exists(prefix + name):
            return prefix + name
        end
    end
    call fail("required system tool is missing: " + name)
end

function bounded(executable, arguments, maximum, seconds):
    # Empty environment blocks LD_*, CURL_*, OPENSSL_*, proxy and config
    # injection. Kernel RLIMIT_FSIZE bounds unknown-length downloads and gzip
    # output even on curl versions whose max-filesize only checks headers.
    limits = ["--signal=TERM", "--kill-after=2s", "--", String(seconds) + "s", tool("prlimit"), "--as=1073741824", "--cpu=" + String(seconds), "--fsize=" + String(maximum), "--core=0", "--nofile=64", "--", executable]
    limits.extend(arguments)
    output = capture_clean(tool("timeout"), limits)
    status = capture_status()
    if status != 0:
        call fail("tool failed (" + String(status) + "): " + executable + ": " + capture_stderr().strip())
    end
    return output
end

function lock(store):
    path = cstring(store + "/lock")
    handle = __lsl_syscall(2, __lsl_data_address(path), 2 + 64 + 524288 + 131072, 384, 0)
    if handle < 0:
        call fail("cannot open updater lock")
    end
    info = __lsl_byte_zeros(144)
    status = __lsl_syscall(5, handle, __lsl_data_address(info), 0, 0)
    if status < 0 or (little(info, 24, 4) & 61440) != 32768 or little(info, 16, 8) != 1 or little(info, 28, 4) != __lsl_syscall(107, 0, 0, 0, 0) or (little(info, 24, 4) & 18) != 0:
        call fd.close(handle)
        call fail("unsafe updater lock")
    end
    if __lsl_syscall(73, handle, 2 + 4, 0, 0) < 0:
        call fd.close(handle)
        call fail("another LSL update is running")
    end
    return handle
end

function canonical(path):
    call fd.checked_path(path)
    if not String(path).startswith("/") or path == "/" or len(path) > 2048:
        call fail("installation path must be a canonical absolute path")
    end
    pieces = String(path).split("/")
    for piece in pieces[1:len(pieces)]:
        if piece == "" or piece == "." or piece == "..":
            call fail("non-canonical installation path")
        end
    end
    for character in String(path):
        if ord(character) < 32 or ord(character) == 127:
            call fail("control character in installation path")
        end
    end
end

function installation(executable, home, system):
    call canonical(executable)
    prefix = dirname(dirname(executable))
    marker = "/lib/lsl-updates/generations/"
    position = prefix.find(marker)
    if position >= 0:
        prefix = prefix[0:position]
    end
    if prefix == "/usr/local":
        if not system or __lsl_syscall(107, 0, 0, 0, 0) != 0:
            call fail("system installation requires explicit administrator invocation: sudo /usr/local/bin/lsl update --system")
        end
    elif home == None or prefix != String(home) + "/.local" or system:
        call fail("self-update supports the active ~/.local or /usr/local installation only; a source checkout is never overwritten")
    end
    if position < 0 and executable != prefix + "/bin/lsl":
        call fail("self-update requires the active prefix/bin/lsl executable")
    elif position >= 0:
        active = target(prefix + "/lib/lsl-updates", "current")
        if executable != active + "/bin/lsl":
            call fail("self-update cannot run from an inactive generation")
        end
    end
    call canonical(prefix)
    # Check every ancestor (root-owned ancestors are allowed). No symlink
    # prefix or group/other writer can redirect a privileged transaction.
    current = ""
    for piece in prefix.split("/")[1:len(prefix.split("/"))]:
        current += "/" + piece
        info = metadata(current)
        if info == None or (info["mode"] & 61440) != 16384 or (info["mode"] & 18) != 0 or (info["uid"] != 0 and info["uid"] != __lsl_syscall(107, 0, 0, 0, 0)):
            call fail("unsafe installation ancestor: " + current)
        end
    end
    call owned_directory(prefix)
    call owned_directory(prefix + "/bin")
    call owned_directory(prefix + "/lib")
    return prefix
end

function target(store, name):
    value = read_link(store + "/" + name)
    base = store + "/generations/"
    if not value.startswith(base) or value[len(base):len(value)].find("/") >= 0 or not value[len(base):len(value)].startswith("g-"):
        call fail("deployment link escapes generation store")
    end
    call canonical(value)
    call owned_directory(value)
    return value
end

function health(generation, expected, scratch):
    output = bounded(generation + "/bin/lsl", ["version"], 16777216, 30)
    if output != expected + chr(10):
        call fail("installed CLI version differs from signed manifest")
    end
    # Also exercise compiler + trusted resources, not just the version string.
    call writefile(scratch + "/probe.lsl", "load json" + chr(10) + "print json.encode({\"ok\": True})" + chr(10))
    if metadata(scratch + "/probe") != None and unlink(scratch + "/probe") != 0:
        call fail("cannot remove previous compiler probe")
    end
    call bounded(generation + "/bin/lsl", ["compile", scratch + "/probe.lsl", scratch + "/probe"], 16777216, 60)
    output = bounded(scratch + "/probe", [], 1048576, 10)
    if output != "{\"ok\":true}" + chr(10):
        call fail("installed compiler smoke test failed")
    end
end

function install_stage(installer, generation, version, scratch):
    # The signed installer's ordinary 0755/0644 modes must also work for
    # system users when the administrator's personal umask is 077.
    previous_mask = __lsl_syscall(95, 18, 0, 0, 0)
    install_failure = None
    try:
        call bounded(installer, [generation], 16777216, 120)
    else:
        install_failure = last_error()
    end
    call __lsl_syscall(95, previous_mask, 0, 0, 0)
    if install_failure != None:
        call fail(String(install_failure))
    end
    for name in TOOLS:
        info = metadata(generation + "/bin/" + name)
        if info == None or (info["mode"] & 61440) != 32768 or (info["mode"] & 73) == 0:
            call fail("installer omitted expected executable: " + name)
        end
    end
    call health(generation, version, scratch)
    call writefile(generation + "/version", version + chr(10))
    call public_directory(generation)
    # syncfs flushes all new files before any activation pointer is published.
    handle = fd.open(generation, 524288 + 65536)
    status = __lsl_syscall(306, handle, 0, 0, 0)
    call fd.close(handle)
    if status < 0:
        call fail("cannot flush staged installation")
    end
end

function prepare(prefix, executable, version, scratch):
    store = prefix + "/lib/lsl-updates"
    if metadata(store + "/current") == None:
        old = private_work(store + "/generations")
        call install_stage(dirname(executable) + "/lsl-install", old, version, scratch)
        call switch_link(old, store + "/current", scratch + "/current-link")
    end
    old = target(store, "current")
    # Migration may be interrupted after any link. Every converted entry still
    # points to the OLD snapshot until the single current link is switched.
    names = TOOLS + ["lsl-cuda-worker"]
    for name in names:
        destination = prefix + "/bin/" + name
        expected = store + "/current/bin/" + name
        info = metadata(destination)
        if info != None and (info["mode"] & 61440) == 40960:
            if read_link(destination) != expected:
                call fail("refusing to replace unrelated executable link: " + destination)
            end
        elif info != None and (info["mode"] & 61440) == 32768 and info["uid"] == __lsl_syscall(107, 0, 0, 0, 0) and (info["mode"] & 18) == 0:
            call switch_link(expected, destination, scratch + "/entry-link")
        elif info == None and name == "lsl-cuda-worker":
            call switch_link(expected, destination, scratch + "/entry-link")
        else:
            call fail("unsafe or missing installation entry: " + destination)
        end
    end
    return old
end

function recover(store, scratch):
    if metadata(store + "/pending") != None:
        old = target(store, "previous")
        call switch_link(old, store + "/current", scratch + "/recover-link")
        if unlink(store + "/pending") != 0:
            call fail("cannot clear recovered transaction")
        end
        call sync_path(store)
        print "Recovered previous LSL installation after an interrupted update."
    end
end

function activate(store, generation, version, scratch):
    old = target(store, "current")
    call switch_link(old, store + "/previous", scratch + "/previous-link")
    call writefile(store + "/pending", "rollback to previous on interruption" + chr(10))
    call sync_path(store + "/pending")
    call sync_path(store)
    failure = None
    try:
        call switch_link(generation, store + "/current", scratch + "/activate-link")
        call health(store + "/current", version, scratch)
    else:
        failure = last_error()
    end
    if failure != None:
        call switch_link(old, store + "/current", scratch + "/rollback-link")
    end
    if unlink(store + "/pending") != 0:
        call fail("cannot clear transaction journal; next update will restore previous")
    end
    call sync_path(store)
    if failure != None:
        call fail("update rolled back: " + String(failure))
    end
end

function rollback(store, scratch):
    previous = target(store, "previous")
    version = fd.read_text_limit(previous + "/version", 64).strip()
    call health(previous, version, scratch)
    call activate(store, previous, version, scratch)
    print "Rolled back to LSL " + version
end

function cleanup_scratch(path):
    # The caller passes only an atomically created, private g-PID-N directory.
    # No generation (including a failed one) is ever removed automatically.
    call canonical(path)
    if not String(path).split("/")[len(String(path).split("/")) - 1].startswith("g-"):
        call fail("invalid scratch cleanup target")
    end
    call owned_directory(path)
    call bounded(tool("rm"), ["-r", "-f", "--", path], 1048576, 30)
end
