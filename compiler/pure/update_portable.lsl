# Self-update na Windows a macOS. Kořen důvěry (klíč Ed25519) je
# zakompilovaný v programu; podpis manifestu i SHA-256 archivu ověřuje LSL
# (release_crypto.lsl), ze systému se používá jen curl a tar
# (Windows 10 1803+: %SystemRoot%\System32\curl.exe a tar.exe, macOS
# /usr/bin/curl, /usr/bin/tar a /usr/bin/gzip).
#
# Instalace z lsl-install (značka lib/lsl/INSTALLATION):
#   PREFIX/bin/...                    aktivní nástroje
#   PREFIX/lib/lsl                    aktivní knihovna
#   PREFIX/lib/lsl-updates/lock       zámek (adresář vytvořený atomicky)
#   PREFIX/lib/lsl-updates/incoming   nová verze z jejího lsl-install
#   PREFIX/lib/lsl-updates/outgoing   stará verze během výměny
#   PREFIX/lib/lsl-updates/previous   předchozí verze pro --rollback
#   PREFIX/lib/lsl-updates/journal    existuje jen během výměny
# Výměna přesouvá položky přejmenováním v rámci svazku (Windows dovolí
# přesunout i spuštěný .exe). Přerušenou výměnu vrátí recover() při dalším
# spuštění; nová verze se aktivuje jen po kontrole verze a překladu.
load _platform as platform
load console
load update_manifest as manifest
load release_crypto as crypto

MANIFEST_URL = manifest.MANIFEST_URL
KEY_ID = manifest.KEY_ID
PUBLIC_KEY = manifest.PUBLIC_KEY
MAX_MANIFEST = manifest.MAX_MANIFEST
MAX_ARCHIVE = manifest.MAX_WINDOWS_ARCHIVE
MAX_TAR = manifest.MAX_TAR
DOWNLOAD = {"path": "", "received": 0, "expected": 0, "shown": -1}
MARKER = "INSTALLATION"
UNIQUE = {"counter": 0}

function fail(message):
    Error(UpdateError: message)
end

# Znovu vyhodí zachycenou chybu bez zdvojeného "UpdateError: ".
function reraise(failure):
    text = String(failure)
    if text.startswith("UpdateError: "):
        text = text[13:len(text)]
    end
    call fail(text)
end

function windows():
    return platform.NAME.startswith("windows-")
end

# [systém, architektura] podle platformy, pro kterou je program přeložený
# (jména jako v názvech archivů vydání).
function host_target():
    if platform.NAME == "windows-x86_64":
        return ["windows", "x86_64"]
    elif platform.NAME == "windows-arm64":
        return ["windows", "arm64"]
    elif platform.NAME == "macos-arm64":
        return ["macos", "arm64"]
    elif platform.NAME == "macos-x86_64":
        return ["macos", "x86_64"]
    end
    call fail("self-update is not available for " + platform.NAME)
end

function system_title(system):
    if system == "windows":
        return "Windows"
    end
    return "macOS"
end

function host_platform():
    return host_target()[1]
end

function executable_name(name):
    if windows():
        return name + ".exe"
    end
    return name
end

# Spravované položky bin/ (balík pro Windows nese i LLVM).
function binary_names():
    names = []
    for name in ["lsl", "lslc", "luxir", "lsl-install", "lsl-configure", "lsl-test"]:
        names.append(executable_name(name))
    end
    if windows():
        names.extend(["llvm-mc.exe", "lld.exe"])
    end
    return names
end

function normalized(path):
    return String(path).replace(chr(92), "/")
end

function dirname(path):
    text = String(path)
    slash = -1
    index = 0
    while index < len(text):
        if text[index] == "/":
            slash = index
        end
        index += 1
    end
    if slash < 0:
        return "."
    elif slash == 0:
        return "/"
    elif slash == 2 and text[1] == ":":
        return text[0:3]
    end
    return text[0:slash]
end

function basename(path):
    parts = String(path).split("/")
    return parts[len(parts) - 1]
end

# Systémový nástroj podle absolutní cesty (žádné hledání v PATH).
function system_tool(name):
    if windows():
        root = __lsl_getenv("SystemRoot")
        if root == None or root == "":
            root = "C:/Windows"
        end
        path = normalized(root) + "/System32/" + name + ".exe"
    else:
        path = "/usr/bin/" + name
    end
    if not exists(path):
        call fail("required system tool is missing: " + path)
    end
    return path
end

