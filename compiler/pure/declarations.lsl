# Lower explicit lexical type constraints before inference and native emission.
load diagnostics

function fail(path, source, node, message):
    actual = node.get("path", path)
    text = source
    if actual != path and exists(actual):
        text = readfile(actual)
    end
    lines = text.split(chr(10))
    line = node.get("line", 1)
    call diagnostics.fail(actual, line, node.get("column", 1), 1, lines[line - 1], "E2003", message, "use one consistent built-in type for each variable in its scope")
end

function collect(value, types, path, source):
    if type(value) == "List":
        for item in value:
            call collect(item, types, path, source)
        end
    elif type(value) == "Dictionary":
        kind = value.get("kind", "")
        if kind == "function" or kind == "class":
            return
        end
        if "declared_type" in value:
            name = value["target"]["name"]
            declared = value["declared_type"]
            if name in types and types[name] != declared:
                call fail(path, source, value, "conflicting declared types for '" + name + "'")
            end
            types[name] = declared
        end
        for field in value.keys():
            call collect(value[field], types, path, source)
        end
    end
end

function checked_assignment(template, name, expression, declared):
    assignment = Dictionary(template)
    assignment["kind"] = "assign"
    assignment["target"] = {"kind": "name", "name": name}
    assignment["target"]["line"] = template["line"]
    assignment["target"]["column"] = template["column"]
    assignment["target"]["end_column"] = template["end_column"]
    assignment["operator"] = "="
    assignment["value"] = expression
    assignment["declared_type"] = declared
    return assignment
end

function rewrite(value, types, path, source, serial):
    if type(value) == "List":
        for item in value:
            call rewrite(item, types, path, source, serial)
        end
    elif type(value) == "Dictionary":
        kind = value.get("kind", "")
        if kind == "function":
            call scope(value["body"], value["parameters"], path, source, serial)
            return
        elif kind == "class":
            if value["name"] in types:
                call fail(path, source, value, "class name conflicts with typed variable '" + value["name"] + "'")
            end
            call scope(value["body"], [], path, source, serial)
            return
        end
        if kind == "for" and value["name"] in types:
            name = value["name"]
            temporary = "@typed_for@" + String(serial[0])
            serial[0] += 1
            value["name"] = temporary
            reference = {"kind": "name", "name": temporary, "line": value["line"], "column": value["column"], "end_column": value["end_column"]}
            assignment = checked_assignment(value, name, reference, types[name])
            # Do not retain the loop's body/iterable in the new assignment.
            del(assignment["body"])
            del(assignment["iterable"])
            loop_body = [assignment]
            call loop_body.extend(value["body"])
            value["body"] = loop_body
        end
        for field in value.keys():
            call rewrite(value[field], types, path, source, serial)
        end
        if kind == "assign" and value["target"]["kind"] == "name":
            name = value["target"]["name"]
            if name in types and types[name] != "Any":
                expression = value["value"]
                if value["operator"] != "=":
                    expression = {"kind": "binary", "operator": value["operator"][0:len(value["operator"]) - 1], "left": value["target"], "right": expression, "line": value["line"], "column": value["column"], "end_column": value["end_column"]}
                end
                wrapper = {"kind": "call", "target": {"kind": "name", "name": "__lsl_declared_" + types[name]}, "arguments": [expression], "line": value["line"], "column": value["column"], "end_column": value["end_column"]}
                if "path" in value:
                    wrapper["path"] = value["path"]
                end
                value["value"] = wrapper
                value["operator"] = "="
                value["declared_type"] = types[name]
            end
        end
    end
end

function scope(body, parameters, path, source, serial):
    types = {}
    call collect(body, types, path, source)
    for parameter in parameters:
        if parameter in types:
            # A declaration constrains a variable, not an existing parameter's
            # incoming ABI. Keep parameter annotations a separate feature.
            call fail(path, source, body[0], "typed declaration cannot redeclare parameter '" + parameter + "'; use a new local variable")
        end
    end
    call rewrite(body, types, path, source, serial)
end

function lower(program, path, source):
    call scope(program, [], path, source, [0])
end
