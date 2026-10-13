# Recursive AST module linker for the direct compiler. Module functions are
# flattened to deterministic prefixed native symbols; no runtime loader exists.

load parser
load diagnostics
load target
load host

function dirname(path):
    return host.dirname(path)
end

function module_alias(name):
    parts = name.split(".")
    return parts[len(parts) - 1]
end

function module_prefix(index):
    # Import names are relative to their owner. Two different directories may
    # therefore both contain (for example) helper.lsl. A graph-order identity
    # avoids symbol collisions between those distinct files as well as between
    # dotted names and names containing underscores.
    return "@lsl_module_" + String(index) + "@"
end

function builtin_module(name):
    builtins = "|_platform|_platform_linux_arm64|_platform_linux_riscv64|_platform_linux_x86_64|_random_hash|ai|bigint|config|configure|cuda|env|fd|http|httpserver|json|lconf|lux|luxos|math|native|os|plugin|process|random|requests|sandbox|system|tensor|time|tui|unixsock|"
    return "|" + String(name) + "|" in builtins or target.builtin_provider(name)
end

function module_path_with_home(name, owner_path, home):
    return host.module_path(name, owner_path, home, builtin_module(name))
end

function module_path(name, owner_path):
    return module_path_with_home(name, owner_path, host.home())
end

function private_class(statement):
    if statement["kind"] != "class":
        return False
    end
    for member in statement["body"]:
        if member["kind"] == "ctype":
            return member["visibility"] == "Private"
        end
    end
    return False
end

function collect_names(statements, result):
    for statement in statements:
        kind = statement["kind"]
        if kind == "function" or kind == "class":
            # Function/class bodies have their own local namespace.
            result[statement["name"]] = statement["name"]
        elif kind == "assign":
            if statement["target"]["kind"] == "name":
                result[statement["target"]["name"]] = statement["target"]["name"]
            end
        elif kind == "for":
            result[statement["name"]] = statement["name"]
            call collect_names(statement["body"], result)
        elif kind == "if":
            for branch in statement["branches"]:
                call collect_names(branch[1], result)
            end
            call collect_names(statement["otherwise"], result)
        elif kind == "while" or kind == "loop" or kind == "safe" or kind == "unsafe":
            call collect_names(statement["body"], result)
        elif kind == "try":
            call collect_names(statement["body"], result)
            call collect_names(statement["otherwise"], result)
        end
    end
end

function function_names(program):
    result = {}
    call collect_names(program, result)
    return result
end

function scoped_names(names, parameters, body):
    # An empty import/name map cannot contain a shadowed binding.
    if len(names) == 0:
        return {}
    end
    result = Dictionary(names)
    for parameter in parameters:
        if parameter in result:
            del(result[parameter])
        end
    end
    locals = {}
    call collect_names(body, locals)
    for name in locals.keys():
        if name in result:
            del(result[name])
        end
    end
    return result
end

function annotate_expression(expression, path):
    if expression == None:
        return
    end
    expression["path"] = path
    kind = expression["kind"]
    if kind == "comprehension":
        call annotate_statements(expression["body"], path)
        call annotate_expression(expression["result"], path)
    elif kind == "member":
        call annotate_expression(expression["target"], path)
    elif kind == "call":
        call annotate_expression(expression["target"], path)
        for argument in expression["arguments"]:
            call annotate_expression(argument, path)
        end
    elif kind == "binary":
        call annotate_expression(expression["left"], path)
        call annotate_expression(expression["right"], path)
    elif kind == "unary":
        call annotate_expression(expression["operand"], path)
    elif kind == "compare":
        for operand in expression["operands"]:
            call annotate_expression(operand, path)
        end
    elif kind == "index":
        call annotate_expression(expression["target"], path)
        call annotate_expression(expression["index"], path)
    elif kind == "slice":
        call annotate_expression(expression["target"], path)
        call annotate_expression(expression["start"], path)
        call annotate_expression(expression["stop"], path)
        call annotate_expression(expression.get("step", None), path)
    elif kind == "list" or kind == "tuple" or kind == "real_array":
        for item in expression["items"]:
            call annotate_expression(item, path)
        end
    elif kind == "dictionary":
        for entry in expression["entries"]:
            call annotate_expression(entry[0], path)
            call annotate_expression(entry[1], path)
        end
    end
end

