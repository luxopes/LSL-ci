# Stable-channel self-update client. Trust root is compiled into the ELF;
# neither environment variables nor downloaded keys can replace it.
load fd
load console
load json
load update_install

MANIFEST_URL = "https://lsl.lux-ai.cz/updates/channels/stable.json"
KEY_ID = "6930f9769efdaa1f62183875d540b340bab10f40060082f29eedd5dcead8231a"
PUBLIC_KEY = "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEA0wMrw+VLMcfb4IlJ/CF3rIOBY10enQ/SJxiFKcLtUpo=\n-----END PUBLIC KEY-----\n"
MAX_MANIFEST = 65536
MAX_ARCHIVE = 33554432
MAX_TAR = 67108864

function fail(message):
    Error(UpdateError: message)
end

function digits(text, maximum):
    if type(text) != "String" or len(text) < 1 or len(text) > 10:
        call fail("invalid decimal field")
    end
    result = 0
    for character in String(text):
        digit = ord(character) - 48
        if digit < 0 or digit > 9 or result > (__lsl_typed_int(maximum) - digit) // 10:
            call fail("decimal field outside supported range")
        end
        result = result * 10 + digit
    end
    return result
end

function version_parts(value):
    if type(value) != "String" or len(value) > 32:
        call fail("invalid release version")
    end
    parts = value.split(".")
    if len(parts) != 3:
        call fail("release version must be MAJOR.MINOR.PATCH")
    end
    result = []
    for part in parts:
        if len(part) > 1 and part[0] == "0":
            call fail("non-canonical release version")
        end
        result.append(digits(part, 999999999))
    end
    return result
end

function compare_versions(first, second):
    a = version_parts(first)
    b = version_parts(second)
    for index in rang(3):
        if a[index] < b[index]:
            return -1
        elif a[index] > b[index]:
            return 1
        end
    end
    return 0
end

function fields(value, expected):
    if type(value) != "Dictionary" or len(value) != len(expected):
        call fail("manifest object has an invalid schema")
    end
    for name in expected:
        if name not in value:
            call fail("manifest is missing field: " + name)
        end
    end
end

function hash_string(value):
    if type(value) != "String" or len(value) != 64:
        call fail("invalid SHA-256 field")
    end
    for character in String(value):
        if character not in "0123456789abcdef":
            call fail("invalid SHA-256 field")
        end
    end
end

function timestamp(value):
    # Publisher emits canonical UTC RFC3339. Reject other representations
    # rather than silently accepting an unvalidated date-time field.
    if type(value) != "String" or len(value) != 20:
        call fail("released_at must be UTC YYYY-MM-DDTHH:MM:SSZ")
    end
    if value[4] != "-" or value[7] != "-" or value[10] != "T" or value[13] != ":" or value[16] != ":" or value[19] != "Z":
        call fail("invalid release timestamp")
    end
    year = digits(value[0:4], 9999)
    month = digits(value[5:7], 12)
    day = digits(value[8:10], 31)
    call digits(value[11:13], 23)
    call digits(value[14:16], 59)
    call digits(value[17:19], 59)
    if year < 1970 or month < 1 or day < 1:
        call fail("invalid release date")
    end
    days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0):
        days[1] = 29
    end
    if day > days[month - 1]:
        call fail("invalid release day")
    end
end

function host_platform():
    data = __lsl_byte_zeros(390)
    if __lsl_syscall(63, __lsl_data_address(data), 0, 0, 0) < 0:
        call fail("cannot detect host platform")
    end
    if __lsl_text_from_bytes(data, 0, 5) != "Linux" or __lsl_text_from_bytes(data, 260, 6) != "x86_64" or data[266] != 0:
        call fail("self-update currently supports Linux x86_64 only")
    end
    return "x86_64"
end

