# Strict dependency manifest codec for future .lux package archives.

function manifest_error(path, line_number, message):
    Error(LConfError: path + ":" + String(line_number) + ": " + message)
end

function valid_source(source):
    return source == "apt" or source == "lux" or source == "lsl"
end

function valid_dependency(name):
    if name == "" or name.startswith("-") or chr(0) in name:
        return False
    end
    for character in name:
        code = ord(character)
        if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or character in "+-._:@"):
            return False
        end
    end
    return True
end

function parse(text, path):
    if type(text) != "String" or type(path) != "String":
        Error(TypeError: "lconf.parse expects (String, String)")
    elif __lsl_text_byte_length(String(text)) > 1048576:
        Error(LConfError: path + ": manifest exceeds 1 MiB")
    end
    result = {"apt": [], "lux": [], "lsl": []}
    dependency_count = 0
    line_number = 0
    for physical_line in text.split(chr(10)):
        line_number += 1
        line = physical_line.strip()
        if line == "" or line.startswith("#"):
            continue
        end
        separator = line.find(":")
        if separator < 0:
            call manifest_error(path, line_number, "expected SOURCE: DEPENDENCY")
        end
        source = line[0:separator].strip()
        if not valid_source(source):
            call manifest_error(path, line_number, "unknown dependency source: " + source)
        end
        values = line[separator + 1:len(line)].split(",")
        for raw_value in values:
            dependency = raw_value.strip()
            if dependency == "":
                call manifest_error(path, line_number, "dependency name is empty")
            elif not valid_dependency(dependency):
                call manifest_error(path, line_number, "invalid dependency name: " + dependency)
            elif dependency in result[source]:
                call manifest_error(path, line_number, "duplicate " + source + " dependency: " + dependency)
            end
            dependency_count += 1
            if dependency_count > 4096:
                call manifest_error(path, line_number, "manifest has more than 4096 dependencies")
            end
            result[source].append(dependency)
        end
    end
    return result
end

function decode(text):
    return parse(text, "<config.lconf>")
end

function encode(manifest):
    if type(manifest) != "Dictionary":
        Error(TypeError: "lconf.encode expects a Dictionary")
    end
    pieces = []
    dependency_count = 0
    for source in ["apt", "lux", "lsl"]:
        if source not in manifest or type(manifest[source]) != "List":
            Error(TypeError: "lconf manifest requires List key: " + source)
        end
        seen = []
        for dependency in manifest[source]:
            if type(dependency) != "String" or not valid_dependency(dependency):
                Error(ValueError: "invalid " + source + " dependency")
            elif dependency in seen:
                Error(ValueError: "duplicate " + source + " dependency: " + dependency)
            end
            seen.append(dependency)
            dependency_count += 1
            if dependency_count > 4096:
                Error(ValueError: "lconf manifest has more than 4096 dependencies")
            end
            pieces.append(source + ": " + dependency + chr(10))
        end
    end
    return "".join(pieces)
end
