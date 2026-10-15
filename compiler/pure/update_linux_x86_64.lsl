load _platform as platform
# Stable-channel self-update client. Trust root is compiled into the ELF;
# neither environment variables nor downloaded keys can replace it.
load fd
load console
load json
load update_install
load update_manifest as manifest

MANIFEST_URL = manifest.MANIFEST_URL
KEY_ID = manifest.KEY_ID
PUBLIC_KEY = manifest.PUBLIC_KEY
MAX_MANIFEST = manifest.MAX_MANIFEST
MAX_ARCHIVE = manifest.MAX_ARCHIVE
MAX_TAR = manifest.MAX_TAR

function fail(message):
    Error(UpdateError: message)
end

function digits(text, maximum):
    return manifest.digits(text, maximum)
end

function version_parts(value):
    return manifest.version_parts(value)
end

function compare_versions(first, second):
    return manifest.compare_versions(first, second)
end

function fields(value, expected):
    return manifest.fields(value, expected)
end

function hash_string(value):
    return manifest.hash_string(value)
end

function timestamp(value):
    return manifest.timestamp(value)
end

# Architektura balíku podle platformy, pro kterou je tento program přeložený
# (jméno stroje z uname a v URL archivu).
function release_architecture():
    if platform.NAME == "linux-arm64":
        return "aarch64"
    elif platform.NAME == "linux-riscv64":
        return "riscv64"
    end
    return "x86_64"
end

function host_platform():
    data = __lsl_byte_zeros(platform.UTSNAME_BYTES)
    if __lsl_syscall(platform.SYS_UNAME, __lsl_data_address(data), 0, 0, 0) < 0:
        call fail("cannot detect host platform")
    end
    architecture = release_architecture()
    width = __lsl_text_byte_length(architecture)
    if __lsl_text_from_bytes(data, platform.UTSNAME_SYSNAME, 5) != "Linux" or __lsl_text_from_bytes(data, platform.UTSNAME_MACHINE, width) != architecture or data[platform.UTSNAME_MACHINE + width] != 0:
        call fail("self-update supports Linux x86_64, aarch64 and riscv64 with the matching LSL build")
    end
    return architecture
end

function manifest_value(text, current, architecture, allow_downgrade):
    return manifest.manifest_value(text, current, "linux", architecture, allow_downgrade)
end

function allowed_url(url):
    return manifest.allowed_url(url)
end

function download(url, path, maximum):
    call allowed_url(url)
    arguments = ["-q", "--fail", "--silent", "--show-error", "--globoff", "--proto", "=https", "--proto-redir", "=https", "--tlsv1.2", "--max-redirs", "0", "--connect-timeout", "15", "--max-time", "120", "--max-filesize", String(maximum), "--output", path, "--write-out", "%{http_code}", "--url", url]
    output = update_install.bounded(update_install.tool("curl"), arguments, maximum, 125)
    if output != "200":
        call fail("update server must return HTTP 200 without redirection")
    end
    info = update_install.metadata(path)
    if info == None or info["size"] < 1 or info["size"] > maximum:
        call fail("download size outside limit")
    end
end

# Download with an in-place percentage: curl streams the body to stdout and
# reports the HTTP status on stderr; every chunk is appended to `path`.
DOWNLOAD = {"path": "", "received": 0, "expected": 0, "shown": -1}