function annotate_statements(statements, path):
    for statement in statements:
        statement["path"] = path
        kind = statement["kind"]
        if kind == "function" or kind == "loop" or kind == "safe" or kind == "unsafe":
            call annotate_statements(statement["body"], path)
        elif kind == "while":
            call annotate_expression(statement["condition"], path)
            call annotate_statements(statement["body"], path)
        elif kind == "for":
            call annotate_expression(statement["iterable"], path)
            call annotate_statements(statement["body"], path)
        elif kind == "try":
            call annotate_statements(statement["body"], path)
            call annotate_statements(statement["otherwise"], path)
        elif kind == "class":
            call annotate_expression(statement["condition"], path)
            call annotate_expression(statement.get("parent", None), path)
            call annotate_statements(statement["body"], path)
        elif kind == "assign":
            call annotate_expression(statement["target"], path)
            call annotate_expression(statement["value"], path)
        elif kind == "print":
            for expression in statement["expressions"]:
                call annotate_expression(expression, path)
            end
        elif kind == "expression":
            call annotate_expression(statement["expression"], path)
        elif kind == "return":
            call annotate_expression(statement["expression"], path)
        elif kind == "if":
            for branch in statement["branches"]:
                call annotate_expression(branch[0], path)
                call annotate_statements(branch[1], path)
            end
            call annotate_statements(statement["otherwise"], path)
        elif kind == "error":
            call annotate_expression(statement["message"], path)
        elif kind == "delete":
            call annotate_expression(statement["target"], path)
        end
    end
end

function mark_trusted(statements, trusted):
    for statement in statements:
        statement["trusted"] = trusted
        kind = statement["kind"]
        if kind == "function" or kind == "loop" or kind == "safe" or kind == "unsafe":
            call mark_trusted(statement["body"], trusted)
        elif kind == "while" or kind == "for":
            call mark_trusted(statement["body"], trusted)
        elif kind == "try":
            call mark_trusted(statement["body"], trusted)
            call mark_trusted(statement["otherwise"], trusted)
        elif kind == "if":
            for branch in statement["branches"]:
                call mark_trusted(branch[1], trusted)
            end
            call mark_trusted(statement["otherwise"], trusted)
        elif kind == "class":
            call mark_trusted(statement["body"], trusted)
        end
    end
end

function mark_internal_abi(statements, internal):
    for statement in statements:
        statement["internal_abi"] = Bool(internal)
        kind = statement["kind"]
        if kind == "function" or kind == "loop" or kind == "safe" or kind == "unsafe":
            call mark_internal_abi(statement["body"], internal)
        elif kind == "while" or kind == "for":
            call mark_internal_abi(statement["body"], internal)
        elif kind == "try":
            call mark_internal_abi(statement["body"], internal)
            call mark_internal_abi(statement["otherwise"], internal)
        elif kind == "if":
            for branch in statement["branches"]:
                call mark_internal_abi(branch[1], internal)
            end
            call mark_internal_abi(statement["otherwise"], internal)
        elif kind == "class":
            call mark_internal_abi(statement["body"], internal)
        end
    end
end

function unsafe_name(name):
    value = String(name)
    return value == "thread_spawn" or value.startswith("__lsl_") or value.startswith("native__") or value.startswith("native_")
end

function unsafe_failure(expression, name, sandbox_mode):
    detail = "unsafe operation outside an unsafe block"
    if sandbox_mode:
        detail = "unsafe operation is forbidden in sandbox compilation"
    end
    Error(CompileError: detail + " at " + String(expression.get("path", "<source>")) + ":" + String(expression.get("line", 0)) + ": " + String(name))
end

