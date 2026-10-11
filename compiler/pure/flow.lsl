# Definite assignment before native emission. A local slot is never a value
# until every reachable path to its read has assigned it. No runtime flags.
load diagnostics

# Expression child order is part of definite-assignment analysis. Known
# expression shapes avoid allocating and probing the entire field list at
# each leaf; the fallback preserves traversal of other AST shapes.
EXPRESSION_FIELDS = {
    "literal": [],
    "binary": ["left", "right"],
    "unary": ["operand"],
    "compare": ["operands"],
    "call": ["target", "arguments"],
    "member": ["target"],
    "index": ["target", "index"],
    "slice": ["target", "start", "stop", "step"],
    "list": ["items"],
    "tuple": ["items"],
    "real_array": ["items"],
    "dictionary": ["entries"]
}
OTHER_EXPRESSION_FIELDS = ["target", "value", "condition", "expression", "iterable", "left", "right", "operand", "index", "start", "stop", "step", "message", "parent", "arguments", "items", "operands", "expressions", "entries"]

function terminating_call(node, known):
    if type(node) != "Dictionary" or node.get("kind", "") != "call":
        return False
    end
    target = node["target"]
    return target["kind"] == "name" and (target["name"] == "exit" or target["name"] in known)
end

function never_returns(body, known):
    for statement in body:
        kind = statement["kind"]
        if kind == "error":
            return True
        elif kind == "return":
            return False
        elif kind == "expression" and terminating_call(statement["expression"], known):
            return True
        elif kind == "if":
            all_stop = never_returns(statement["otherwise"], known)
            for branch in statement["branches"]:
                all_stop = all_stop and never_returns(branch[1], known)
            end
            if all_stop:
                return True
            end
        elif kind == "unsafe" and never_returns(statement["body"], known):
            return True
        end
    end
    return False
end

function noreturn_functions(functions):
    known = {}
    changed = True
    while changed:
        changed = False
        for name in functions.keys():
            if name not in known and never_returns(functions[name]["body"], known):
                known[name] = True
                changed = True
            end
        end
    end
    return known
end

function meet(left, right):
    if left == None:
        return right
    elif right == None:
        return left
    end
    result = {}
    for name in left.keys():
        if name in right:
            result[name] = True
        end
    end
    return result
end

function fail(context, node):
    path = node.get("path", context["path"])
    source = context["source"]
    if path != context["path"] and exists(path):
        source = readfile(path)
    end
    lines = source.split(chr(10))
    line = node.get("line", 1)
    text = ""
    if line >= 1 and line <= len(lines):
        text = lines[line - 1]
    end
    name = String(node["name"]).split("@")[-1]
    call diagnostics.fail(path, line, node.get("column", 1), max(1, node.get("end_column", 2) - node.get("column", 1)), text, "E2002", "variable '" + name + "' may be read before assignment", "assign '" + name + "' on every path before reading it; += and -= also read the previous value")
end

function expression(context, node, assigned):
    if type(node) == "List":
        for item in node:
            call expression(context, item, assigned)
        end
        return
    elif type(node) != "Dictionary":
        return
    end
    kind = node.get("kind", "")
    if kind == "name":
        if node["name"] in context["locals"] and node["name"] not in assigned:
            call fail(context, node)
        elif node["name"] in context["globals"] and (context["module"] or node["name"] not in context["locals"]):
            context["global_reads"][node["name"]] = node
        end
        return
    elif kind == "comprehension":
        result = statements(context, node["body"], Dictionary(assigned), None)
        if result != None:
            call expression(context, node["result"], result)
            for name in result.keys():
                assigned[name] = True
            end
        end
        return
    elif kind == "binary" and (node["operator"] == "and" or node["operator"] == "or"):
        call expression(context, node["left"], assigned)
        truth = context["truth"]
        constant = truth(node["left"])
        if constant[0]:
            if (node["operator"] == "and" and not constant[1]) or (node["operator"] == "or" and constant[1]):
                return
            end
        end
        call expression(context, node["right"], assigned)
        return
    end
    for field in EXPRESSION_FIELDS.get(kind, OTHER_EXPRESSION_FIELDS):
        if field in node:
            call expression(context, node[field], assigned)
        end
    end