# Spustí nástroj v čistém prostředí s časovým limitem; vrátí stdout.
function tool_run(executable, arguments, seconds):
    output = __lsl_capture_input_timeout(String(executable), arguments, "", seconds)
    status = capture_status()
    if status != 0:
        detail = capture_stderr().strip()
        if len(detail) > 400:
            detail = detail[0:400]
        end
        call fail("tool failed (" + String(status) + "): " + basename(executable) + ": " + detail)
    end
    return output
end

# Nástroje ověřené verze LSL (instalátor, lsl, testovací program) běží
# s prostředím uživatele: překladač potřebuje TEMP/TMPDIR a nástroje Xcode.
function own_run(executable, arguments):
    output = capture(String(executable), arguments)
    status = capture_status()
    if status != 0:
        detail = (capture_stderr() + output).strip()
        if len(detail) > 400:
            detail = detail[0:400]
        end
        call fail(basename(executable) + " failed (" + String(status) + "): " + detail)
    end
    return output
end

function make_directories(path):
    if exists(path):
        return None
    end
    parent = dirname(path)
    if parent != path and parent != "." and not exists(parent):
        call make_directories(parent)
    end
    if mkdir(path) != 0 and not exists(path):
        call fail("cannot create directory: " + path)
    end
end

# Nový soukromý adresář parent/prefix-N (atomicky přes mkdir).
function unique_directory(parent, prefix):
    for attempt in rang(128):
        UNIQUE["counter"] += 1
        path = parent + "/" + prefix + String(Int(monotonic() * 1000000.0)) + "-" + String(UNIQUE["counter"])
        if __lsl_mkdir_private(path) == 0:
            return path
        end
    end
    call fail("cannot create private update directory in " + parent)
end

function move(source, destination):
    if __lsl_rename(source, destination) != 0:
        call fail("cannot move " + source + " to " + destination)
    end
end

# Smaže strom, který updater sám vytvořil. Nejdřív zkusí soubor: unlink na
# symlinku odstraní odkaz, ne cíl. Stromy pocházejí z ověřeného archivu a
# z lsl-install, odkazy ani junction v nich nejsou.
function remove_tree(path):
    if unlink(path) == 0:
        return None
    end
    names = []
    try:
        names = __lsl_list_directory(String(path))
    else:
        if not exists(path):
            return None
        end
        call fail("cannot remove " + path)
    end
    for name in names:
        call remove_tree(path + "/" + name)
    end
    if rmdir(path) != 0:
        call fail("cannot remove " + path)
    end
end

function remove_quietly(path):
    try:
        call remove_tree(path)
    else:
        print "Could not remove " + path + " (remove it later)."
    end
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

function manifest_value(text, current, architecture, allow_downgrade):
    return manifest.manifest_value(text, current, host_target()[0], architecture, allow_downgrade)
end

function allowed_url(url):
    return manifest.allowed_url(url)
end

function download(url, path, maximum):
    call allowed_url(url)
    arguments = ["-q", "--fail", "--silent", "--show-error", "--globoff", "--proto", "=https", "--proto-redir", "=https", "--tlsv1.2", "--max-redirs", "0", "--connect-timeout", "15", "--max-time", "300", "--max-filesize", String(maximum), "--output", path, "--write-out", "%{http_code}", "--url", url]
    output = tool_run(system_tool("curl"), arguments, 330)
    if output.strip() != "200":
        call fail("update server must return HTTP 200 without redirection")
    end
    if not exists(path):
        call fail("download failed: " + url)
    end
end

function download_chunk(chunk):
    return None
end

function download_progress(url, path, expected):
    return download(url, path, expected)
end

function verify_signature(work):
    signature = readbytes(work + "/manifest.sig")
    if len(signature) != 64:
        call fail("Ed25519 signature must contain exactly 64 raw bytes")
    end
    data = readbytes(work + "/manifest.json")
    if len(data) < 1 or len(data) > MAX_MANIFEST:
        call fail("manifest size outside limit")
    end
    if not crypto.ed25519_verify(signature, data, crypto.hex_bytes(manifest.PUBLIC_KEY_RAW)):
        call fail("manifest signature is not valid for the LSL release key")
    end
    return data
end

function verified_manifest(work, current, architecture, allow_downgrade):
    data = verify_signature(work)
    # Parsuje se přesně ověřený obsah, ne znovu načtený soubor.
    return manifest_value(__lsl_text_from_bytes(data, 0, len(data)), current, architecture, allow_downgrade)
end