function download_chunk(chunk):
    progress = DOWNLOAD
    call appendfile(progress["path"], chunk)
    progress["received"] += __lsl_text_byte_length(String(chunk))
    percent = min(100, progress["received"] * 100 // max(1, progress["expected"]))
    if percent != progress["shown"]:
        progress["shown"] = percent
        call update_install.show_progress("Downloading", percent)
    end
    return None
end

function download_progress(url, path, expected):
    call allowed_url(url)
    progress = DOWNLOAD
    progress["path"] = path
    progress["received"] = 0
    progress["expected"] = expected
    progress["shown"] = -1
    call writefile(path, "")
    arguments = ["-q", "--fail", "--silent", "--show-error", "--globoff", "--proto", "=https", "--proto-redir", "=https", "--tlsv1.2", "--max-redirs", "0", "--connect-timeout", "15", "--max-time", "120", "--max-filesize", String(expected), "--output", "-", "--write-out", "%{stderr}%{http_code}", "--url", url]
    stderr = update_install.bounded_stream(update_install.tool("curl"), arguments, expected, 125, download_chunk)
    if stderr.strip() != "200":
        call fail("update server must return HTTP 200 without redirection")
    end
    info = update_install.metadata(path)
    if info == None or info["size"] < 1 or info["size"] > expected:
        call fail("download size outside limit")
    end
end

function verify_signature(work):
    info = update_install.metadata(work + "/manifest.sig")
    if info == None or info["size"] != 64:
        call fail("Ed25519 signature must contain exactly 64 raw bytes")
    end
    info = update_install.metadata(work + "/manifest.json")
    if info == None or info["size"] < 1 or info["size"] > MAX_MANIFEST:
        call fail("manifest size outside limit")
    end
    call writefile(work + "/public.pem", PUBLIC_KEY)
    # -rawin verifies Ed25519 over the original bytes, not parsed/re-encoded JSON.
    call update_install.bounded(update_install.tool("openssl"), ["pkeyutl", "-verify", "-pubin", "-inkey", work + "/public.pem", "-rawin", "-in", work + "/manifest.json", "-sigfile", work + "/manifest.sig"], MAX_MANIFEST, 30)
end

function verified_manifest(work, current, architecture, allow_downgrade):
    call verify_signature(work)
    return manifest_value(fd.read_text_limit(work + "/manifest.json", MAX_MANIFEST), current, architecture, allow_downgrade)
end

function verify_archive(path, artifact):
    info = update_install.metadata(path)
    if info == None or info["size"] != artifact["size"] or info["size"] > MAX_ARCHIVE:
        call fail("archive size differs from signed manifest")
    end
    output = update_install.bounded(update_install.tool("sha256sum"), ["--", path], 1048576, 30)
    if len(output) < 64 or output[0:64] != artifact["sha256"]:
        call fail("archive SHA-256 differs from signed manifest")
    end
end

function tar_string(buffer, offset, width):
    return manifest.tar_string(buffer, offset, width)
end

function tar_octal(buffer, offset, width):
    return manifest.tar_octal(buffer, offset, width)
end

function archive_path(name, root):
    return manifest.archive_path(name, root)
end

function tar_entries(buffer, root):
    return manifest.tar_entries(buffer, root)
end

function installer_entry(buffer, entries, root):
    data = ByteArray(buffer)
    for entry in entries:
        if entry["name"] == root + "/bin/lsl-install":
            start = entry["offset"]
            if entry["kind"] == 53 or entry["size"] < 176 or (entry["mode"] & 73) == 0:
                call fail("expected installer is not an executable regular file")
            end
            if data[start] != 127 or __lsl_text_from_bytes(data, start + 1, 3) != "ELF" or data[start + 4] != 2 or data[start + 5] != 1 or update_install.little(data, start + 16, 2) != 3 or update_install.little(data, start + 18, 2) != platform.ELF_MACHINE:
                call fail("expected installer is not a Linux PIE ELF for this architecture")
            end
            return entry
        end
    end
    call fail("archive is missing bin/lsl-install")
end

function extract_archive(work, artifact):
    archive = work + "/release.tar.gz"
    call verify_archive(archive, artifact)
    call update_install.bounded(update_install.tool("gzip"), ["-d", "-k", "-n", "--", archive], MAX_TAR, 60)
    data = fd.read_all_limit(work + "/release.tar", MAX_TAR)
    root = artifact["archive_root"]
    entries = tar_entries(data, root)
    call installer_entry(data, entries, root)
    # No writes happen until ALL headers and the expected installer pass.
    for entry in entries:
        path = work + "/" + entry["name"]
        if entry["kind"] == 53:
            if __lsl_mkdir_private(path) != 0:
                call fail("cannot create archive directory")
            end
        else:
            size = __lsl_typed_int(entry["size"])
            contents = __lsl_byte_zeros(size)
            call __lsl_byte_copy(contents, data, 0, entry["offset"], size)
            call writebytes(path, contents)
            mode = 420
            if (entry["mode"] & 73) != 0:
                mode = 493
            end
            encoded = update_install.cstring(path)
            if __lsl_syscall(platform.SYS_FCHMODAT, platform.AT_FDCWD, __lsl_data_address(encoded), mode, 0) != 0:
                call fail("cannot set safe archive permissions")
            end
        end
        gc()
    end
    return work + "/" + root + "/bin/lsl-install"
end

function options():
    result = {"check": False, "rollback": False, "system": False, "allow-downgrade": False}
    for index in rang(2, arg_count()):
        argument = arg(index)
        if not String(argument).startswith("--") or argument[2:len(argument)] not in result:
            call fail("unknown self-update option: " + String(argument))
        end
        key = argument[2:len(argument)]
        if result[key]:
            call fail("duplicate self-update option")
        end
        result[key] = True
    end
    if (result["check"] and result["rollback"]) or (result["rollback"] and result["allow-downgrade"]):
        call fail("incompatible self-update options")
    end
    return result
end

function execute(current, settings, work, prefix):
    if prefix != None:
        store = prefix + "/lib/lsl-updates"
        call update_install.recover(store, work)
        if settings["rollback"]:
            call update_install.rollback(store, work)
            return None
        end
        if update_install.metadata(store + "/current") != None:
            active = update_install.target(store, "current")
            # Compare against the active generation under lock, not a stale
            # process that another updater has already replaced.
            active_version = fd.read_text_limit(active + "/version", 64).strip()
            if current != active_version:
                call fail("active LSL version changed; rerun the active lsl update")
            end
        end
    end
    call download(MANIFEST_URL, work + "/manifest.json", MAX_MANIFEST)
    call download(MANIFEST_URL + ".sig", work + "/manifest.sig", 64)
    manifest = verified_manifest(work, current, host_platform(), settings["allow-downgrade"])
    if manifest["comparison"] == 0:
        call console.success("LSL " + current + " is up to date.")
        return None
    elif settings["check"]:
        call console.heading("LSL " + manifest["version"] + " is available (installed " + current + ").")
        return None
    end
    if prefix == None:
        call fail("installation prefix is required for an update; use --check for a download-free check")
    end
    store = prefix + "/lib/lsl-updates"
    artifact = manifest["artifact"]
    call console.heading("Downloading verified LSL " + manifest["version"] + " for Linux " + release_architecture() + ".")
    call download_progress(artifact["url"], work + "/release.tar.gz", artifact["size"])
    installer = extract_archive(work, artifact)
    generation = update_install.private_work(store + "/generations")
    call update_install.install_stage(installer, generation, manifest["version"], work)
    call update_install.prepare(prefix, executable_path(), current, work)
    call update_install.activate(store, generation, manifest["version"], work)
    call console.success("Updated LSL " + current + " -> " + manifest["version"] + ". Previous version retained; use lsl update --rollback.")
end

function main(current):
    settings = options()
    prefix = None
    handle = -1
    if settings["check"]:
        work = update_install.private_work("/tmp")
    else:
        prefix = update_install.installation(executable_path(), __lsl_getenv("HOME"), settings["system"])
        store = prefix + "/lib/lsl-updates"
        call update_install.directory(store)
        call update_install.directory(store + "/generations")
        call update_install.public_directory(store)
        call update_install.public_directory(store + "/generations")
        handle = update_install.lock(store)
        work = update_install.private_work(store)
    end
    failure = None
    try:
        call execute(current, settings, work, prefix)
    else:
        failure = last_error()
    end
    cleanup_failure = None
    try:
        call update_install.cleanup_scratch(work)
    else:
        cleanup_failure = last_error()
    end
    if handle >= 0:
        call fd.close(handle)
    end
    if cleanup_failure != None:
        print "Could not remove private update scratch: " + work
    end
    if failure != None:
        call fail(String(failure))
    elif cleanup_failure != None:
        call fail(String(cleanup_failure))
    end
end