end

function remove_deleted(body, assigned):
    for statement in body:
        kind = statement["kind"]
        if kind == "delete" and statement["target"]["kind"] == "name":
            name = statement["target"]["name"]
            if name in assigned:
                del(assigned[name])
            end
        elif kind != "function" and kind != "class":
            if "body" in statement:
                call remove_deleted(statement["body"], assigned)
            end
            if "otherwise" in statement:
                call remove_deleted(statement["otherwise"], assigned)
            end
            if "branches" in statement:
                for branch in statement["branches"]:
                    call remove_deleted(branch[1], assigned)
                end
            end
        end
    end
end

# Celočíselný literál (i se znaménkem) jako [True, hodnota], jinak [False, 0].
# V interním ABI jsou None a 0 stejná raw hodnota, proto dvojice.
function literal_integer(node):
    sign = 1
    if node["kind"] == "unary" and node["operator"] == "-":
        sign = -1
        node = node["operand"]
    end
    if node["kind"] == "literal" and node.get("literal_kind", "") == "number" and "integer_value" in node:
        return [True, sign * __lsl_typed_int(node["integer_value"])]
    end
    return [False, 0]
end

# Smyčka, která prokazatelně proběhne aspoň jednou: rang s literály dávající
# aspoň jednu hodnotu nebo neprázdný literál List/Tuple/String. Jinak False.
function nonempty_iterable(node):
    kind = node["kind"]
    if kind == "list" or kind == "tuple" or kind == "real_array":
        return len(node["items"]) > 0
    elif kind == "literal" and node.get("literal_kind", "") == "string":
        return len(node["value"]) > 0
    elif kind == "call" and node["target"]["kind"] == "name" and (node["target"]["name"] == "rang" or node["target"]["name"] == "range") and "argument_names" not in node:
        values = []
        for argument in node["arguments"]:
            number = literal_integer(argument)
            if not number[0]:
                return False
            end
            values.append(number[1])
        end
        if len(values) == 1:
            return values[0] > 0
        elif len(values) == 2:
            return values[0] < values[1]
        elif len(values) == 3:
            return (values[2] > 0 and values[0] < values[1]) or (values[2] < 0 and values[0] > values[1])
        end
    end
    return False
end