function validate_safe_expression(expression, trusted, unsafe_context, sandbox_mode):
    if expression == None:
        return None
    end
    kind = expression["kind"]
    if kind == "comprehension":
        call mark_trusted(expression["body"], trusted)
        call validate_safe_statements(expression["body"], unsafe_context, sandbox_mode)
    elif kind == "name":
        name = expression["name"]
        if not trusted and unsafe_name(name) and (not unsafe_context or sandbox_mode):
            call unsafe_failure(expression, name, sandbox_mode)
        end
    elif kind == "member":
        call validate_safe_expression(expression["target"], trusted, unsafe_context, sandbox_mode)
    elif kind == "call":
        call validate_safe_expression(expression["target"], trusted, unsafe_context, sandbox_mode)
        for argument in expression["arguments"]:
            call validate_safe_expression(argument, trusted, unsafe_context, sandbox_mode)
        end
    elif kind == "binary":
        call validate_safe_expression(expression["left"], trusted, unsafe_context, sandbox_mode)
        call validate_safe_expression(expression["right"], trusted, unsafe_context, sandbox_mode)
    elif kind == "unary":
        call validate_safe_expression(expression["operand"], trusted, unsafe_context, sandbox_mode)
    elif kind == "compare":
        for operand in expression["operands"]:
            call validate_safe_expression(operand, trusted, unsafe_context, sandbox_mode)
        end
    elif kind == "index":
        call validate_safe_expression(expression["target"], trusted, unsafe_context, sandbox_mode)
        call validate_safe_expression(expression["index"], trusted, unsafe_context, sandbox_mode)
    elif kind == "slice":
        call validate_safe_expression(expression["target"], trusted, unsafe_context, sandbox_mode)
        call validate_safe_expression(expression["start"], trusted, unsafe_context, sandbox_mode)
        call validate_safe_expression(expression["stop"], trusted, unsafe_context, sandbox_mode)
        call validate_safe_expression(expression.get("step", None), trusted, unsafe_context, sandbox_mode)
    elif kind == "list" or kind == "tuple" or kind == "real_array":
        for item in expression["items"]:
            call validate_safe_expression(item, trusted, unsafe_context, sandbox_mode)
        end
    elif kind == "dictionary":
        for entry in expression["entries"]:
            call validate_safe_expression(entry[0], trusted, unsafe_context, sandbox_mode)
            call validate_safe_expression(entry[1], trusted, unsafe_context, sandbox_mode)
        end
    end
    return None
end

function validate_safe_statements(statements, unsafe_context, sandbox_mode):
    for statement in statements:
        trusted = statement.get("trusted", False)
        kind = statement["kind"]
        if kind == "unsafe":
            if not trusted and sandbox_mode:
                Error(CompileError: "unsafe block is forbidden in sandbox compilation at " + String(statement.get("path", "<source>")) + ":" + String(statement.get("line", 0)))
            end
            call validate_safe_statements(statement["body"], True, sandbox_mode)
        elif kind == "function" or kind == "loop" or kind == "safe":
            call validate_safe_statements(statement["body"], unsafe_context, sandbox_mode)
        elif kind == "while":
            call validate_safe_expression(statement["condition"], trusted, unsafe_context, sandbox_mode)
            call validate_safe_statements(statement["body"], unsafe_context, sandbox_mode)
        elif kind == "for":
            call validate_safe_expression(statement["iterable"], trusted, unsafe_context, sandbox_mode)
            call validate_safe_statements(statement["body"], unsafe_context, sandbox_mode)
        elif kind == "try":
            call validate_safe_statements(statement["body"], unsafe_context, sandbox_mode)
            call validate_safe_statements(statement["otherwise"], unsafe_context, sandbox_mode)
        elif kind == "class":
            call validate_safe_expression(statement["condition"], trusted, unsafe_context, sandbox_mode)
            call validate_safe_expression(statement.get("parent", None), trusted, unsafe_context, sandbox_mode)
            call validate_safe_statements(statement["body"], unsafe_context, sandbox_mode)
        elif kind == "assign":
            call validate_safe_expression(statement["target"], trusted, unsafe_context, sandbox_mode)
            call validate_safe_expression(statement["value"], trusted, unsafe_context, sandbox_mode)
        elif kind == "print":
            for expression in statement["expressions"]:
                call validate_safe_expression(expression, trusted, unsafe_context, sandbox_mode)
            end
        elif kind == "expression" or kind == "return":
            call validate_safe_expression(statement["expression"], trusted, unsafe_context, sandbox_mode)
        elif kind == "if":
            for branch in statement["branches"]:
                call validate_safe_expression(branch[0], trusted, unsafe_context, sandbox_mode)
                call validate_safe_statements(branch[1], unsafe_context, sandbox_mode)
            end
            call validate_safe_statements(statement["otherwise"], unsafe_context, sandbox_mode)
        elif kind == "error":
            call validate_safe_expression(statement["message"], trusted, unsafe_context, sandbox_mode)
        elif kind == "delete":
            call validate_safe_expression(statement["target"], trusted, unsafe_context, sandbox_mode)
        end
    end
    return None
end

