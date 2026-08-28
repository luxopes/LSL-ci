# Generates a native LSL configuration evaluator wrapper for one module graph.
function dirname(path):
    index = len(path) - 1
    while index >= 0 and path[index] != "/":
        index -= 1
    end
    if index < 0:
        return "."
    elif index == 0:
        return "/"
    end
    return path[0:index]
end

function identifier_start(character):
    code = ord(character)
    return (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or character == "_"
end

function identifier_part(character):
    code = ord(character)
    return identifier_start(character) or (code >= 48 and code <= 57)
end

# Minimal lexical pass used only for the configuration security policy. It
# ignores comments, preserves newlines and treats strings as opaque tokens, so
# whitespace, aliases and text inside comments cannot bypass the checks.
function source_tokens(source, path):
    tokens = []
    characters = __lsl_string_chars(source)
    index = 0
    line = 1
    while index < len(characters):
        character = characters[index]
        if character == chr(10):
            tokens.append(["newline", "", line])
            line += 1
            index += 1
        elif character == " " or character == chr(9) or character == chr(13):
            index += 1
        elif character == "#":
            while index < len(characters) and characters[index] != chr(10):
                index += 1
            end
        elif character == "l" and index + 1 < len(characters) and (characters[index + 1] == "\"" or characters[index + 1] == "'"):
            # Lux strings evaluate the expressions between braces at runtime.
            # Treating them as opaque text would let an impure call bypass the
            # configuration identifier policy.
            print "Lux strings are not allowed in configuration in", path, "at", line
            exit(1)
        elif character == "\"" or character == "'":
            quote = character
            token_line = line
            index += 1
            value_chars = []
            escaped = False
            while index < len(characters) and characters[index] != quote:
                character = characters[index]
                if character == chr(10):
                    print "Configuration string crosses a line in", path, "at", token_line
                    exit(1)
                elif escaped:
                    # Import paths reject escapes; other strings stay opaque.
                    value_chars.append(chr(92) + character)
                    escaped = False
                elif character == chr(92):
                    escaped = True
                else:
                    value_chars.append(character)
                end
                index += 1
            end
            if index >= len(characters) or escaped:
                print "Unterminated configuration string in", path, "at", token_line
                exit(1)
            end
            index += 1
            value = "".join(value_chars)
            tokens.append(["string", value, token_line])
        elif identifier_start(character):
            start = index
            while index < len(characters) and identifier_part(characters[index]):
                index += 1
            end
            tokens.append(["identifier", "".join(characters[start:index]), line])
        else:
            tokens.append(["symbol", character, line])
            index += 1
        end
        if len(tokens) > 1000000:
            print "Configuration contains too many tokens in", path
            exit(1)
        end
    end
    return tokens
end

function next_non_newline(tokens, index):
    while index < len(tokens) and tokens[index][0] == "newline":
        index += 1
    end
    return index
end

function valid_import_path(path):
    if type(path) != "String" or len(path) == 0 or len(path) > 256 or path[0] == "/" or chr(92) in path or not path.endswith(".lsl"):
        return False
    end
    components = path.split("/")
    for component in components:
        if component == "" or component == "." or component == "..":
            return False
        end
        name = component
        if component.endswith(".lsl"):
            name = component[0:len(component) - 4]
        end
        if len(name) == 0 or not identifier_start(name[0]):
            return False
        end
        for character in name:
            if not identifier_part(character):
                return False
            end
        end
    end
    return True
end

function extract_imports(tokens, path):
    result = []
    found = False
    index = 0
    while index < len(tokens):
        if tokens[index][0] == "identifier" and tokens[index][1] == "imports":
            equals = next_non_newline(tokens, index + 1)
            if equals < len(tokens) and tokens[equals][1] == "=":
                if found:
                    print "Configuration assigns imports more than once in", path
                    exit(1)
                end
                found = True
                cursor = next_non_newline(tokens, equals + 1)
                if cursor >= len(tokens) or tokens[cursor][1] != "[":
                    print "Configuration imports must be a literal String list in", path
                    exit(1)
                end
                cursor += 1
                closed = False
                while cursor < len(tokens):
                    cursor = next_non_newline(tokens, cursor)
                    if cursor < len(tokens) and tokens[cursor][1] == "]":
                        closed = True
                        break
                    elif cursor < len(tokens) and tokens[cursor][1] == ",":
                        cursor += 1
                        continue
                    elif cursor >= len(tokens) or tokens[cursor][0] != "string" or not valid_import_path(tokens[cursor][1]):
                        print "Configuration import path is unsafe in", path
                        exit(1)
                    end
                    result.append(tokens[cursor][1])
                    if len(result) > 256:
                        print "Configuration has too many imports in", path
                        exit(1)
                    end
                    cursor += 1
                end
                if not closed:
                    print "Unterminated configuration imports in", path
                    exit(1)
                end
            end
        end
        index += 1
    end
    return result
end

function validate_pure(tokens, path):
    forbidden = {
        "input": True, "readfile": True, "readbytes": True,
        "writefile": True, "appendfile": True, "writebytes": True,
        "mkdir": True, "rmdir": True, "unlink": True, "exists": True,
        "getenv": True, "run": True, "run_clean": True, "check": True,
        "capture": True, "capture_clean": True, "capture_stream": True,
        "capture_stream_clean": True, "capture_input": True,
        "capture_input_clean": True, "capture_input_stream": True,
        "capture_input_stream_clean": True, "capture_status": True,
        "capture_stderr": True, "native_open": True, "native_size": True,
        "native_u64": True, "native_name_equal": True,
        "native_function": True, "native_call": True, "native_close": True,
        "clock": True, "executable_path": True, "arg": True,
        "arg_count": True, "exit": True, "thread_spawn": True,
        "thread_join": True, "atomic_add": True, "atomic_xchg": True,
        "atomic_cas": True, "print": True, "printl": True, "help": True
    }
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token[0] == "identifier":
            name = token[1]
            if name.startswith("__lsl_") or name in forbidden:
                print "Impure configuration identifier", name, "in", path, "at", token[2]
                exit(1)
            elif name == "from":
                print "Configuration from-imports are not allowed in", path, "at", token[2]
                exit(1)
            elif name == "load":
                module_index = index + 1
                if module_index >= len(tokens) or tokens[module_index][0] != "identifier" or tokens[module_index][1] != "config":
                    print "Configuration may load only the config module in", path, "at", token[2]
                    exit(1)
                end
                after = module_index + 1
                if after < len(tokens) and tokens[after][0] != "newline":
                    print "Configuration module aliases are not allowed in", path, "at", token[2]
                    exit(1)
                end
                index = module_index
            end
        end
        index += 1
    end
end

function collect(path, seen, active, order, sources, source_budget):
    if len(active) >= 128:
        print "Configuration import depth exceeds 128 at", path
        exit(1)
    elif len(seen) >= 256:
        print "Configuration graph exceeds 256 modules at", path
        exit(1)
    end
    if path in active:
        start = 0
        while start < len(active) and active[start] != path:
            start += 1
        end
        cycle = active[start:len(active)]
        cycle.append(path)
        print "Configuration import cycle:", " -> ".join(cycle)
        exit(1)
    elif path in seen:
        return
    end
    active.append(path)
    source = readfile(path)
    source_bytes = __lsl_text_byte_length(String(source))
    if source_bytes > 1048576:
        print "Configuration source exceeds 1 MiB in", path
        exit(1)
    elif source_bytes > 16777216 - source_budget[0]:
        print "Configuration graph exceeds 16 MiB at", path
        exit(1)
    end
    source_budget[0] += source_bytes
    tokens = source_tokens(source, path)
    call validate_pure(tokens, path)
    imports = extract_imports(tokens, path)
    index = 0
    while index < len(imports):
        child = imports[index]
        call collect(dirname(path) + "/" + child, seen, active, order, sources, source_budget)
        index += 1
    end
    call __lsl_pop(active)
    seen.append(path)
    order.append(path)
    sources.append(source)
end

function string_literal(value):
    result = "\""
    for character in String(value):
        code = ord(character)
        if character == "\"" or character == chr(92):
            result += chr(92) + character
        elif character == chr(10):
            result += chr(92) + "n"
        elif character == chr(13):
            result += chr(92) + "r"
        elif character == chr(9):
            result += chr(92) + "t"
        elif code < 32 or code == 127:
            print "Configuration path contains a control character"
            exit(1)
        else:
            result += character
        end
    end
    return result + "\""
end

function has_export(source, name):
    return source.find(name + " =") >= 0 or source.find(name + "=") >= 0
end

function snapshot_name(index):
    return "lsl_config_snapshot_" + String(index)
end

function module_name(root, path):
    relative = path
    prefix = root + "/"
    if path.startswith(prefix):
        relative = path[len(prefix):len(path)]
    end
    if relative.endswith(".lsl"):
        relative = relative[0:len(relative) - 4]
    end
    return relative.replace("/", ".")
end

entry = arg(1)
output_path = arg(2)
snapshot_root = arg(3)
if entry == None or output_path == None:
    print "usage: lsl-configure ENTRY OUTPUT"
    exit(2)
end
root = dirname(entry)
entry_name = entry
slash = entry_name.find("/")
while slash >= 0:
    entry_name = entry_name[slash + 1:len(entry_name)]
    slash = entry_name.find("/")
end
if not valid_import_path(entry_name):
    print "Configuration entry filename must be a safe .lsl module name"
    exit(2)
end
order = []
sources = []
source_budget = [0]
call collect(entry, [], [], order, sources, source_budget)
snapshot = snapshot_root != None
if snapshot:
    if type(snapshot_root) != "String" or len(snapshot_root) == 0 or __lsl_text_byte_length(String(snapshot_root)) > 4095 or snapshot_root[0] != "/" or chr(0) in snapshot_root or not exists(snapshot_root):
        print "Configuration snapshot directory is invalid"
        exit(2)
    end
    index = 0
    while index < len(order):
        snapshot_path = snapshot_root + "/" + snapshot_name(index) + ".lsl"
        if exists(snapshot_path):
            print "Configuration snapshot target already exists"
            exit(1)
        end
        call writefile(snapshot_path, sources[index])
        index += 1
    end
end
wrapper = "load json\n"
index = 0
while index < len(order):
    loaded_module = module_name(root, order[index])
    if snapshot:
        loaded_module = snapshot_name(index)
    end
    wrapper += "load " + loaded_module + "\n"
    index += 1
end
wrapper += "\nfunction priority(value):\n"
wrapper += "    if __lsl_type_code(value) == 3 and \"__priority\" in value:\n        return value[\"__priority\"]\n    end\n    return 500\nend\n"
wrapper += "\nfunction unwrap(value):\n"
wrapper += "    if __lsl_type_code(value) == 3 and \"__priority\" in value:\n        return value[\"value\"]\n    end\n    return value\nend\n"
wrapper += "\nfunction merge_pair_active(active, left, right):\n"
wrapper += "    for pair in active:\n        if __lsl_raw_equal(pair[0], left) and __lsl_raw_equal(pair[1], right):\n            return True\n        end\n    end\n    return False\nend\n"
wrapper += "\nfunction deep_merge(left, right, active):\n"
wrapper += "    if __lsl_type_code(right) == 3 and \"__omit\" in right:\n        return left\n    end\n"
wrapper += "    left_priority = priority(left)\n    right_priority = priority(right)\n"
wrapper += "    if left_priority != right_priority:\n        if right_priority > left_priority:\n            return right\n        end\n        return left\n    end\n"
wrapper += "    left_value = unwrap(left)\n    right_value = unwrap(right)\n"
wrapper += "    if __lsl_type_code(left_value) == 3 and __lsl_type_code(right_value) == 3:\n"
wrapper += "        if merge_pair_active(active, left_value, right_value):\n            Error(ConfigCycleError: \"configuration merge cycle\")\n        end\n        if len(active) >= 64:\n            Error(ConfigDepthError: \"configuration merge exceeds depth 64\")\n        end\n        active.append([left_value, right_value])\n"
wrapper += "        dictionary_result = {}\n        for key in left_value:\n            dictionary_result[key] = left_value[key]\n        end\n        for key in right_value:\n            if key in dictionary_result:\n                dictionary_result[key] = deep_merge(dictionary_result[key], right_value[key], active)\n            else:\n                dictionary_result[key] = right_value[key]\n            end\n        end\n        call __lsl_pop(active)\n        return dictionary_result\n    end\n"
wrapper += "    if __lsl_type_code(left_value) == 2 and __lsl_type_code(right_value) == 2:\n        list_result = left_value[0:len(left_value)]\n        list_result.extend(right_value)\n        return list_result\n    end\n"
wrapper += "    return right\nend\n"
wrapper += "\nfunction identity_active(active, value):\n"
wrapper += "    for item in active:\n        if __lsl_raw_equal(item, value):\n            return True\n        end\n    end\n    return False\nend\n"
wrapper += "\nfunction materialize(value, active):\n"
wrapper += "    value_type = __lsl_type_code(value)\n"
wrapper += "    if value_type != 2 and value_type != 3:\n        return value\n    end\n"
wrapper += "    if identity_active(active, value):\n        Error(ConfigCycleError: \"cyclic configuration value\")\n    end\n"
wrapper += "    if len(active) >= 64:\n        Error(ConfigDepthError: \"configuration value exceeds depth 64\")\n    end\n"
wrapper += "    active.append(value)\n"
wrapper += "    if value_type == 3 and \"__priority\" in value:\n        resolved = materialize(value[\"value\"], active)\n        call __lsl_pop(active)\n        return resolved\n    end\n"
wrapper += "    if value_type == 3 and \"__lazy\" in value:\n        thunk = value[\"__lazy\"]\n        resolved = materialize(thunk(), active)\n        call __lsl_pop(active)\n        return resolved\n    end\n"
wrapper += "    if value_type == 3:\n        dictionary_result = {}\n        for key in value:\n            if not (__lsl_type_code(value[key]) == 3 and \"__omit\" in value[key]):\n                materialized = materialize(value[key], active)\n                dictionary_result[key] = materialized\n            end\n        end\n        call __lsl_pop(active)\n        return dictionary_result\n    end\n"
wrapper += "    list_result = []\n    for item in value:\n        materialized = materialize(item, active)\n        list_result.append(materialized)\n    end\n    call __lsl_pop(active)\n    return list_result\nend\n"
wrapper += "\nfunction get_path(root, path, missing):\n"
wrapper += "    parts = path.split(\".\")\n    value = root\n    for part in parts:\n        if __lsl_type_code(value) != 3 or part not in value:\n            return missing\n        end\n        value = value[part]\n    end\n    return value\nend\n"
wrapper += "\nfunction set_path(root, path, value):\n"
wrapper += "    parts = path.split(\".\")\n    target = root\n    index = 0\n    while index < len(parts) - 1:\n        part = parts[index]\n        if part not in target or __lsl_type_code(target[part]) != 3:\n            target[part] = {}\n        end\n        target = target[part]\n        index += 1\n    end\n    target[parts[len(parts) - 1]] = value\nend\n"
wrapper += "\nfunction dynamic_type(value):\n    code = __lsl_type_code(value)\n    if code == 0 or code == 9:\n        return \"Int\"\n    elif code == 1:\n        return \"String\"\n    elif code == 2:\n        return \"List\"\n    elif code == 3:\n        return \"Dictionary\"\n    elif code == 4:\n        return \"Bool\"\n    elif code == 5:\n        return \"None\"\n    end\n    return \"Any\"\nend\n"
wrapper += "\nfunction type_matches(value, expected):\n"
wrapper += "    variants = expected.split(\"|\")\n    for variant in variants:\n        if variant.strip() == \"Any\" or variant.strip() == dynamic_type(value):\n            return True\n        end\n    end\n    return False\nend\n"
wrapper += "\nmerged = {}\nall_options = {}\nall_assertions = []\n"
index = 0
while index < len(order):
    current_module = module_name(root, order[index])
    if snapshot:
        current_module = snapshot_name(index)
    end
    wrapper += "merged = deep_merge(merged, " + current_module + ".config, [])\n"
    if has_export(sources[index], "options"):
        wrapper += "for declared_name in " + current_module + ".options:\n"
        wrapper += "    declared_option = " + current_module + ".options[declared_name]\n"
        wrapper += "    declared_option[\"source\"] = " + string_literal(order[index]) + "\n"
        wrapper += "    all_options[declared_name] = declared_option\nend\n"
    end
    if has_export(sources[index], "assertions"):
        wrapper += "all_assertions.extend(" + current_module + ".assertions)\n"
    end
    index += 1
end
wrapper += "clean = materialize(merged, [])\nmissing = {\"__missing\": True}\n"
wrapper += "for option_name in all_options:\n    descriptor = all_options[option_name]\n    option_value = get_path(clean, option_name, missing)\n    if option_value == missing:\n        if descriptor[\"required\"]:\n            print \"Missing required option\", option_name, \"declared in\", descriptor[\"source\"]\n            exit(1)\n        end\n        option_value = materialize(descriptor[\"default\"], [])\n        call set_path(clean, option_name, option_value)\n    end\n    if not type_matches(option_value, descriptor[\"type\"]):\n        print \"Invalid option type\", option_name, descriptor[\"type\"], dynamic_type(option_value), \"declared in\", descriptor[\"source\"]\n        exit(1)\n    end\nend\n"
wrapper += "for assertion in all_assertions:\n    if not assertion[0]:\n        print \"Configuration assertion failed:\", assertion[1]\n        exit(1)\n    end\nend\n"
wrapper += "print json.encode(clean)\n"
if output_path == "-":
    print wrapper
else:
    call writefile(output_path, wrapper)
end