function manifest_value(text, current, architecture, allow_downgrade):
    if __lsl_text_byte_length(String(text)) < 1 or __lsl_text_byte_length(String(text)) > MAX_MANIFEST:
        call fail("manifest size outside limit")
    end
    value = json.decode(text)
    call fields(value, ["schema", "product", "channel", "version", "released_at", "release_key_id", "artifacts"])
    if type(value["schema"]) != "Int" or value["schema"] != 1 or value["product"] != "lsl" or value["channel"] != "stable" or value["release_key_id"] != KEY_ID:
        call fail("untrusted manifest identity, channel or signing key ID")
    end
    call timestamp(value["released_at"])
    comparison = compare_versions(value["version"], current)
    if comparison < 0 and not allow_downgrade:
        call fail("release downgrade refused; developer override is --allow-downgrade")
    end
    artifacts = value["artifacts"]
    if type(artifacts) != "List" or len(artifacts) < 1 or len(artifacts) > 16:
        call fail("invalid artifact list")
    end
    selected = None
    seen = {}
    for artifact in artifacts:
        call fields(artifact, ["os", "architecture", "format", "url", "size", "sha256", "archive_root", "installer"])
        if artifact["os"] != "linux" or (artifact["architecture"] != "x86_64" and artifact["architecture"] != "aarch64") or artifact["format"] != "tar.gz":
            call fail("unsupported artifact platform or format")
        end
        arch = artifact["architecture"]
        if arch in seen:
            call fail("duplicate artifact platform")
        end
        seen[arch] = True
        version = value["version"]
        url = "https://lsl.lux-ai.cz/updates/releases/" + version + "/lsl-" + version + "-linux-" + arch + ".tar.gz"
        if artifact["url"] != url or artifact["archive_root"] != "lsl-" + version or artifact["installer"] != "bin/lsl-install":
            call fail("unsafe artifact URL or archive layout")
        end
        if type(artifact["size"]) != "Int" or artifact["size"] < 1 or artifact["size"] > MAX_ARCHIVE:
            call fail("archive size outside limit")
        end
        call hash_string(artifact["sha256"])
        if arch == architecture:
            selected = artifact
        end
    end
    if selected == None:
        call fail("release has no artifact for this platform")
    end
    return {"version": value["version"], "artifact": selected, "comparison": comparison}
end

function allowed_url(url):
    # Exact authority, no port, credentials, query, fragment, escapes, HTTP,
    # alternate trust roots or redirects (including same-domain redirects).
    if type(url) != "String" or not url.startswith("https://lsl.lux-ai.cz/updates/") or len(url) > 512:
        call fail("update URL must use the pinned production HTTPS origin")
    end
    suffix = url[len("https://lsl.lux-ai.cz/updates/"):len(url)]
    for character in suffix:
        if character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-":
            call fail("unsafe update URL character")
        end
    end
    for part in suffix.split("/"):
        if part == "." or part == ".." or part == "":
            call fail("non-canonical update URL")
        end
    end
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
    data = ByteArray(buffer)
    # Offset zero is a raw Int in the CLI's internal ABI, not public None.
    end_index = __lsl_typed_int(offset)
    while end_index < offset + width and data[end_index] != 0:
        if data[end_index] < 32 or data[end_index] > 126:
            call fail("non-ASCII tar header string")
        end
        end_index += 1
    end
    for index in rang(end_index, offset + width):
        if data[index] != 0:
            call fail("nonzero bytes after tar header NUL")
        end
    end
    return __lsl_text_from_bytes(data, offset, end_index - offset)
end

function tar_octal(buffer, offset, width):
    data = ByteArray(buffer)
    value = 0
    ended = False
    found = False
    for index in rang(offset, offset + width):
        byte = data[index]
        if byte == 0 or byte == 32:
            ended = True
        elif byte >= 48 and byte <= 55 and not ended:
            found = True
            value = value * 8 + byte - 48
        else:
            call fail("invalid tar octal field (base-256 is unsupported)")
        end
    end
    if not found:
        call fail("missing tar numeric field")
    end
    return value
end

