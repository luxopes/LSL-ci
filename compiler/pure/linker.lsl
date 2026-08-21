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

function module_path_with_home(name, owner_path, home):
    relative_name = name.replace(".", "/") + ".lsl"
    local_path = dirname(owner_path) + "/" + relative_name
    if exists(local_path):
        return local_path
    end
    # Compiler-focused tests live under tests/, while implementation modules stay
    # exclusively in compiler/pure/. Allow those modules without test copies.
    compiler_path = "compiler/pure/" + relative_name
    test_owner = owner_path.startswith("tests/") or owner_path.find("/tests/") >= 0
    if test_owner and exists(compiler_path):
        return compiler_path
    end
    standard_path = "stdlib/" + relative_name
    if exists(standard_path):
        return standard_path
    end
    executable = executable_path()
    root_candidate = dirname(executable) + "/" + standard_path
    if exists(root_candidate):
        return root_candidate
    end
    root_candidate = dirname(dirname(dirname(executable))) + "/" + standard_path
    if exists(root_candidate):
        return root_candidate
    end
    prefix = dirname(dirname(executable))
    installed_path = prefix + "/lib/lsl/" + standard_path
    if exists(installed_path):
        return installed_path
    end
    # Registry libraries are user-owned and never shadow built-in modules.
    if home != None and home != "":
        user_path = home + "/.local/lib/lsl/stdlib/" + relative_name
        if exists(user_path):
            return user_path
        end
    end
    # Preserve the deterministic missing-file diagnostic path.
    return installed_path
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
        elif kind == "while" or kind == "loop" or kind == "safe":
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
        if kind == "function" or kind == "loop" or kind == "safe":
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
        elif kind == "loop" or kind == "safe":
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

function collect_module(name, owner_path, cache, output):
    if name in cache:
        return cache[name]
    end
    path = module_path(name, owner_path)
    source = readfile(path)
    program = parser.parse(path, source)
    call annotate_statements(program, path)
    prefix = module_prefix(name)
    cache[name] = prefix
    namespaces = {}
    imported_names = {}

    for statement in program:
        if statement["kind"] == "load":
            dependency = statement["module"]
            dependency_prefix = collect_module(dependency, path, cache, output)
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

function link(path, source):
    program = parser.parse(path, source)
    call annotate_statements(program, path)
    cache = {}
    linked = []
    namespaces = {}
    imported_names = {}
    for statement in program:
        if statement["kind"] == "load":
            dependency = statement["module"]
            prefix = collect_module(dependency, path, cache, linked)
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
    return linked
end