function transform_expression(expression, own_functions, imported_names, namespaces):
    if expression == None:
        return None
    end
    kind = expression["kind"]
    if kind == "comprehension":
        call transform_statements(expression["body"], own_functions, imported_names, namespaces)
    elif kind == "name":
        name = expression["name"]
        if name in imported_names:
            expression["name"] = imported_names[name]
        elif name in own_functions:
            expression["name"] = own_functions[name]
        end
    elif kind == "member":
        target = expression["target"]
        transformed_namespace = False
        if target["kind"] == "name":
            # `origin` is the reserved immediate-parent receiver only when it
            # is used as `origin.method()`. A standalone function named
            # `origin` remains a normal module symbol.
            if target["name"] == "origin":
                transformed_namespace = True
            elif target["name"] in namespaces:
                expression["kind"] = "name"
                expression["name"] = namespace_prefix(namespaces[target["name"]], expression["name"]) + expression["name"]
                transformed_namespace = True
            end
        end
        if not transformed_namespace:
            call transform_expression(target, own_functions, imported_names, namespaces)
        end
    elif kind == "call":
        call transform_expression(expression["target"], own_functions, imported_names, namespaces)
        for argument in expression["arguments"]:
            call transform_expression(argument, own_functions, imported_names, namespaces)
        end
    elif kind == "binary":
        call transform_expression(expression["left"], own_functions, imported_names, namespaces)
        call transform_expression(expression["right"], own_functions, imported_names, namespaces)
    elif kind == "unary":
        call transform_expression(expression["operand"], own_functions, imported_names, namespaces)
    elif kind == "compare":
        for operand in expression["operands"]:
            call transform_expression(operand, own_functions, imported_names, namespaces)
        end
    elif kind == "index":
        call transform_expression(expression["target"], own_functions, imported_names, namespaces)
        call transform_expression(expression["index"], own_functions, imported_names, namespaces)
    elif kind == "slice":
        call transform_expression(expression["target"], own_functions, imported_names, namespaces)
        call transform_expression(expression["start"], own_functions, imported_names, namespaces)
        call transform_expression(expression["stop"], own_functions, imported_names, namespaces)
        call transform_expression(expression.get("step", None), own_functions, imported_names, namespaces)
    elif kind == "list" or kind == "tuple" or kind == "real_array":
        for item in expression["items"]:
            call transform_expression(item, own_functions, imported_names, namespaces)
        end
    elif kind == "dictionary":
        for entry in expression["entries"]:
            call transform_expression(entry[0], own_functions, imported_names, namespaces)
            call transform_expression(entry[1], own_functions, imported_names, namespaces)
        end
    end
end

function transform_statements(statements, own_functions, imported_names, namespaces):
    for statement in statements:
        kind = statement["kind"]
        if kind == "function":
            statement["name"] = own_functions[statement["name"]]
            local_names = scoped_names(own_functions, statement["parameters"], statement["body"])
            local_imports = scoped_names(imported_names, statement["parameters"], statement["body"])
            # Jména z global se nestínají lokální proměnnou: zůstává jméno modulu.
            if "globals" in statement:
                renamed = []
                for declared in statement["globals"]:
                    if declared in own_functions:
                        local_names[declared] = own_functions[declared]
                        renamed.append(own_functions[declared])
                    else:
                        renamed.append(declared)
                    end
                end
                statement["globals"] = renamed
            end
            call transform_statements(statement["body"], local_names, local_imports, namespaces)
        elif kind == "assign":
            call transform_expression(statement["target"], own_functions, imported_names, namespaces)
            call transform_expression(statement["value"], own_functions, imported_names, namespaces)
        elif kind == "print":
            for expression in statement["expressions"]:
                call transform_expression(expression, own_functions, imported_names, namespaces)
            end
        elif kind == "expression":
            call transform_expression(statement["expression"], own_functions, imported_names, namespaces)
        elif kind == "return":
            call transform_expression(statement["expression"], own_functions, imported_names, namespaces)
        elif kind == "if":
            for branch in statement["branches"]:
                call transform_expression(branch[0], own_functions, imported_names, namespaces)
                call transform_statements(branch[1], own_functions, imported_names, namespaces)
            end
            call transform_statements(statement["otherwise"], own_functions, imported_names, namespaces)
        elif kind == "while":
            call transform_expression(statement["condition"], own_functions, imported_names, namespaces)
            call transform_statements(statement["body"], own_functions, imported_names, namespaces)
        elif kind == "for":
            if statement["name"] in own_functions:
                statement["name"] = own_functions[statement["name"]]
            end
            call transform_expression(statement["iterable"], own_functions, imported_names, namespaces)
            call transform_statements(statement["body"], own_functions, imported_names, namespaces)
        elif kind == "loop" or kind == "safe" or kind == "unsafe":
            call transform_statements(statement["body"], own_functions, imported_names, namespaces)
        elif kind == "try":
            call transform_statements(statement["body"], own_functions, imported_names, namespaces)
            call transform_statements(statement["otherwise"], own_functions, imported_names, namespaces)
        elif kind == "error":
            call transform_expression(statement["message"], own_functions, imported_names, namespaces)
        elif kind == "delete":
            call transform_expression(statement["target"], own_functions, imported_names, namespaces)
        elif kind == "global":
            statement["names"] = [own_functions.get(declared, declared) for declared in statement["names"]]
        elif kind == "class":
            statement["name"] = own_functions[statement["name"]]
            call transform_expression(statement["condition"], own_functions, imported_names, namespaces)
            call transform_expression(statement.get("parent", None), own_functions, imported_names, namespaces)
            for member in statement["body"]:
                if member["kind"] == "function":
                    local_names = scoped_names(own_functions, member["parameters"], member["body"])
                    local_imports = scoped_names(imported_names, member["parameters"], member["body"])
                    call transform_statements(member["body"], local_names, local_imports, namespaces)
                elif member["kind"] == "assign":
                    call transform_expression(member["target"], own_functions, imported_names, namespaces)
                    call transform_expression(member["value"], own_functions, imported_names, namespaces)
                end
            end
        end
    end