function archive_path(name, root):
    if len(name) < 1 or len(name) > 240 or (name != root and not name.startswith(root + "/")):
        call fail("unexpected archive root")
    end
    for character in name:
        if character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-":
            call fail("unsafe archive path character")
        end
    end
    for part in name.split("/"):
        if part == "" or part == "." or part == "..":
            call fail("archive path traversal or ambiguous path")
        end
    end
end

function tar_entries(buffer, root):
    data = ByteArray(buffer)
    if len(data) < 1024 or len(data) > MAX_TAR or len(data) % 512 != 0:
        call fail("invalid expanded tar size")
    end
    entries = []
    seen = {}
    offset = 0
    terminated = False
    while offset + 512 <= len(data):
        if data[offset] == 0:
            if offset + 1024 > len(data):
                call fail("tar requires two terminating zero blocks")
            end
            index = offset
            while index < len(data):
                if data[index] != 0:
                    call fail("nonzero data after tar terminator")
                end
                index += 1
            end
            terminated = True
            break
        end
        checksum = 0
        for index in rang(512):
            if index >= 148 and index < 156:
                checksum += 32
            else:
                checksum += data[offset + index]
            end
        end
        if checksum != tar_octal(data, offset + 148, 8):
            call fail("tar header checksum mismatch")
        end
        magic = __lsl_text_from_bytes(data, offset + 257, 8)
        if magic != "ustar" + chr(0) + "00" and magic != "ustar  " + chr(0):
            call fail("only plain ustar/GNU tar archives are supported")
        end
        name = tar_string(data, offset, 100)
        if magic == "ustar" + chr(0) + "00":
            prefix = tar_string(data, offset + 345, 155)
            if prefix != "":
                name = prefix + "/" + name
            end
        else:
            for index in rang(offset + 345, offset + 512):
                if data[index] != 0:
                    call fail("GNU tar extensions are unsupported")
                end
            end
        end
        kind = data[offset + 156]
        if kind != 0 and kind != 48 and kind != 53:
            call fail("archive links, devices, FIFOs and extension records are forbidden")
        end
        if tar_string(data, offset + 157, 100) != "":
            call fail("unexpected tar link target")
        end
        if kind == 53 and name.endswith("/"):
            name = name[0:len(name) - 1]
        end
        call archive_path(name, root)
        if name in seen:
            call fail("duplicate archive path")
        end
        if name != root:
            parent = update_install.dirname(name)
            if parent not in seen or seen[parent] != 53:
                call fail("archive parent must be an earlier directory")
            end
        elif kind != 53:
            call fail("archive root must be a directory")
        end
        seen[name] = kind
        size = tar_octal(data, offset + 124, 12)
        mode = tar_octal(data, offset + 100, 8)
        if size > 16777216 or (kind == 53 and size != 0) or mode > 511:
            call fail("unsafe tar member size or permissions")
        end
        next_offset = offset + 512 + ((size + 511) // 512) * 512
        if next_offset > len(data):
            call fail("truncated tar member")
        end
        entries.append({"name": name, "kind": kind, "offset": offset + 512, "size": size, "mode": mode})
        if len(entries) > 4096:
            call fail("too many archive members")
        end
        offset = next_offset
    end
    if not terminated or root not in seen:
        call fail("tar lacks root or terminator")
    end
    return entries
end

function installer_entry(buffer, entries, root):
    data = ByteArray(buffer)
    for entry in entries:
        if entry["name"] == root + "/bin/lsl-install":
            start = entry["offset"]
            if entry["kind"] == 53 or entry["size"] < 176 or (entry["mode"] & 73) == 0:
                call fail("expected installer is not an executable regular file")
            end
            if data[start] != 127 or __lsl_text_from_bytes(data, start + 1, 3) != "ELF" or data[start + 4] != 2 or data[start + 5] != 1 or update_install.little(data, start + 16, 2) != 3 or update_install.little(data, start + 18, 2) != 62:
                call fail("expected installer is not a Linux x86_64 PIE ELF")
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
            if __lsl_syscall(90, __lsl_data_address(encoded), mode, 0, 0) != 0:
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
    call console.heading("Downloading verified LSL " + manifest["version"] + " for Linux x86_64.")
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
