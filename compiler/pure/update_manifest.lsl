# Podepsaný manifest stabilního kanálu: ověření polí a výběr artefaktu.
# Sdílí ho self-update na Linuxu (update_linux_x86_64.lsl) i na Windows a
# macOS (update_portable.lsl). Kořen důvěry je zakompilovaný v programu.
load json

# stable-v2.json nese všechny platformy (Linux, Windows, macOS). Starý
# stable.json zůstává jen pro Linux x86_64 a aarch64, protože klienti 0.9.x
# neznámou architekturu odmítnou.
MANIFEST_URL = "https://lsl.lux-ai.cz/updates/channels/stable-v2.json"
KEY_ID = "6930f9769efdaa1f62183875d540b340bab10f40060082f29eedd5dcead8231a"
PUBLIC_KEY = "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEA0wMrw+VLMcfb4IlJ/CF3rIOBY10enQ/SJxiFKcLtUpo=\n-----END PUBLIC KEY-----\n"
# Týž klíč Ed25519 bez obalu SubjectPublicKeyInfo (posledních 32 bajtů PEM).
PUBLIC_KEY_RAW = "d3032bc3e54b31c7dbe08949fc2177ac8381635d1e9d0fd227188529c2ed529a"
MAX_MANIFEST = 65536
MAX_ARCHIVE = 33554432
# Balíky pro Windows nesou LLVM (llvm-mc, lld), proto větší limit.
MAX_WINDOWS_ARCHIVE = 67108864
MAX_TAR = 67108864
PLATFORMS = {"linux": ["x86_64", "aarch64", "riscv64"], "windows": ["x86_64", "arm64"], "macos": ["arm64", "x86_64"]}

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

function archive_format(system):
    if system == "windows":
        return "zip"
    end
    return "tar.gz"
end

function installer_name(system):
    if system == "windows":
        return "bin/lsl-install.exe"
    end
    return "bin/lsl-install"
end

function archive_limit(system):
    if system == "windows":
        return MAX_WINDOWS_ARCHIVE
    end
    return MAX_ARCHIVE
end

# Ověří manifest a vybere artefakt pro systém system a architekturu
# architecture. Platformy, které tento klient nezná, přeskočí: podepsaný
# manifest pak smí přidat další platformy bez rozbití starších klientů.
function manifest_value(text, current, system, architecture, allow_downgrade):
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
        name = artifact["os"]
        if type(name) != "String" or name not in PLATFORMS or artifact["architecture"] not in PLATFORMS[name]:
            continue
        end
        if artifact["format"] != archive_format(name):
            call fail("unsupported artifact format")
        end
        arch = artifact["architecture"]
        key = name + "-" + arch
        if key in seen:
            call fail("duplicate artifact platform")
        end
        seen[key] = True
        version = value["version"]
        url = "https://lsl.lux-ai.cz/updates/releases/" + version + "/lsl-" + version + "-" + key + "." + archive_format(name)
        if artifact["url"] != url or artifact["archive_root"] != "lsl-" + version or artifact["installer"] != installer_name(name):
            call fail("unsafe artifact URL or archive layout")
        end
        if type(artifact["size"]) != "Int" or artifact["size"] < 1 or artifact["size"] > archive_limit(name):
            call fail("archive size outside limit")
        end
        call hash_string(artifact["sha256"])
        if name == system and arch == architecture:
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

function parent_path(path):
    parts = String(path).split("/")
    return "/".join(parts[0:len(parts) - 1])
end

# Přísný parser ustar/GNU tar (jen soubory a adresáře pod kořenem archivu,
# žádné odkazy ani zařízení). Vrací položky; nic nezapisuje.
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
            parent = parent_path(name)
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