function statements(context, body, assigned, loop_state):
    for statement in body:
        if assigned == None:
            break
        end
        kind = statement["kind"]
        if kind == "assign":
            target = statement["target"]
            if target["kind"] == "name" and target["name"] not in assigned:
                statement["init_flag"] = True
            end
            if target["kind"] != "name" or statement["operator"] != "=":
                call expression(context, target, assigned)
            end
            call expression(context, statement["value"], assigned)
            if target["kind"] == "name":
                assigned[target["name"]] = True
            end
        elif kind == "delete":
            target = statement["target"]
            call expression(context, target, assigned)
            if target["kind"] == "name" and target["name"] in assigned:
                del(assigned[target["name"]])
            end
        elif kind == "if":
            select = context["select"]
            selected = select(statement)
            if selected[0]:
                assigned = statements(context, selected[1], assigned, loop_state)
            else:
                merged = None
                for branch in statement["branches"]:
                    call expression(context, branch[0], assigned)
                    merged = meet(merged, statements(context, branch[1], Dictionary(assigned), loop_state))
                end
                assigned = meet(merged, statements(context, statement["otherwise"], Dictionary(assigned), loop_state))
            end
        elif kind == "while" or kind == "loop" or kind == "for":
            truth = context["truth"]
            condition = [True, True]
            if kind == "while":
                call expression(context, statement["condition"], assigned)
                condition = truth(statement["condition"])
            elif kind == "for":
                call expression(context, statement["iterable"], assigned)
                condition = [False, False]
                if statement["name"] not in assigned:
                    statement["init_flag"] = True
                end
            end
            if kind == "while" and condition[0] and not condition[1]:
                continue
            end
            entry = Dictionary(assigned)
            if kind == "for":
                entry[statement["name"]] = True
                entry[statement["iterator_name"]] = True
                entry[statement["index_name"]] = True
            end
            edges = {"breaks": None, "continues": None}
            first_entry = Dictionary(entry)
            backedge = statements(context, statement["body"], entry, edges)
            backedge = meet(backedge, edges["continues"])
            nonempty = kind == "for" and nonempty_iterable(statement["iterable"])
            # Neprázdná smyčka skončí až po některém průchodu tělem.
            exits = meet(backedge, edges["breaks"])
            # A deletion on a back edge must not expose a stale slot in the
            # next condition/body, even if the first iteration was initialized.
            if backedge != None:
                next_entry = meet(assigned, backedge)
                if kind == "while":
                    call expression(context, statement["condition"], next_entry)
                end
                if kind == "for":
                    next_entry[statement["name"]] = True
                    next_entry[statement["iterator_name"]] = True
                    next_entry[statement["index_name"]] = True
                end
                if next_entry != first_entry:
                    next_edges = {"breaks": None, "continues": None}
                    next_backedge = statements(context, statement["body"], next_entry, next_edges)
                    exits = meet(exits, meet(meet(next_backedge, next_edges["continues"]), next_edges["breaks"]))
                end
            end
            if condition[0] and condition[1]:
                assigned = edges["breaks"]
            elif nonempty:
                assigned = exits
            else:
                assigned = meet(assigned, backedge)
                assigned = meet(assigned, edges["breaks"])
            end
        elif kind == "break":
            if loop_state != None:
                loop_state["breaks"] = meet(loop_state["breaks"], assigned)
            end
            assigned = None
        elif kind == "continue":
            if loop_state != None:
                loop_state["continues"] = meet(loop_state["continues"], assigned)
            end
            assigned = None
        elif kind == "unsafe":
            assigned = statements(context, statement["body"], assigned, loop_state)
        elif kind == "safe" or kind == "try":
            failure = Dictionary(assigned)
            call remove_deleted(statement["body"], failure)
            normal = statements(context, statement["body"], Dictionary(assigned), loop_state)
            if kind == "try":
                failure = statements(context, statement["otherwise"], failure, loop_state)
            end
            assigned = meet(normal, failure)
        elif kind == "class":
            call expression(context, statement["condition"], assigned)
            call expression(context, statement.get("parent", None), assigned)
            truth = context["truth"]
            condition = [True, True]
            if statement["condition"] != None:
                condition = truth(statement["condition"])
            end
            if condition[0] and not condition[1]:
                continue
            end
            if statement["name"] not in assigned:
                statement["init_flag"] = True
            end
            if condition[0] and condition[1]:
                assigned[statement["name"]] = True
            end
            for member in statement["body"]:
                if member["kind"] == "assign":
                    call expression(context, member["value"], assigned)
                end
            end
        elif kind != "function":
            call expression(context, statement, assigned)
            if kind == "return" or kind == "error":
                assigned = None
            elif kind == "expression" and terminating_call(statement["expression"], context["noreturn"]):
                assigned = None
            end
        end
    end
    return assigned
end

function deleted_names(value, result):
    if type(value) == "List":
        for item in value:
            call deleted_names(item, result)
        end
    elif type(value) == "Dictionary":
        if value.get("kind", "") == "delete" and value["target"]["kind"] == "name":
            result[value["target"]["name"]] = True
        end
        for field in value.keys():
            call deleted_names(value[field], result)
        end
    end
end

function check(path, source, body, locals, parameters, truth, select, noreturn, globals, module=False):
    assigned = {}
    for name in parameters:
        assigned[name] = True
    end
    context = {"path": path, "source": source, "locals": locals, "truth": truth, "select": select, "noreturn": noreturn, "globals": globals, "global_reads": {}, "module": module}
    call statements(context, body, assigned, None)
    return context["global_reads"]
end
