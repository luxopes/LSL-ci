# Recursive AST module linker for the direct compiler. Module functions are
# flattened to deterministic prefixed native symbols; no runtime loader exists.

load parser

function dirname(path):
    slash = -1
    index = 0
    while index < len(path):
        if path[index] == "/":
            slash = index
        end
        index += 1
    end
    if slash < 0:
        return "."
    elif slash == 0:
        return "/"
    end
    return path[0:slash]
end

function module_alias(name):
    parts = name.split(".")
    return parts[len(parts) - 1]
end

function module_prefix(name):
    return name.replace(".", "__") + "__"
end

function builtin_module(name):
    builtins = "|ai|bigint|config|configure|css|cuda|display|env|fd|gfx|http|httpserver|input|json|lconf|lux|luxos|math|native|os|plugin|process|sandbox|system|tensor|time|tui|ui|unixsock|wayland|x11|"
    return "|" + String(name) + "|" in builtins
end

function module_path_with_home(name, owner_path, home):
    relative_name = name.replace(".", "/") + ".lsl"
    standard_path = "stdlib/" + relative_name
    executable = executable_path()
    binary_directory = dirname(executable)
    # Installed/repository resources adjacent to the compiler are trusted ahead
    # of the source directory, so local json.lsl/config.lsl files cannot shadow
    # security-critical built-in modules.
    root_candidate = binary_directory + "/" + standard_path
    if exists(root_candidate):
        return root_candidate
    end
    root_candidate = dirname(dirname(dirname(executable))) + "/" + standard_path
    if exists(root_candidate):
        return root_candidate
    end
    prefix = dirname(binary_directory)
    prefix_bin = prefix + "/bin"
    if prefix == "/":
        prefix_bin = "/bin"
    end
    installed_layout = binary_directory == prefix_bin
    installed_path = prefix + "/lib/lsl/" + standard_path
    if installed_layout:
        if exists(installed_path) or builtin_module(name):
            # A missing built-in fails at its trusted prefix path. Local/user
            # modules remain available for names outside the built-in set.
            return installed_path
        end
    end
    local_path = dirname(owner_path) + "/" + relative_name
    if exists(local_path):
        return local_path
    end
    # Compiler-focused tests live under tests/, while implementation modules stay
    # exclusively in compiler/pure/. Prefer a path rooted beside the compiler.
    test_owner = owner_path.startswith("tests/") or owner_path.find("/tests/") >= 0
    compiler_path = dirname(dirname(dirname(executable))) + "/compiler/pure/" + relative_name
    if test_owner and exists(compiler_path):
        return compiler_path
    end
    compiler_path = "compiler/pure/" + relative_name
    if test_owner and exists(compiler_path):
        return compiler_path
    end
    # Development compiler copied outside the tree: cwd is an explicit fallback,
    # never a precedence path for installed binaries.
    if exists(standard_path):
        return standard_path
    end
    # Registry libraries are user-owned and never shadow built-in modules.
    if home != None and home != "":
        user_path = home + "/.local/lib/lsl/stdlib/" + relative_name
        if exists(user_path):
            return user_path
        end
    end
    # Preserve the deterministic missing-file diagnostic path.
    if installed_layout:
        return installed_path
    end
    return standard_path
end

function module_path(name, owner_path):
    return module_path_with_home(name, owner_path, __lsl_getenv("HOME"))
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
    if kind == "member":
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
    if kind == "name":
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
    if kind == "name":
        name = expression["name"]
        # `origin` is the reserved immediate-parent receiver inside inherited
        # methods. It must survive module namespace rewriting unchanged.
        if name == "origin":
            return None
        elif name in imported_names:
            expression["name"] = imported_names[name]
        elif name in own_functions:
            expression["name"] = own_functions[name]
        end
    elif kind == "member":
        target = expression["target"]
        transformed_namespace = False
        if target["kind"] == "name":
            if target["name"] in namespaces:
                expression["kind"] = "name"
                expression["name"] = namespaces[target["name"]] + expression["name"]
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
            call transform_statements(statement["body"], local_names, imported_names, namespaces)
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
        elif kind == "class":
            statement["name"] = own_functions[statement["name"]]
            call transform_expression(statement["condition"], own_functions, imported_names, namespaces)
            call transform_expression(statement.get("parent", None), own_functions, imported_names, namespaces)
            for member in statement["body"]:
                if member["kind"] == "function":
                    local_names = scoped_names(own_functions, member["parameters"], member["body"])
                    call transform_statements(member["body"], local_names, imported_names, namespaces)
                elif member["kind"] == "assign":
                    call transform_expression(member["target"], own_functions, imported_names, namespaces)
                    call transform_expression(member["value"], own_functions, imported_names, namespaces)
                end
            end
        end
    end
end

function collect_module(name, owner_path, cache, output, source_budget):
    if name in cache:
        return cache[name]
    end
    if len(cache) >= 256:
        Error(CompileError: "module graph exceeds 256 modules")
    end
    path = module_path(name, owner_path)
    source = readfile(path)
    source_bytes = __lsl_text_byte_length(source)
    if source_bytes > 16777216 - source_budget[0]:
        Error(CompileError: "linked source exceeds the 16 MiB compiler limit: " + path)
    end
    source_budget[0] += source_bytes
    program = parser.parse(path, source)
    call annotate_statements(program, path)
    call mark_trusted(program, builtin_module(name))
    prefix = module_prefix(name)
    cache[name] = prefix
    namespaces = {}
    imported_names = {}

    for statement in program:
        if statement["kind"] == "load":
            dependency = statement["module"]
            dependency_prefix = collect_module(dependency, path, cache, output, source_budget)
            if statement["symbol"] == None:
                namespaces[statement["alias"]] = dependency_prefix
            else:
                imported_names[statement["alias"]] = dependency_prefix + statement["symbol"]
            end
        end
    end

    own_functions = function_names(program)
    names = own_functions.keys()
    for function_name in names:
        own_functions[function_name] = prefix + function_name
    end
    for declaration in program:
        if private_class(declaration):
            own_functions[declaration["name"]] = prefix + "__private__" + declaration["name"]
        end
    end
    filtered = []
    for statement in program:
        if statement["kind"] != "load":
            filtered.append(statement)
        end
    end
    call transform_statements(filtered, own_functions, imported_names, namespaces)
    output.extend(filtered)
    return prefix
end

function link_mode(path, source, safety_mode):
    checked_source = String(source)
    source_bytes = __lsl_text_byte_length(checked_source)
    if source_bytes > 16777216:
        Error(CompileError: "linked source exceeds the 16 MiB compiler limit: " + path)
    end
    program = parser.parse(path, checked_source)
    call annotate_statements(program, path)
    call mark_trusted(program, False)
    cache = {}
    linked = []
    namespaces = {}
    imported_names = {}
    source_budget = IntArray()
    source_budget.append(source_bytes)
    for statement in program:
        if statement["kind"] == "load":
            dependency = statement["module"]
            prefix = collect_module(dependency, path, cache, linked, source_budget)
            if statement["symbol"] == None:
                namespaces[statement["alias"]] = prefix
            else:
                imported_names[statement["alias"]] = prefix + statement["symbol"]
            end
        end
    end
    own_functions = function_names(program)
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

function link(path, source):
    return link_mode(path, source, 0)
end

function link_checked(path, source, sandbox_mode):
    mode = 1
    if Bool(sandbox_mode):
        mode = 2
    end
    return link_mode(path, source, mode)
end
