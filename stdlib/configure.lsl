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

function extract_imports(source):
    result = []
    marker = source.find("imports")
    if marker < 0:
        return result
    end
    start = source[marker:len(source)].find("[")
    if start < 0:
        return result
    end
    start += marker + 1
    stop = start
    depth = 1
    quote = ""
    escaped = False
    while stop < len(source) and depth > 0:
        char = source[stop]
        if len(quote) > 0:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
            end
        elif char == "\"" or char == "'":
            quote = char
        elif char == "[":
            depth += 1
        elif char == "]":
            depth -= 1
        end
        stop += 1
    end
    text = source[start:stop - 1]
    index = 0
    while index < len(text):
        if text[index] == "\"" or text[index] == "'":
            quote = text[index]
            index += 1
            value = ""
            while index < len(text) and text[index] != quote:
                value += text[index]
                index += 1
            end
            result.append(value)
        end
        index += 1
    end
    return result
end

function validate_pure(source, path):
    forbidden = ["input ", "input(", "readfile(", "writefile(", "appendfile(", "load http", "load env", "load native", "getenv(", "run(", "capture(", "native_open(", "native_call(", "clock(", "exit("]
    for feature in forbidden:
        if feature in source:
            print "Impure configuration feature", feature, "in", path
            exit(1)
        end
    end
end

function collect(path, seen, active, order):
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
    call validate_pure(source, path)
    imports = extract_imports(source)
    index = 0
    while index < len(imports):
        child = imports[index]
        if not child.endswith(".lsl"):
            child += ".lsl"
        end
        call collect(dirname(path) + "/" + child, seen, active, order)
        index += 1
    end
    call __lsl_pop(active)
    seen.append(path)
    order.append(path)
end

function has_export(path, name):
    source = readfile(path)
    return source.find(name + " =") >= 0 or source.find(name + "=") >= 0
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
if entry == None or output_path == None:
    print "usage: lsl-configure ENTRY OUTPUT"
    exit(2)
end
root = dirname(entry)
order = []
call collect(entry, [], [], order)
wrapper = "load json\n"
index = 0
while index < len(order):
    wrapper += "load " + module_name(root, order[index]) + "\n"
    index += 1
end
wrapper += "\nfunction priority(value):\n"
wrapper += "    if __lsl_type_code(value) == 3 and \"__priority\" in value:\n        return value[\"__priority\"]\n    end\n    return 500\nend\n"
wrapper += "\nfunction unwrap(value):\n"
wrapper += "    if __lsl_type_code(value) == 3 and \"__priority\" in value:\n        return value[\"value\"]\n    end\n    return value\nend\n"
wrapper += "\nfunction deep_merge(left, right):\n"
wrapper += "    if __lsl_type_code(right) == 3 and \"__omit\" in right:\n        return left\n    end\n"
wrapper += "    left_priority = priority(left)\n    right_priority = priority(right)\n"
wrapper += "    if left_priority != right_priority:\n        if right_priority > left_priority:\n            return right\n        end\n        return left\n    end\n"
wrapper += "    left_value = unwrap(left)\n    right_value = unwrap(right)\n"
wrapper += "    if __lsl_type_code(left_value) == 3 and __lsl_type_code(right_value) == 3:\n"
wrapper += "        dictionary_result = {}\n        for key in left_value:\n            dictionary_result[key] = left_value[key]\n        end\n        for key in right_value:\n            if key in dictionary_result:\n                dictionary_result[key] = deep_merge(dictionary_result[key], right_value[key])\n            else:\n                dictionary_result[key] = right_value[key]\n            end\n        end\n        return dictionary_result\n    end\n"
wrapper += "    if __lsl_type_code(left_value) == 2 and __lsl_type_code(right_value) == 2:\n        list_result = left_value[0:len(left_value)]\n        list_result.extend(right_value)\n        return list_result\n    end\n"
wrapper += "    return right\nend\n"
wrapper += "\nfunction materialize(value, active):\n"
wrapper += "    if __lsl_type_code(value) == 3 and \"__priority\" in value:\n        return materialize(value[\"value\"], active)\n    end\n"
wrapper += "    if __lsl_type_code(value) == 3 and \"__lazy\" in value:\n        thunk = value[\"__lazy\"]\n        if thunk in active:\n            Error(ConfigCycleError: \"lazy configuration dependency cycle\")\n        end\n        active.append(thunk)\n        resolved = materialize(thunk(), active)\n        call __lsl_pop(active)\n        return resolved\n    end\n"
wrapper += "    if __lsl_type_code(value) == 3:\n        dictionary_result = {}\n        for key in value:\n            if not (__lsl_type_code(value[key]) == 3 and \"__omit\" in value[key]):\n                materialized = materialize(value[key], active)\n                dictionary_result[key] = materialized\n            end\n        end\n        return dictionary_result\n    end\n"
wrapper += "    if __lsl_type_code(value) == 2:\n        list_result = []\n        for item in value:\n            materialized = materialize(item, active)\n            list_result.append(materialized)\n        end\n        return list_result\n    end\n    return value\nend\n"
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
    wrapper += "merged = deep_merge(merged, " + current_module + ".config)\n"
    if has_export(order[index], "options"):
        wrapper += "all_options.update(" + current_module + ".options)\n"
    end
    if has_export(order[index], "assertions"):
        wrapper += "all_assertions.extend(" + current_module + ".assertions)\n"
    end
    index += 1
end
wrapper += "clean = materialize(merged, [])\nmissing = {\"__missing\": True}\n"
wrapper += "for option_name in all_options:\n    descriptor = all_options[option_name]\n    option_value = get_path(clean, option_name, missing)\n    if option_value == missing:\n        if descriptor[\"required\"]:\n            print \"Missing required option\", option_name\n            exit(1)\n        end\n        option_value = materialize(descriptor[\"default\"], [])\n        call set_path(clean, option_name, option_value)\n    end\n    if not type_matches(option_value, descriptor[\"type\"]):\n        print \"Invalid option type\", option_name, descriptor[\"type\"], dynamic_type(option_value)\n        exit(1)\n    end\nend\n"
wrapper += "for assertion in all_assertions:\n    if not assertion[0]:\n        print \"Configuration assertion failed:\", assertion[1]\n        exit(1)\n    end\nend\n"
wrapper += "print json.encode(clean)\n"
call writefile(output_path, wrapper)