end

function import_failure(name, path, owner_path, owner_source, statement, missing):
    code = "E3002"
    message = "cannot read library '" + name + "' from " + path
    hint = "check that " + path + " is a readable .lsl file and that its parent directories are accessible"
    if missing:
        code = "E3001"
        message = "library '" + name + "' was not found (not installed or missing local source)"
        relative = name.replace(".", "/") + ".lsl"
        hint = "check the name and local file " + dirname(owner_path) + "/" + relative
        if builtin_module(name):
            message = "built-in library '" + name + "' is missing from this LSL installation"
            hint = "repair or reinstall LSL; expected " + path + "; built-in libraries are not installed with lsl install"
        elif name.find(".") < 0 and len(name) <= 64 and name == name.lower() and not name.startswith("_"):
            hint += "; for registry packages use: lsl search " + name + " ; lsl install " + name
        end
    end
    lines = owner_source.split(chr(10))
    line = statement.get("line", 1)
    text = ""
    if line >= 1 and line <= len(lines):
        text = lines[line - 1]
    end
    call diagnostics.fail(owner_path, line, statement.get("module_column", statement.get("column", 1)), len(name), text, code, message, hint)
end

function mentions_system(value):
    if type(value) == "List":
        for item in value:
            if mentions_system(item):
                return True
            end
        end
    elif type(value) == "Dictionary":
        if value.get("kind", "") == "name" and value.get("name", "") == "system":
            return True
        end
        for field in value.keys():
            if mentions_system(value[field]):
                return True
            end
        end
    end
    return False
end

function import_system(program, path, source, cache, output, budget, internal, own, imports, namespaces):
    # Jméno system může v AST být jen tehdy, když je v textu modulu; levná
    # kontrola textu ušetří obecný průchod celým stromem u většiny modulů.
    if "system" not in own and "system" not in imports and "system" not in namespaces and "system" in source and mentions_system(program):
        entry = collect_module("os", path, cache, output, budget, internal, source, {"line": 1, "column": 1, "module_column": 1})
        imports["system"] = entry[0] + "run"
    end
end

