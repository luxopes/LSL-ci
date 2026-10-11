load _catalog_platform as transport
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
    return transport.library_file(path)
end

function directory_names(directory):
    return transport.directory_names(directory)
end

function installed(home, bundled):
    result = []
    directory = ""
    if home != None and home != "":
        directory = package.user_path(home)
    end
    for name in directory_names(bundled):
        path = bundled + "/" + name + ".lsl"
        scope = "bundled"
        # A legacy ~/.local toolchain shares its source directory with user
        # packages. Installer provenance distinguishes downloaded libraries;
        # this is inventory only, not a replacement for `lsl origin` verification.
        if directory == bundled and library_file(path + ".origin"):
            scope = "user"
        end
        result.append({"name": name, "scope": scope, "path": path})
    end
    if directory != "" and directory != bundled:
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