function verify_archive(path, artifact):
    data = readbytes(path)
    if len(data) != artifact["size"]:
        call fail("archive size differs from signed manifest")
    end
    if crypto.sha256_hex(data) != artifact["sha256"]:
        call fail("archive SHA-256 differs from signed manifest")
    end
    return data
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

# Jména položek ZIP z centrálního adresáře (bez rozbalování): jen soubory
# a adresáře pod kořenem, metody stored/deflate, bez šifrování a odkazů.
function zip_entries(buffer, root):
    data = ByteArray(buffer)
    size = len(data)
    if size < 22:
        call fail("archive is not a ZIP file")
    end
    end_record = -1
    position = size - 22
    lowest = max(0, size - 22 - 65535)
    while position >= lowest:
        if data[position] == 80 and data[position + 1] == 75 and data[position + 2] == 5 and data[position + 3] == 6:
            end_record = position
            break
        end
        position -= 1
    end
    if end_record < 0:
        call fail("ZIP end of central directory is missing")
    end
    count = little(data, end_record + 10, 2)
    directory_size = little(data, end_record + 12, 4)
    offset = little(data, end_record + 16, 4)
    if little(data, end_record + 4, 4) != 0 or little(data, end_record + 8, 2) != count or count < 1 or count > 4096 or offset + directory_size > end_record:
        call fail("unsupported ZIP layout (multi-disk, ZIP64 or truncated)")
    end
    entries = []
    seen = {}
    for index in rang(count):
        if offset + 46 > end_record or little(data, offset, 4) != 0x02014b50:
            call fail("invalid ZIP central directory")
        end
        flags = little(data, offset + 8, 2)
        method = little(data, offset + 10, 2)
        name_length = little(data, offset + 28, 2)
        extra_length = little(data, offset + 30, 2)
        comment_length = little(data, offset + 32, 2)
        attributes = little(data, offset + 38, 4)
        if (flags & 1) != 0 or (method != 0 and method != 8):
            call fail("encrypted or unsupported ZIP member")
        end
        if offset + 46 + name_length > end_record:
            call fail("truncated ZIP member name")
        end
        for position in rang(offset + 46, offset + 46 + name_length):
            if data[position] < 32 or data[position] > 126:
                call fail("non-ASCII ZIP member name")
            end
        end
        name = __lsl_text_from_bytes(data, offset + 46, name_length)
        directory = name.endswith("/")
        if directory:
            name = name[0:len(name) - 1]
        end
        kind = (attributes >> 16) & 0o170000
        if (little(data, offset + 4, 2) >> 8) == 3 and kind != 0 and kind != 0o100000 and kind != 0o040000:
            call fail("archive links, devices and FIFOs are forbidden")
        end
        call manifest.archive_path(name, root)
        if name == root and not directory:
            call fail("archive root must be a directory")
        end
        if name in seen:
            call fail("duplicate archive path")
        end
        seen[name] = True
        entries.append(name)
        offset += 46 + name_length + extra_length + comment_length
    end
    return entries
end

function installer_entry(buffer, entries, root):
    expected = root + "/" + manifest.installer_name(host_target()[0])
    for entry in entries:
        name = entry
        if type(entry) == "Dictionary":
            name = entry["name"]
        end
        if name == expected:
            return entry
        end
    end
    call fail("archive is missing " + manifest.installer_name(host_target()[0]))
end

# Ověří archiv a rozbalí ho do work/x; vrátí cestu k jeho lsl-install.
function extract_archive(work, artifact):
    system = host_target()[0]
    root = artifact["archive_root"]
    archive = work + "/release." + manifest.archive_format(system)
    data = verify_archive(archive, artifact)
    target = work + "/x"
    call make_directories(target)
    if system == "windows":
        entries = zip_entries(data, root)
        call installer_entry(data, entries, root)
        # Windows tar.exe (libarchive) rozbalí ZIP a odmítne absolutní cesty i "..".
        call tool_run(system_tool("tar"), ["-x", "-f", archive, "-C", target], 300)
    else:
        call tool_run(system_tool("gzip"), ["-d", "-k", "-n", "--", archive], 120)
        expanded = readbytes(work + "/release.tar")
        entries = tar_entries(expanded, root)
        call installer_entry(expanded, entries, root)
        call tool_run(system_tool("tar"), ["-x", "-f", work + "/release.tar", "-C", target], 300)
    end
    installer = target + "/" + root + "/" + manifest.installer_name(system)
    if not exists(installer):
        call fail("archive did not extract " + manifest.installer_name(system))
    end
    return installer
end