# Returns the module entry [prefix, exports]: exports maps every public name
# of the module to its prefixed form, so a shared alias can pick the module
# that defines a member.
function collect_module(name, owner_path, cache, output, source_budget, internal_graph, owner_source, import_statement):
    # Platforma knihoven patří cíli překladu; bootstrap fasáda není host detekce.
    providers = source_budget[1]
    if name in providers:
        name = providers[name]
    end
    path = module_path(name, owner_path)
    if path in cache:
        return cache[path]
    end
    if len(cache) >= 256:
        Error(CompileError: "module graph exceeds 256 modules")
    end
    if not exists(path):
        call import_failure(name, path, owner_path, owner_source, import_statement, True)
    end
    source = ""
    try:
        source = readfile(path)
    else:
        call import_failure(name, path, owner_path, owner_source, import_statement, False)
    end
    source_bytes = __lsl_text_byte_length(source)
    # Byte counts have a fixed scalar representation across the internal ABI.
    # Keep platform-provider metadata in the surrounding heterogeneous pair.
    counter = IntArray(source_budget[0])
    if source_bytes > 16777216 - counter[0]:
        Error(CompileError: "linked source exceeds the 16 MiB compiler limit: " + path)
    end
    counter[0] += source_bytes
    program = parser.parse(path, source)
    call annotate_statements(program, path)
    call mark_trusted(program, builtin_module(name))
    internal_module = False
    if internal_graph:
        # Samostatné projekty (např. backend LuxIR) se označí stejnou značkou
        # jako vstupní zdroj; mimo důvěryhodný graf značka nic neznamená.
        internal_module = path.startswith("compiler/pure/") or path.find("/compiler/pure/") >= 0 or String(source).startswith("# lsl: internal-abi" + chr(10)) or String(source).startswith("# lsl: runtime" + chr(10))
    end
    call mark_internal_abi(program, internal_module)
    prefix = module_prefix(len(cache))
    entry = [prefix, {}]
    cache[path] = entry
    namespaces = {}
    imported_names = {}

    for statement in program:
        if statement["kind"] == "load":
            dependency = statement["module"]
            dependency_entry = collect_module(dependency, path, cache, output, source_budget, internal_graph, source, statement)
            if statement["symbol"] == None:
                call bind_namespace(namespaces, statement["alias"], dependency_entry)
            else:
                imported_names[statement["alias"]] = dependency_entry[0] + statement["symbol"]
            end
        end
    end

    own_functions = function_names(program)
    call import_system(program, path, source, cache, output, source_budget, internal_graph, own_functions, imported_names, namespaces)
    names = own_functions.keys()
    for function_name in names:
        own_functions[function_name] = prefix + function_name
    end
    for declaration in program:
        if private_class(declaration):
            own_functions[declaration["name"]] = prefix + "__private__" + declaration["name"]
        end
    end
    entry[1] = own_functions
    filtered = []
    for statement in program:
        if statement["kind"] != "load":
            filtered.append(statement)
        end
    end
    call transform_statements(filtered, own_functions, imported_names, namespaces)
    output.extend(filtered)
    return entry
end

# An alias names a list of module entries. `load a, b as x` appends both, so
# `x.member` resolves to the first listed module that exports the member.
function bind_namespace(namespaces, alias, entry):
    if alias not in namespaces:
        namespaces[alias] = []
    end
    namespaces[alias].append(entry)
end

function namespace_prefix(entries, member):
    for entry in entries:
        if member in entry[1]:
            return entry[0]
        end
    end
    return entries[0][0]
end

function link_mode_options(path, source, safety_mode, internal_graph, platform_module=""):
    if platform_module == "":
        platform_module = target.resolve(host.target_name())["platform_module"]
    end
    providers = target.modules_for_platform(platform_module)
    checked_source = String(source)
    source_bytes = __lsl_text_byte_length(checked_source)
    if source_bytes > 16777216:
        Error(CompileError: "linked source exceeds the 16 MiB compiler limit: " + path)
    end
    program = parser.parse(path, checked_source)
    call annotate_statements(program, path)
    call mark_trusted(program, False)
    call mark_internal_abi(program, internal_graph)
    cache = {}
    linked = []
    namespaces = {}
    imported_names = {}
    source_counter = IntArray()
    source_counter.append(source_bytes)
    source_budget = []
    source_budget.append(source_counter)
    source_budget.append(providers)
    for statement in program:
        if statement["kind"] == "load":
            dependency = statement["module"]
            entry = collect_module(dependency, path, cache, linked, source_budget, internal_graph, checked_source, statement)
            if statement["symbol"] == None:
                call bind_namespace(namespaces, statement["alias"], entry)
            else:
                imported_names[statement["alias"]] = entry[0] + statement["symbol"]
            end
        end
    end
    own_functions = function_names(program)
    call import_system(program, path, checked_source, cache, linked, source_budget, internal_graph, own_functions, imported_names, namespaces)
    filtered = []
    for statement in program:
        if statement["kind"] != "load":
            filtered.append(statement)
        end
    end
    call transform_statements(filtered, own_functions, imported_names, namespaces)
    linked.extend(filtered)
    if safety_mode != 0:
        call validate_safe_statements(linked, False, safety_mode == 2)
    end
    return linked
end


function link_mode(path, source, safety_mode):
    return link_mode_options(path, source, safety_mode, False)
end

function link(path, source):
    return link_mode(path, source, 0)
end

function link_internal(path, source):
    return link_mode_options(path, source, 0, True)
end

function link_checked(path, source, sandbox_mode):
    mode = 1
    if Bool(sandbox_mode):
        mode = 2
    end
    return link_mode(path, source, mode)
end
