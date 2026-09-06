# Read-only package inventory and production catalog v1. No shell commands.
load console
load fd
load json
load package

function fail(message):
    Error(PackageError: message)
end

function text_field(value, maximum):
    if type(value) != "String" or len(value) < 1 or len(value) > maximum or console.clean(value) != value:
        call fail("catalog text field is invalid")
    end
end

function decode(content):
    if __lsl_text_byte_length(String(content)) > 1048576:
        call fail("catalog exceeds 1 MiB")
    end
    value = json.decode(content)
    if type(value) != "Dictionary" or value.get("schema", None) != 1 or type(value.get("schema", None)) != "Int" or type(value.get("packages", None)) != "List":
        call fail("unsupported package catalog schema")
    end
    items = value["packages"]
    if len(items) > 4096:
        call fail("catalog contains too many packages")
    end
    by_name = {}
    names = []
    for item in items:
        if type(item) != "Dictionary":
            call fail("catalog package must be an object")
        end
        for field in ["name", "version", "description", "license", "source", "sha256", "size"]:
            if field not in item:
                call fail("catalog package is missing " + field)
            end
        end
        name = item["name"]
        if not package.valid_name(name) or name in by_name:
            call fail("invalid or duplicate catalog package name")
        end
        call text_field(item["version"], 32)
        parts = String(item["version"]).split(".")
        if len(parts) != 3:
            call fail("invalid catalog version")
        end
        for part in parts:
            if len(part) < 1 or len(part) > 10:
                call fail("invalid catalog version")
            end
            for character in part:
                if character not in "0123456789":
                    call fail("invalid catalog version")
                end
            end
        end
        call text_field(item["description"], 300)
        call text_field(item["license"], 64)
        if item["source"] != name + ".lsl" or type(item["sha256"]) != "String" or not package.valid_hash(item["sha256"]):
            call fail("invalid catalog source or SHA-256")
        end
        if type(item["size"]) != "Int" or item["size"] < 1 or item["size"] > 1048576:
            call fail("catalog source size is outside supported limits")
        end
        by_name[name] = item
        names.append(name)
    end
    call names.sort()
    return [by_name[name] for name in names]
end

function fetch(server, curl_path):
    server = package.normalize_server(server)
    return decode(package.fetch(curl_path, server, server + "/catalog.json"))
end

function search(items, query):
    query = String(query).lower()
    return [item for item in items if query in item["name"] or query in String(item["description"]).lower()]
end

function library_file(path):
    encoded = __lsl_byte_zeros(__lsl_text_byte_length(String(path)) + 1)
    for index in rang(len(encoded) - 1):
        encoded[index] = __lsl_text_byte(String(path), index)
    end
    metadata = __lsl_byte_zeros(144)
    status = __lsl_syscall(4, __lsl_data_address(encoded), __lsl_data_address(metadata), 0, 0)
    if status == -2 or status == -20:
        return False
    elif status < 0:
        call fail("cannot inspect library: " + console.clean(path))
    end
    return ((metadata[24] + metadata[25] * 256) & 61440) == 32768
end

function directory_names(directory):
    # getdents64 is bounded, accepts only validated module basenames and closes
    # the descriptor on every error. Listing does not create HOME directories.
    if not exists(directory):
        return []
    end
    handle = fd.open(directory, 65536 + 524288)
    result = []
    failure = None
    try:
        buffer = __lsl_byte_zeros(32768)
        entries = 0
        loop:
            count = __lsl_syscall(217, handle, __lsl_data_address(buffer), len(buffer), 0)
            if count < 0:
                call fail("cannot list library directory")
            elif count == 0:
                break
            end
            offset = 0
            while offset < count:
                if count - offset < 20:
                    call fail("invalid directory entry")
                end
                size = buffer[offset + 16] + buffer[offset + 17] * 256
                if size < 20 or size > count - offset:
                    call fail("invalid directory record length")
                end
                limit = offset + 19
                while limit < offset + size and buffer[limit] != 0:
                    limit += 1
                end
                name = __lsl_text_from_bytes(buffer, offset + 19, limit - offset - 19)
                if name.endswith(".lsl"):
                    name = name[0:len(name) - 4]
                    if package.valid_name(name) and library_file(directory + "/" + name + ".lsl"):
                        result.append(name)
                    end
                end
                entries += 1
                if entries > 16384:
                    call fail("library directory contains too many entries")
                end
                offset += size
            end
        end
    else:
        failure = last_error()
    end
    call fd.close(handle)
    if failure != None:
        call fail(String(failure))
    end
    call result.sort()
    return result
end

function installed(home, bundled):
    result = []
    for name in directory_names(bundled):
        result.append({"name": name, "scope": "bundled", "path": bundled + "/" + name + ".lsl"})
    end
    if home != None and home != "":
        directory = package.user_path(home)
        for name in directory_names(directory):
            result.append({"name": name, "scope": "user", "path": directory + "/" + name + ".lsl"})
        end
    end
    return result
end

function find_installed(items, name):
    if not package.valid_name(name):
        call fail("invalid library name: " + console.clean(name))
    end
    for item in items:
        if item["name"] == name:
            return item
        end
    end
    return None
end