# Nová (nebo vrácená) verze v prefixu: verze odpovídá a překladač přeloží
# a spustí program.
function health(prefix, expected, work):
    lsl = prefix + "/bin/" + executable_name("lsl")
    if not exists(lsl):
        call fail("installation is missing " + executable_name("lsl"))
    end
    if own_run(lsl, ["version"]).strip() != expected:
        call fail("installed CLI version differs from the expected " + expected)
    end
    probe = work + "/probe.lsl"
    program = work + "/" + executable_name("probe")
    call writefile(probe, "load json" + chr(10) + "print json.encode({\"ok\": True})" + chr(10))
    if exists(program) and unlink(program) != 0:
        call fail("cannot remove previous compiler probe")
    end
    call own_run(lsl, ["compile", probe, program])
    if own_run(program, []).strip() != "{\"ok\":true}":
        call fail("installed compiler smoke test failed")
    end
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
    if result["system"]:
        call fail("--system is only for Linux /usr/local installations")
    end
    return result
end

# Prefix instalace z cesty spuštěného lsl. Rozbalený archiv, zdrojový
# checkout ani kopie v lib/lsl-updates se neaktualizují.
function installation():
    executable = normalized(executable_path())
    if basename(executable) != executable_name("lsl"):
        call fail("self-update requires the installed lsl executable")
    end
    prefix = dirname(dirname(executable))
    if prefix.find("/lib/lsl-updates/") >= 0:
        call fail("self-update cannot run from a stored or staged version")
    end
    if not exists(prefix + "/lib/lsl/" + MARKER) and not exists(prefix + "/lib/lsl-updates/journal"):
        call fail("self-update works on installations made by lsl-install; install this package with lsl-install first")
    end
    return prefix
end

function lock(store):
    if __lsl_mkdir_private(store + "/lock") != 0:
        call fail("another LSL update is running; if none is, remove " + store + "/lock")
    end
end

function unlock(store):
    call rmdir(store + "/lock")
end

# Výměna: aktivní položky do outgoing, položky z incoming do prefixu.
function swap_in(prefix, store, version):
    outgoing = store + "/outgoing"
    incoming = store + "/incoming"
    if exists(outgoing):
        call fail("unexpected outgoing directory; rerun lsl update")
    end
    call writefile(store + "/journal", "swap" + chr(10))
    call make_directories(outgoing + "/bin")
    call make_directories(outgoing + "/lib")
    call writefile(outgoing + "/version", version + chr(10))
    for name in binary_names():
        if exists(prefix + "/bin/" + name):
            call move(prefix + "/bin/" + name, outgoing + "/bin/" + name)
        end
    end
    if exists(prefix + "/lib/lsl"):
        call move(prefix + "/lib/lsl", outgoing + "/lib/lsl")
    end
    for name in binary_names():
        if exists(incoming + "/bin/" + name):
            call move(incoming + "/bin/" + name, prefix + "/bin/" + name)
        end
    end
    call move(incoming + "/lib/lsl", prefix + "/lib/lsl")
end

# Vrátí přerušenou nebo neúspěšnou výměnu: položky z outgoing zpět do
# prefixu, nové položky do incoming. Opakovatelné po každém kroku.
function recover(prefix, store):
    if not exists(store + "/journal"):
        if exists(store + "/outgoing"):
            call remove_tree(store + "/outgoing")
        end
        return False
    end
    outgoing = store + "/outgoing"
    incoming = store + "/incoming"
    call make_directories(incoming + "/bin")
    call make_directories(incoming + "/lib")
    trash = ""
    for name in binary_names():
        if exists(outgoing + "/bin/" + name):
            if exists(prefix + "/bin/" + name):
                if exists(incoming + "/bin/" + name):
                    if trash == "":
                        trash = unique_directory(store, "trash-")
                    end
                    call move(prefix + "/bin/" + name, trash + "/" + name)
                else:
                    call move(prefix + "/bin/" + name, incoming + "/bin/" + name)
                end
            end
            call move(outgoing + "/bin/" + name, prefix + "/bin/" + name)
        end
    end
    if exists(outgoing + "/lib/lsl"):
        if exists(prefix + "/lib/lsl"):
            if exists(incoming + "/lib/lsl"):
                if trash == "":
                    trash = unique_directory(store, "trash-")
                end
                call move(prefix + "/lib/lsl", trash + "/lsl")
            else:
                call move(prefix + "/lib/lsl", incoming + "/lib/lsl")
            end
        end
        call move(outgoing + "/lib/lsl", prefix + "/lib/lsl")
    end
    call remove_tree(outgoing)
    if unlink(store + "/journal") != 0:
        call fail("cannot clear the update journal")
    end
    if trash != "":
        call remove_quietly(trash)
    end
    print "Recovered the previous LSL installation after an interrupted update."
    return True
end

# Aktivuje incoming (verze version) místo aktivní verze current.
function activate(prefix, store, current, version, work):
    call swap_in(prefix, store, current)
    failure = None
    try:
        call health(prefix, version, work)
    else:
        failure = last_error()
    end
    if failure != None:
        call recover(prefix, store)
        call fail("update rolled back: " + String(failure).replace("UpdateError: ", ""))
    end
    if exists(store + "/previous"):
        trash = unique_directory(store, "trash-")
        call rmdir(trash)
        call move(store + "/previous", trash)
        call remove_quietly(trash)
    end
    call move(store + "/outgoing", store + "/previous")
    if unlink(store + "/journal") != 0:
        call fail("cannot clear the update journal")
    end
    call remove_quietly(store + "/incoming")
end

function rollback(prefix, store, current, work):
    previous = store + "/previous"
    if not exists(previous + "/version") or not exists(previous + "/lib/lsl"):
        call fail("no previous LSL version is retained")
    end
    version = readfile(previous + "/version").strip()
    call version_parts(version)
    if exists(store + "/incoming"):
        call remove_tree(store + "/incoming")
    end
    call move(previous, store + "/incoming")
    failure = None
    try:
        call health(store + "/incoming", version, work)
    else:
        failure = last_error()
    end
    if failure != None:
        call move(store + "/incoming", previous)
        call fail("previous version failed its check: " + String(failure).replace("UpdateError: ", ""))
    end
    call activate(prefix, store, current, version, work)
    print "Rolled back to LSL " + version
end

function temporary_root():
    if windows():
        for name in ["TEMP", "TMP"]:
            value = __lsl_getenv(name)
            if value != None and value != "":
                return normalized(value)
            end
        end
        return normalized(__lsl_getenv("LOCALAPPDATA")) + "/Temp"
    end
    value = __lsl_getenv("TMPDIR")
    if value != None and value != "":
        path = String(value)
        while len(path) > 1 and path.endswith("/"):
            path = path[0:len(path) - 1]
        end
        return path
    end
    return "/tmp"
end

function execute(current, settings, work, prefix):
    call download(MANIFEST_URL, work + "/manifest.json", MAX_MANIFEST)
    call download(MANIFEST_URL + ".sig", work + "/manifest.sig", 64)
    target = host_target()
    value = verified_manifest(work, current, target[1], settings["allow-downgrade"])
    if value["comparison"] == 0:
        call console.success("LSL " + current + " is up to date.")
        return None
    elif settings["check"]:
        call console.heading("LSL " + value["version"] + " is available (installed " + current + ").")
        return None
    end
    if prefix == None:
        call fail("installation prefix is required for an update; use --check for a download-free check")
    end
    store = prefix + "/lib/lsl-updates"
    artifact = value["artifact"]
    call console.heading("Downloading verified LSL " + value["version"] + " for " + system_title(target[0]) + " " + target[1] + ".")
    call download(artifact["url"], work + "/release." + manifest.archive_format(target[0]), artifact["size"])
    installer = extract_archive(work, artifact)
    incoming = store + "/incoming"
    if exists(incoming):
        call remove_tree(incoming)
    end
    print "Installing LSL " + value["version"] + " into the staging directory."
    call own_run(installer, [incoming])
    call health(incoming, value["version"], work)
    call activate(prefix, store, current, value["version"], work)
    call console.success("Updated LSL " + current + " -> " + value["version"] + ". Previous version retained; use lsl update --rollback.")
end

function main(current):
    settings = options()
    call host_target()
    if settings["check"]:
        work = unique_directory(temporary_root(), "lsl-update-")
        failure = None
        try:
            call execute(current, settings, work, None)
        else:
            failure = last_error()
        end
        call remove_quietly(work)
        if failure != None:
            call reraise(failure)
        end
        return None
    end
    prefix = installation()
    store = prefix + "/lib/lsl-updates"
    call make_directories(store)
    call lock(store)
    work = ""
    failure = None
    try:
        call recover(prefix, store)
        work = unique_directory(store, "work-")
        if settings["rollback"]:
            call rollback(prefix, store, current, work)
        else:
            call execute(current, settings, work, prefix)
        end
    else:
        failure = last_error()
    end
    if work != "":
        call remove_quietly(work)
    end
    call unlock(store)
    if failure != None:
        call reraise(failure)
    end
end
