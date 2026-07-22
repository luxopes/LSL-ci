# Native scalar/control-flow code generator over the token-span AST.

load assembler
load bytes
load diagnostics
load elf_image
load native_runtime
load parser
load x86_64

function context(path, lines, syntax):
    line = syntax["line"]
    source = ""
    actual_path = path
    if "path" in syntax:
        actual_path = syntax["path"]
    end
    if "source" in syntax:
        source = syntax["source"]
    elif line >= 1 and line <= len(lines):
        source = lines[line - 1]
    end
    return {"path": actual_path, "line": line, "column": syntax["column"], "source": source}
end

function unsupported(path, lines, syntax, message, help_text):
    width = max(1, syntax["end_column"] - syntax["column"])
    details = context(path, lines, syntax)
    call diagnostics.fail(details["path"], syntax["line"], syntax["column"], width, details["source"], "E2001", message, help_text)
end

function label_name(generator, prefix):
    counter = generator["counter"]
    generator["counter"] = counter + 1
    return prefix + "_" + String(counter)
end

function collect_variables(statements, variables):
    for statement in statements:
        kind = statement["kind"]
        if kind == "class":
            name = statement["name"]
            if name not in variables:
                variables[name] = -(len(variables) + 1) * 8
            end
        elif kind == "assign":
            if statement["target"]["kind"] == "name":
                name = statement["target"]["name"]
                if name not in variables:
                    variables[name] = -(len(variables) + 1) * 8
                end
            end
        elif kind == "if":
            for branch in statement["branches"]:
                call collect_variables(branch[1], variables)
            end
            call collect_variables(statement["otherwise"], variables)
        elif kind == "while" or kind == "loop":
            call collect_variables(statement["body"], variables)
        elif kind == "safe" or kind == "try":
            call collect_variables(statement["body"], variables)
            call collect_variables(statement["otherwise"], variables)
        elif kind == "for":
            name = statement["name"]
            if name not in variables:
                variables[name] = -(len(variables) + 1) * 8
            end
            iterator_name = "__iterator_" + String(len(variables))
            variables[iterator_name] = -(len(variables) + 1) * 8
            index_name = "__iterator_index_" + String(len(variables))
            variables[index_name] = -(len(variables) + 1) * 8
            statement["iterator_name"] = iterator_name
            statement["index_name"] = index_name
            call collect_variables(statement["body"], variables)
        end
    end
end

function infer_expression_type(syntax, types, function_returns):
    if syntax == None:
        return "None"
    end
    kind = syntax["kind"]
    if kind == "literal":
        if syntax["literal_kind"] == "string":
            return "String"
        elif syntax["literal_kind"] == "number":
            if syntax["value"].find(".") >= 0 or syntax["value"].find("e") >= 0 or syntax["value"].find("E") >= 0:
                return "Float"
            end
            return "Int"
        elif syntax["value"] == "True" or syntax["value"] == "False":
            return "Bool"
        end
        return "None"
    elif kind == "name":
        if syntax["name"] in function_returns:
            return "Function"
        end
        return types.get(syntax["name"], "Any")
    elif kind == "list":
        return "List"
    elif kind == "tuple":
        return "Tuple"
    elif kind == "real_array":
        return "RealArray"
    elif kind == "dictionary":
        return "Dictionary"
    elif kind == "compare":
        return "Bool"
    elif kind == "unary":
        if syntax["operator"] == "not":
            return "Bool"
        end
        return infer_expression_type(syntax["operand"], types, function_returns)
    elif kind == "binary":
        left = infer_expression_type(syntax["left"], types, function_returns)
        right = infer_expression_type(syntax["right"], types, function_returns)
        if syntax["operator"] == "+":
            if left == "String" or right == "String":
                return "String"
            elif left == "List" and right == "List":
                return "List"
            elif left == "Float" or right == "Float":
                return "Float"
            elif left == "Any" or right == "Any":
                return "Any"
            end
        elif syntax["operator"] == "*":
            if (left == "String" and right == "Int") or (left == "Int" and right == "String"):
                return "String"
            elif left == "Float" or right == "Float":
                return "Float"
            end
        elif syntax["operator"] == "-" or syntax["operator"] == "/":
            if left == "Float" or right == "Float" or syntax["operator"] == "/":
                return "Float"
            end
        elif syntax["operator"] == "**":
            if left == "Float" or right == "Float":
                return "Float"
            end
        end
        if syntax["operator"] == "and" or syntax["operator"] == "or":
            return "Bool"
        end
        return "Int"
    elif kind == "index":
        target_type = infer_expression_type(syntax["target"], types, function_returns)
        if target_type == "String":
            return "String"
        end
        return "Any"
    elif kind == "slice":
        return infer_expression_type(syntax["target"], types, function_returns)
    elif kind == "call":
        target = syntax["target"]
        if target["kind"] == "name":
            name = target["name"]
            if name == "len" or name == "Int" or name == "ord" or name == "sum" or name == "min" or name == "max" or name == "arg_count" or name == "run":
                return "Int"
            elif name == "Float":
                return "Float"
            elif name == "Bool":
                return "Bool"
            elif name == "String" or name == "chr" or name == "arg" or name == "input" or name == "readfile" or name == "last_error" or name == "type" or name == "capture" or name == "executable_path":
                return "String"
            elif name == "clock":
                return "Float"
            elif name == "exists":
                return "Bool"
            elif name == "List":
                return "List"
            elif name == "Tuple":
                return "Tuple"
            elif name == "RealArray":
                return "RealArray"
            elif name == "Dictionary":
                return "Dictionary"
            elif "__class__" + name in function_returns:
                return function_returns["__class__" + name]
            elif name in function_returns:
                return function_returns[name]
            end
        elif target["kind"] == "member":
            member = target["name"]
            if member == "append" or member == "extend" or member == "sort" or member == "clear":
                return "None"
            elif member == "strip" or member == "lstrip" or member == "rstrip" or member == "join" or member == "replace" or member == "lower" or member == "upper" or member == "title":
                return "String"
            elif member == "split" or member == "keys" or member == "values" or member == "items":
                return "List"
            elif member == "copy":
                return infer_expression_type(target["target"], types, function_returns)
            elif member == "startswith" or member == "endswith":
                return "Bool"
            elif member == "find" or member == "index" or member == "count":
                return "Int"
            end
        end
    end
    return "Any"
end

function collect_types(statements, types, function_returns):
    for statement in statements:
        kind = statement["kind"]
        if kind == "class":
            types[statement["name"]] = "Class:" + statement["name"]
        elif kind == "assign":
            if statement["target"]["kind"] == "name":
                name = statement["target"]["name"]
                if statement["operator"] == "=" or name not in types:
                    assigned_type = infer_expression_type(statement["value"], types, function_returns)
                    if name in types and types[name] != assigned_type:
                        types[name] = "Any"
                    else:
                        types[name] = assigned_type
                    end
                end
            end
        elif kind == "for":
            iterable_type = infer_expression_type(statement["iterable"], types, function_returns)
            if iterable_type == "String":
                types[statement["name"]] = "String"
            elif iterable_type == "List" or iterable_type == "Tuple" or iterable_type == "RealArray":
                types[statement["name"]] = "Any"
            else:
                types[statement["name"]] = "Int"
            end
            call collect_types(statement["body"], types, function_returns)
        elif kind == "if":
            for branch in statement["branches"]:
                call collect_types(branch[1], types, function_returns)
            end
            call collect_types(statement["otherwise"], types, function_returns)
        elif kind == "while" or kind == "loop":
            call collect_types(statement["body"], types, function_returns)
        elif kind == "safe" or kind == "try":
            call collect_types(statement["body"], types, function_returns)
            call collect_types(statement["otherwise"], types, function_returns)
        end
    end
end

function method_function(name):
    if name == "strip":
        return "__lsl_strip"
    elif name == "lower":
        return "__lsl_lower"
    elif name == "upper":
        return "__lsl_upper"
    elif name == "title":
        return "__lsl_title"
    elif name == "lstrip":
        return "__lsl_lstrip"
    elif name == "rstrip":
        return "__lsl_rstrip"
    elif name == "startswith":
        return "__lsl_startswith"
    elif name == "endswith":
        return "__lsl_endswith"
    elif name == "find":
        return "__lsl_find"
    elif name == "split":
        return "__lsl_split"
    elif name == "join":
        return "__lsl_join"
    elif name == "count":
        return "__lsl_count"
    elif name == "extend":
        return "__lsl_extend"
    elif name == "replace":
        return "__lsl_replace"
    elif name == "insert":
        return "__lsl_insert"
    elif name == "remove":
        return "__lsl_remove"
    elif name == "sort":
        return "__lsl_sort"
    elif name == "copy":
        return "__lsl_copy"
    elif name == "get":
        return "__lsl_dict_get"
    elif name == "setdefault":
        return "__lsl_setdefault"
    elif name == "update":
        return "__lsl_update"
    end
    return ""
end

function comparison_opcode(operator):
    if operator == "==" or operator == "is":
        return 148
    elif operator == "!=" or operator == "is not":
        return 149
    elif operator == "<":
        return 156
    elif operator == "<=":
        return 158
    elif operator == ">":
        return 159
    elif operator == ">=":
        return 157
    end
    return -1
end

function align_data(generator):
    while len(generator["data"]) % 8 != 0:
        generator["data"].append(0)
    end
end

function emit_string_pointer(generator, text):
    call align_data(generator)
    offset = len(generator["data"])
    payload = bytes.utf8(text)
    generator["data"].extend(bytes.little(1, 8))
    generator["data"].extend(bytes.little(len(payload), 8))
    generator["data"].extend(payload)
    generator["data"].append(0)
    lea_start = assembler.position(generator["builder"])
    call assembler.emit(generator["builder"], x86_64.lea_rip(0, 0))
    generator["relocations"].append([lea_start + 3, lea_start + 7, offset])
    call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
    call assembler.relative(generator["builder"], [232], "runtime_string_clone")
end

function float_bits(text):
    digits = ""
    denominator = 1
    exponent = 0
    exponent_sign = 1
    after_dot = False
    in_exponent = False
    for character in text:
        if character == ".":
            after_dot = True
        elif character == "e" or character == "E":
            in_exponent = True
        elif in_exponent:
            if character == "-":
                exponent_sign = -1
            elif character != "+":
                exponent = exponent * 10 + ord(character) - 48
            end
        else:
            digits += character
            if after_dot:
                denominator *= 10
            end
        end
    end
    numerator = Int(digits)
    exponent *= exponent_sign
    while exponent > 0:
        numerator *= 10
        exponent -= 1
    end
    while exponent < 0:
        denominator *= 10
        exponent += 1
    end
    if numerator == 0:
        return 0
    end
    exponent = 0
    while numerator >= denominator * 2:
        denominator *= 2
        exponent += 1
    end
    while numerator < denominator:
        numerator *= 2
        exponent -= 1
    end
    remainder = numerator - denominator
    mantissa = 0
    for bit_index in rang(52):
        mantissa *= 2
        remainder *= 2
        if remainder >= denominator:
            mantissa += 1
            remainder -= denominator
        end
    end
    remainder *= 2
    if remainder >= denominator:
        mantissa += 1
    end
    if mantissa >= 4503599627370496:
        mantissa = 0
        exponent += 1
    end
    return (exponent + 1023) * 4503599627370496 + mantissa
end

function emit_truth(generator):
    call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
    call assembler.relative(generator["builder"], [232], "runtime_truth")
end

function condition_is_bool(syntax):
    kind = syntax["kind"]
    if kind == "compare":
        return True
    elif kind == "unary":
        return syntax["operator"] == "not"
    elif kind == "binary":
        return syntax["operator"] == "and" or syntax["operator"] == "or"
    elif kind == "literal":
        return syntax["value"] == "True" or syntax["value"] == "False"
    elif kind == "call":
        if syntax["target"]["kind"] == "name":
            return syntax["target"]["name"] == "Bool"
        end
    end
    return False
end

function emit_condition(generator, syntax):
    # Skip runtime_truth (a call + is_heap_object probe) when the expression
    # already yields a 0/1 Bool.
    call emit_expression(generator, syntax)
    if not condition_is_bool(syntax):
        call emit_truth(generator)
    end
end

function is_int_leaf(generator, syntax):
    kind = syntax["kind"]
    if kind == "literal":
        if syntax["literal_kind"] == "number":
            value = syntax["value"]
            return value.find(".") < 0 and value.find("e") < 0 and value.find("E") < 0
        end
        return False
    elif kind == "name":
        name = syntax["name"]
        return name in generator["variables"] or name in generator["global_variables"]
    end
    return False
end

function emit_int_leaf(generator, syntax, register):
    output = generator["builder"]
    if syntax["kind"] == "literal":
        call assembler.emit(output, x86_64.mov_imm64(register, Int(syntax["value"])))
    else:
        name = syntax["name"]
        if name in generator["variables"]:
            call assembler.emit(output, x86_64.load_stack(register, generator["variables"][name]))
        else:
            call assembler.emit(output, x86_64.load_memory(register, 12, generator["global_variables"][name]))
        end
    end
end

function emit_collection_box(generator, syntax):
    value_type = infer_expression_type(syntax, generator["types"], generator["function_returns"])
    if value_type == "Bool":
        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
        call assembler.relative(generator["builder"], [232], "runtime_box_bool")
    elif value_type == "None":
        call assembler.relative(generator["builder"], [232], "runtime_box_none")
    end
end

function emit_uncaught_runtime_error(generator):
    call emit_static_write_fd(generator, "LSL runtime error: ", 2)
    call assembler.emit(generator["builder"], x86_64.load_memory(2, 13, 8))
    call assembler.emit(generator["builder"], x86_64.lea_base(6, 13, 16))
    call assembler.emit(generator["builder"], x86_64.mov_imm64(7, 2))
    call assembler.emit(generator["builder"], x86_64.mov_imm64(0, 1))
    call assembler.emit(generator["builder"], x86_64.syscall())
    call emit_static_write_fd(generator, chr(10), 2)
    call assembler.emit(generator["builder"], x86_64.mov_imm64(7, 1))
    call assembler.emit(generator["builder"], x86_64.mov_imm64(0, 60))
    call assembler.emit(generator["builder"], x86_64.syscall())
end

function emit_pending_error(generator):
    call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(14, 0))
    if generator["error_label"] != "":
        call assembler.relative(generator["builder"], [15, 133], generator["error_label"])
    else:
        pending_error_clear = label_name(generator, "pending_error_clear")
        call assembler.relative(generator["builder"], [15, 132], pending_error_clear)
        call emit_uncaught_runtime_error(generator)
        call assembler.label(generator["builder"], pending_error_clear)
    end
end

function emit_runtime_raise(generator, message):
    call emit_string_pointer(generator, message)
    call assembler.emit(generator["builder"], x86_64.move_reg_reg(13, 0))
    call assembler.emit(generator["builder"], x86_64.mov_imm64(14, 1))
    if generator["error_label"] != "":
        call assembler.relative(generator["builder"], [233], generator["error_label"])
    else:
        call emit_static_write_fd(generator, "LSL runtime error: " + message + chr(10), 2)
        call assembler.emit(generator["builder"], x86_64.mov_imm64(7, 1))
        call assembler.emit(generator["builder"], x86_64.mov_imm64(0, 60))
        call assembler.emit(generator["builder"], x86_64.syscall())
    end
end

function emit_bounds_check(generator, syntax):
    source_path = syntax.get("path", generator["path"])
    bounds_nonnegative = label_name(generator, "bounds_nonnegative")
    bounds_ok = label_name(generator, "bounds_ok")
    call assembler.emit(generator["builder"], x86_64.push(7))
    call assembler.emit(generator["builder"], x86_64.push(6))
    call assembler.relative(generator["builder"], [232], "runtime_length")
    call assembler.emit(generator["builder"], x86_64.move_reg_reg(8, 0))
    call assembler.emit(generator["builder"], x86_64.pop(6))
    call assembler.emit(generator["builder"], x86_64.pop(7))
    call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(6, 0))
    call assembler.relative(generator["builder"], [15, 141], bounds_nonnegative)
    call assembler.emit(generator["builder"], x86_64.add_reg_reg(6, 8))
    call assembler.label(generator["builder"], bounds_nonnegative)
    call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(6, 0))
    bounds_error = label_name(generator, "bounds_error")
    call assembler.relative(generator["builder"], [15, 140], bounds_error)
    call assembler.emit(generator["builder"], x86_64.cmp_reg_reg(6, 8))
    call assembler.relative(generator["builder"], [15, 140], bounds_ok)
    call assembler.label(generator["builder"], bounds_error)
    message = "IndexError: index out of range at " + source_path + ":" + String(syntax["line"])
    call emit_runtime_raise(generator, message)
    call assembler.label(generator["builder"], bounds_ok)
end

function emit_float_expression(generator, syntax):
    call emit_expression(generator, syntax)
    value_type = infer_expression_type(syntax, generator["types"], generator["function_returns"])
    if value_type == "Any":
        float_value_boxed = label_name(generator, "float_value_boxed")
        float_value_ready = label_name(generator, "float_value_ready")
        call assembler.emit(generator["builder"], x86_64.push(0))
        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
        call assembler.relative(generator["builder"], [232], "runtime_type_code")
        call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(0, 6))
        call assembler.emit(generator["builder"], x86_64.pop(7))
        call assembler.relative(generator["builder"], [15, 132], float_value_boxed)
        call assembler.relative(generator["builder"], [232], "runtime_float_from_int")
        call assembler.relative(generator["builder"], [233], float_value_ready)
        call assembler.label(generator["builder"], float_value_boxed)
        call assembler.emit(generator["builder"], x86_64.move_reg_reg(0, 7))
        call assembler.label(generator["builder"], float_value_ready)
    elif value_type != "Float":
        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
        call assembler.relative(generator["builder"], [232], "runtime_float_from_int")
    end
end

function emit_expression(generator, syntax):
    output = generator["builder"]
    kind = syntax["kind"]
    if kind == "literal":
        value = syntax["value"]
        if syntax["literal_kind"] == "string":
            call emit_string_pointer(generator, value)
        elif syntax["literal_kind"] == "number":
            if value.find(".") >= 0 or value.find("e") >= 0 or value.find("E") >= 0:
                call assembler.emit(output, x86_64.mov_imm64(7, float_bits(value)))
                call assembler.relative(output, [232], "runtime_float_new")
            else:
                call assembler.emit(output, x86_64.mov_imm64(0, Int(value)))
            end
        elif value == "True":
            call assembler.emit(output, x86_64.mov_imm64(0, 1))
        elif value == "False" or value == "None":
            call assembler.emit(output, x86_64.mov_imm64(0, 0))
        else:
            call unsupported(generator["path"], generator["lines"], syntax, "String is only valid directly inside print in this stage", "move the String to a print statement")
        end
    elif kind == "name":
        name = syntax["name"]
        if name in generator["variables"]:
            call assembler.emit(output, x86_64.load_stack(0, generator["variables"][name]))
        elif name in generator["global_variables"]:
            call assembler.emit(output, x86_64.load_memory(0, 12, generator["global_variables"][name]))
        elif name in generator["functions"]:
            call assembler.relative(output, x86_64.lea_rip_prefix(0), "function_" + name)
        else:
            call unsupported(generator["path"], generator["lines"], syntax, "unknown native variable: " + name, "assign the variable before reading it")
        end
    elif kind == "real_array":
        array_values = {"kind": "list", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "items": syntax["items"]}
        array_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_real_array"}, "arguments": [array_values]}
        call emit_expression(generator, array_call)
        call assembler.emit(output, x86_64.store_memory_imm32(0, 0, 8))
    elif kind == "list" or kind == "tuple":
        call assembler.emit(output, x86_64.mov_imm64(7, 0))
        call assembler.emit(output, x86_64.mov_imm64(6, 0))
        call assembler.relative(output, [232], "runtime_list_new")
        call assembler.emit(output, x86_64.push(0))
        for item in syntax["items"]:
            call emit_expression(generator, item)
            call emit_collection_box(generator, item)
            call assembler.emit(output, x86_64.move_reg_reg(6, 0))
            call assembler.emit(output, x86_64.load_memory(7, 4, 0))
            call assembler.relative(output, [232], "runtime_list_append")
        end
        call assembler.emit(output, x86_64.pop(0))
        if kind == "tuple":
            call assembler.emit(output, x86_64.store_memory_imm32(0, 0, 7))
        end
    elif kind == "dictionary":
        call assembler.relative(output, [232], "runtime_dict_new")
        call assembler.emit(output, x86_64.push(0))
        for entry in syntax["entries"]:
            call emit_expression(generator, entry[0])
            call assembler.emit(output, x86_64.push(0))
            call emit_expression(generator, entry[1])
            call emit_collection_box(generator, entry[1])
            call assembler.emit(output, x86_64.move_reg_reg(2, 0))
            call assembler.emit(output, x86_64.pop(6))
            call assembler.emit(output, x86_64.load_memory(7, 4, 0))
            call assembler.relative(output, [232], "runtime_dict_set")
        end
        call assembler.emit(output, x86_64.pop(0))
    elif kind == "member":
        target_type = infer_expression_type(syntax["target"], generator["types"], generator["function_returns"])
        if target_type.startswith("Class:") or target_type.startswith("Instance:") or target_type == "Dictionary":
            call emit_expression(generator, syntax["target"])
            call assembler.emit(output, x86_64.push(0))
            call emit_string_pointer(generator, syntax["name"])
            call assembler.emit(output, x86_64.move_reg_reg(6, 0))
            call assembler.emit(output, x86_64.pop(7))
            call assembler.relative(output, [232], "runtime_dict_get")
            call emit_pending_error(generator)
        else:
            call unsupported(generator["path"], generator["lines"], syntax, "member value requires a class or instance", "access a declared class field")
        end
    elif kind == "slice":
        call emit_expression(generator, syntax["target"])
        call assembler.emit(output, x86_64.push(0))
        if syntax["start"] == None:
            call assembler.emit(output, x86_64.mov_imm64(0, 0))
        else:
            call emit_expression(generator, syntax["start"])
        end
        call assembler.emit(output, x86_64.push(0))
        if syntax["stop"] == None:
            call assembler.emit(output, x86_64.load_memory(7, 4, 8))
            call assembler.relative(output, [232], "runtime_length")
        else:
            call emit_expression(generator, syntax["stop"])
        end
        call assembler.emit(output, x86_64.move_reg_reg(2, 0))
        call assembler.emit(output, x86_64.pop(6))
        call assembler.emit(output, x86_64.pop(7))
        call assembler.relative(output, [232], "runtime_slice")
    elif kind == "index":
        target_type = infer_expression_type(syntax["target"], generator["types"], generator["function_returns"])
        call emit_expression(generator, syntax["target"])
        call assembler.emit(output, x86_64.push(0))
        call emit_expression(generator, syntax["index"])
        call assembler.emit(output, x86_64.move_reg_reg(6, 0))
        call assembler.emit(output, x86_64.pop(7))
        if target_type == "Dictionary":
            call assembler.relative(output, [232], "runtime_dict_get")
        else:
            if target_type == "String" or target_type == "List" or target_type == "Tuple" or target_type == "RealArray":
                call emit_bounds_check(generator, syntax)
            end
            call assembler.relative(output, [232], "runtime_get")
        end
        call emit_pending_error(generator)
    elif kind == "unary":
        call emit_expression(generator, syntax["operand"])
        if syntax["operator"] == "-":
            operand_type = infer_expression_type(syntax["operand"], generator["types"], generator["function_returns"])
            if operand_type == "Float":
                call assembler.emit(output, x86_64.load_memory(7, 0, 8))
                call assembler.emit(output, x86_64.mov_imm64(1, -9223372036854775808))
                call assembler.emit(output, x86_64.add_reg_reg(7, 1))
                call assembler.relative(output, [232], "runtime_float_new")
            else:
                call assembler.emit(output, x86_64.neg_reg(0))
            end
        elif syntax["operator"] == "not":
            call emit_truth(generator)
            call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
            call assembler.emit(output, x86_64.set_condition(148))
        end
    elif kind == "binary":
        operator = syntax["operator"]
        expression_type = infer_expression_type(syntax, generator["types"], generator["function_returns"])
        if expression_type == "Float":
            if operator == "**":
                exponent_type = infer_expression_type(syntax["right"], generator["types"], generator["function_returns"])
                if exponent_type != "Int":
                    call unsupported(generator["path"], generator["lines"], syntax, "Float ** requires an Int exponent", "use an Int exponent such as x ** 3")
                end
                call emit_float_expression(generator, syntax["left"])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["right"])
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_float_power")
                return
            end
            call emit_float_expression(generator, syntax["left"])
            call assembler.emit(output, x86_64.push(0))
            call emit_float_expression(generator, syntax["right"])
            call assembler.emit(output, x86_64.move_reg_reg(6, 0))
            call assembler.emit(output, x86_64.pop(7))
            if operator == "+":
                call assembler.relative(output, [232], "runtime_float_add")
            elif operator == "-":
                call assembler.relative(output, [232], "runtime_float_sub")
            elif operator == "*":
                call assembler.relative(output, [232], "runtime_float_mul")
            elif operator == "/":
                call assembler.relative(output, [232], "runtime_float_div")
            else:
                call unsupported(generator["path"], generator["lines"], syntax, "unsupported Float operator " + operator, "use +, -, *, or /")
            end
            return
        elif operator == "+" and expression_type == "List":
            concat_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_list_concat"}, "arguments": [syntax["left"], syntax["right"]]}
            call emit_expression(generator, concat_call)
            return
        elif operator == "*" and expression_type == "String":
            left_type = infer_expression_type(syntax["left"], generator["types"], generator["function_returns"])
            if left_type == "String":
                repeat_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_str_repeat"}, "arguments": [syntax["left"], syntax["right"]]}
            else:
                repeat_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_str_repeat"}, "arguments": [syntax["right"], syntax["left"]]}
            end
            call emit_expression(generator, repeat_call)
            return
        elif operator == "+" and (expression_type == "String" or expression_type == "Any"):
            call emit_expression(generator, syntax["left"])
            call assembler.emit(output, x86_64.push(0))
            call emit_expression(generator, syntax["right"])
            call assembler.emit(output, x86_64.move_reg_reg(6, 0))
            call assembler.emit(output, x86_64.pop(7))
            if expression_type == "String":
                call assembler.relative(output, [232], "runtime_string_concat")
            else:
                call assembler.relative(output, [232], "runtime_add_any")
            end
            return
        elif operator == "and" or operator == "or":
            short_label = label_name(generator, "bool_short")
            done_label = label_name(generator, "bool_done")
            call emit_expression(generator, syntax["left"])
            call emit_truth(generator)
            call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
            if operator == "and":
                call assembler.relative(output, [15, 132], short_label)
            else:
                call assembler.relative(output, [15, 133], short_label)
            end
            call emit_expression(generator, syntax["right"])
            call emit_truth(generator)
            call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
            call assembler.emit(output, x86_64.set_condition(149))
            call assembler.relative(output, [233], done_label)
            call assembler.label(output, short_label)
            if operator == "and":
                call assembler.emit(output, x86_64.mov_imm64(0, 0))
            else:
                call assembler.emit(output, x86_64.mov_imm64(0, 1))
            end
            call assembler.label(output, done_label)
            return
        end
        # Int arithmetic path (Float/String/List handled above). Avoid the
        # push/pop spill when an operand is a literal or variable leaf.
        if is_int_leaf(generator, syntax["right"]):
            call emit_expression(generator, syntax["left"])
            call emit_int_leaf(generator, syntax["right"], 1)
        elif (operator == "+" or operator == "*") and is_int_leaf(generator, syntax["left"]):
            call emit_expression(generator, syntax["right"])
            call emit_int_leaf(generator, syntax["left"], 1)
        else:
            call emit_expression(generator, syntax["left"])
            call assembler.emit(output, x86_64.push(0))
            call emit_expression(generator, syntax["right"])
            call assembler.emit(output, x86_64.move_reg_reg(1, 0))
            call assembler.emit(output, x86_64.pop(0))
        end
        if operator == "+":
            call assembler.emit(output, x86_64.add_reg_reg(0, 1))
        elif operator == "-":
            call assembler.emit(output, x86_64.sub_reg_reg(0, 1))
        elif operator == "*":
            call assembler.emit(output, x86_64.imul_reg_reg(0, 1))
        elif operator == "**":
            power_ready = label_name(generator, "power_ready")
            call assembler.emit(output, x86_64.cmp_reg_imm8(1, 0))
            call assembler.relative(output, [15, 141], power_ready)
            power_source_path = syntax.get("path", generator["path"])
            power_message = "ValueError: negative Int exponent at " + power_source_path + ":" + String(syntax["line"])
            call emit_runtime_raise(generator, power_message)
            call assembler.label(output, power_ready)
            call assembler.emit(output, x86_64.move_reg_reg(7, 0))
            call assembler.emit(output, x86_64.move_reg_reg(6, 1))
            call assembler.relative(output, [232], "runtime_int_power")
        elif operator == "//" or operator == "%":
            division_ready = label_name(generator, "division_ready")
            call assembler.emit(output, x86_64.cmp_reg_imm8(1, 0))
            call assembler.relative(output, [15, 133], division_ready)
            zero_source_path = syntax.get("path", generator["path"])
            zero_message = "ZeroDivisionError: integer division or modulo by zero at " + zero_source_path + ":" + String(syntax["line"])
            call emit_runtime_raise(generator, zero_message)
            call assembler.label(output, division_ready)
            # Divisor -1 overflows idiv on INT64_MIN (#DE/SIGFPE). a // -1 == -a
            # and a % -1 == 0 for all representable a; INT64_MIN wraps like other
            # Int overflow instead of crashing.
            division_neg_one = label_name(generator, "division_neg_one")
            division_computed = label_name(generator, "division_computed")
            call assembler.emit(output, x86_64.cmp_reg_imm8(1, -1))
            call assembler.relative(output, [15, 132], division_neg_one)
            call assembler.emit(output, x86_64.cqo())
            call assembler.emit(output, x86_64.idiv_reg(1))
            division_floor_done = label_name(generator, "division_floor_done")
            call assembler.emit(output, x86_64.cmp_reg_imm8(2, 0))
            call assembler.relative(output, [15, 132], division_floor_done)
            call assembler.emit(output, x86_64.move_reg_reg(8, 2))
            call assembler.emit(output, x86_64.xor_reg_reg(8, 1))
            call assembler.emit(output, x86_64.cmp_reg_imm8(8, 0))
            call assembler.relative(output, [15, 141], division_floor_done)
            call assembler.emit(output, x86_64.decrement(0))
            call assembler.emit(output, x86_64.add_reg_reg(2, 1))
            call assembler.label(output, division_floor_done)
            call assembler.relative(output, [233], division_computed)
            call assembler.label(output, division_neg_one)
            call assembler.emit(output, x86_64.neg_reg(0))
            call assembler.emit(output, x86_64.xor_reg_reg(2, 2))
            call assembler.label(output, division_computed)
            if operator == "%":
                call assembler.emit(output, x86_64.move_reg_reg(0, 2))
            end
        elif operator == "and" or operator == "or":
            call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
            call assembler.emit(output, x86_64.set_condition(149))
            call assembler.emit(output, x86_64.push(0))
            call assembler.emit(output, x86_64.move_reg_reg(0, 1))
            call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
            call assembler.emit(output, x86_64.set_condition(149))
            call assembler.emit(output, x86_64.move_reg_reg(1, 0))
            call assembler.emit(output, x86_64.pop(0))
            if operator == "and":
                call assembler.emit(output, x86_64.and_reg_reg(0, 1))
            else:
                call assembler.emit(output, x86_64.or_reg_reg(0, 1))
            end
        else:
            call unsupported(generator["path"], generator["lines"], syntax, "operator " + operator + " is not in the native scalar slice", "supported now: +, -, *, //, %, comparisons, and/or")
        end
    elif kind == "call":
        target = syntax["target"]
        if target["kind"] == "name":
            builtin_arity = {"Bool": 1, "Int": 1, "Float": 1, "String": 1, "List": 1, "Tuple": 1, "RealArray": 1, "len": 1, "chr": 1, "ord": 1, "abs": 1, "sum": 1, "type": 1, "exit": 1, "input": 1, "readfile": 1, "getenv": 1, "mkdir": 1, "unlink": 1, "exists": 1, "gc": 0, "clock": 0, "arg_count": 0, "last_error": 0, "executable_path": 0, "help": 0, "run": 2, "capture": 2, "writefile": 2, "appendfile": 2, "writebytes": 2, "check": 2}
            if target["name"] in builtin_arity:
                expected_builtin = builtin_arity[target["name"]]
                if len(syntax["arguments"]) != expected_builtin:
                    call unsupported(generator["path"], generator["lines"], syntax, "builtin " + target["name"] + " expects " + String(expected_builtin) + " argument(s), got " + String(len(syntax["arguments"])), "pass exactly " + String(expected_builtin) + " argument(s)")
                end
            end
            if target["name"] == "Bool":
                call emit_expression(generator, syntax["arguments"][0])
                call emit_truth(generator)
                call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                call assembler.emit(output, x86_64.set_condition(149))
                return
            elif target["name"] == "check":
                check_ok = label_name(generator, "check_ok")
                call emit_expression(generator, syntax["arguments"][0])
                call emit_truth(generator)
                call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                call assembler.relative(output, [15, 133], check_ok)
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(13, 0))
                call assembler.emit(output, x86_64.mov_imm64(14, 1))
                if generator["error_label"] != "":
                    call assembler.relative(output, [233], generator["error_label"])
                else:
                    call emit_static_write_fd(generator, "LSL runtime error: CheckError" + chr(10), 2)
                    call assembler.emit(output, x86_64.mov_imm64(7, 1))
                    call assembler.emit(output, x86_64.mov_imm64(0, 60))
                    call assembler.emit(output, x86_64.syscall())
                end
                call assembler.label(output, check_ok)
                call assembler.emit(output, x86_64.mov_imm64(0, 0))
                return
            elif target["name"] == "List" or target["name"] == "Tuple" or target["name"] == "RealArray":
                conversion_target = "__lsl_list"
                if target["name"] == "RealArray":
                    conversion_target = "__lsl_real_array"
                end
                conversion_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": conversion_target}, "arguments": syntax["arguments"]}
                call emit_expression(generator, conversion_call)
                if target["name"] == "Tuple":
                    call assembler.emit(output, x86_64.store_memory_imm32(0, 0, 7))
                elif target["name"] == "RealArray":
                    call assembler.emit(output, x86_64.store_memory_imm32(0, 0, 8))
                end
                return
            elif target["name"] == "sum":
                sum_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_sum"}, "arguments": syntax["arguments"]}
                call emit_expression(generator, sum_call)
                return
            elif target["name"] == "__lsl_float_string":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_float_to_string")
                return
            elif target["name"] == "__lsl_float_from_int":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_float_from_int")
                return
            elif target["name"] == "__lsl_float_to_int":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_float_to_int")
                return
            elif target["name"] == "__lsl_is_heap":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_is_heap_object")
                return
            elif target["name"] == "__lsl_string_chars":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_string_chars")
                return
            elif target["name"] == "__lsl_type_code":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_type_code")
                return
            elif target["name"] == "__lsl_box_bool":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_box_bool")
                return
            elif target["name"] == "__lsl_box_none":
                call assembler.relative(output, [232], "runtime_box_none")
                return
            elif target["name"] == "__lsl_unbox_bool":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_bool")
                return
            elif target["name"] == "__lsl_pop_last":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_list_pop_last")
                return
            elif target["name"] == "len":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_length")
                return
            elif target["name"] == "Int":
                argument_type = infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"])
                if argument_type == "String":
                    parse_int_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_parse_int"}, "arguments": syntax["arguments"]}
                    call emit_expression(generator, parse_int_call)
                elif argument_type == "Any":
                    int_any_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_int_any"}, "arguments": syntax["arguments"]}
                    call emit_expression(generator, int_any_call)
                elif argument_type == "Float":
                    call emit_expression(generator, syntax["arguments"][0])
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_float_to_int")
                else:
                    call emit_expression(generator, syntax["arguments"][0])
                end
                return
            elif target["name"] == "Float":
                argument_type = infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"])
                if argument_type == "String":
                    parse_float_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_parse_float"}, "arguments": syntax["arguments"]}
                    call emit_expression(generator, parse_float_call)
                elif argument_type == "Any":
                    float_any_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_float_any"}, "arguments": syntax["arguments"]}
                    call emit_expression(generator, float_any_call)
                else:
                    call emit_float_expression(generator, syntax["arguments"][0])
                end
                return
            elif target["name"] == "String":
                argument_type = infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"])
                if argument_type == "String":
                    call emit_expression(generator, syntax["arguments"][0])
                elif argument_type == "Float":
                    call emit_expression(generator, syntax["arguments"][0])
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_float_to_string")
                elif argument_type == "Int":
                    call emit_expression(generator, syntax["arguments"][0])
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_int_to_string")
                else:
                    str_value_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_str_value"}, "arguments": syntax["arguments"]}
                    call emit_expression(generator, str_value_call)
                end
                return
            elif target["name"] == "chr":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_chr")
                return
            elif target["name"] == "ord":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_ord")
                return
            elif target["name"] == "arg":
                argument_missing = label_name(generator, "argument_missing")
                argument_done = label_name(generator, "argument_done")
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.load_memory(1, 15, 0))
                call assembler.emit(output, x86_64.cmp_reg_reg(6, 1))
                call assembler.relative(output, [15, 141], argument_missing)
                call assembler.emit(output, x86_64.lea_base(7, 15, 8))
                call assembler.emit(output, x86_64.load_indexed(7, 7, 6, 3))
                call assembler.relative(output, [232], "runtime_from_cstring")
                call assembler.relative(output, [233], argument_done)
                call assembler.label(output, argument_missing)
                call assembler.emit(output, x86_64.mov_imm64(0, 0))
                call assembler.label(output, argument_done)
                return
            elif target["name"] == "arg_count":
                call assembler.emit(output, x86_64.load_memory(0, 15, 0))
                return
            elif target["name"] == "gc":
                call assembler.relative(output, [232], "runtime_gc")
                return
            elif target["name"] == "executable_path":
                call assembler.relative(output, [232], "runtime_executable_path")
                return
            elif target["name"] == "getenv":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_getenv")
                return
            elif target["name"] == "run" or target["name"] == "capture":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                if target["name"] == "capture":
                    call assembler.relative(output, [232], "runtime_capture")
                else:
                    call assembler.relative(output, [232], "runtime_run")
                end
                return
            elif target["name"] == "input":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_input")
                return
            elif target["name"] == "clock":
                call assembler.relative(output, [232], "runtime_clock")
                return
            elif target["name"] == "readfile":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_readfile")
                call assembler.emit(output, x86_64.cmp_reg_imm8(14, 0))
                if generator["error_label"] != "":
                    call assembler.relative(output, [15, 133], generator["error_label"])
                else:
                    readfile_ok = label_name(generator, "readfile_ok")
                    call assembler.relative(output, [15, 132], readfile_ok)
                    call emit_uncaught_runtime_error(generator)
                    call assembler.label(output, readfile_ok)
                end
                return
            elif target["name"] == "writefile" or target["name"] == "appendfile" or target["name"] == "writebytes":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                if target["name"] == "writebytes":
                    call assembler.relative(output, [232], "runtime_writebytes")
                elif target["name"] == "appendfile":
                    call assembler.relative(output, [232], "runtime_appendfile")
                else:
                    call assembler.relative(output, [232], "runtime_writefile")
                end
                call assembler.emit(output, x86_64.cmp_reg_imm8(14, 0))
                if generator["error_label"] != "":
                    call assembler.relative(output, [15, 133], generator["error_label"])
                else:
                    write_ok = label_name(generator, "write_ok")
                    call assembler.relative(output, [15, 132], write_ok)
                    call emit_uncaught_runtime_error(generator)
                    call assembler.label(output, write_ok)
                end
                return
            elif target["name"] == "last_error":
                call assembler.emit(output, x86_64.move_reg_reg(0, 13))
                return
            elif target["name"] == "type":
                value_type = infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"])
                if value_type.startswith("Class:"):
                    value_type = "Class"
                elif value_type.startswith("Instance:"):
                    value_type = "Instance"
                end
                call emit_string_pointer(generator, value_type)
                return
            elif target["name"] == "mkdir" or target["name"] == "unlink":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                if target["name"] == "mkdir":
                    call assembler.relative(output, [232], "runtime_mkdir")
                else:
                    call assembler.relative(output, [232], "runtime_unlink")
                end
                return
            elif target["name"] == "exists":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_exists")
                return
            elif target["name"] == "min" or target["name"] == "max":
                if len(syntax["arguments"]) == 1:
                    reducer = "__lsl_min"
                    if target["name"] == "max":
                        reducer = "__lsl_max"
                    end
                    reduce_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": reducer}, "arguments": syntax["arguments"]}
                    call emit_expression(generator, reduce_call)
                    return
                end
                if len(syntax["arguments"]) != 2:
                    call unsupported(generator["path"], generator["lines"], syntax, "builtin " + target["name"] + " expects 1 iterable or 2 values", "pass min(iterable) or min(a, b)")
                end
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(1, 0))
                call assembler.emit(output, x86_64.pop(0))
                done_label = label_name(generator, "minmax_done")
                call assembler.emit(output, x86_64.cmp_reg_reg(0, 1))
                if target["name"] == "min":
                    call assembler.relative(output, [15, 142], done_label)
                else:
                    call assembler.relative(output, [15, 141], done_label)
                end
                call assembler.emit(output, x86_64.move_reg_reg(0, 1))
                call assembler.label(output, done_label)
                return
            elif target["name"] == "help":
                call emit_static_write(generator, "Lux Simple Lang (LSL) 0.7" + chr(10) + "functions: print printl input for loop safe if elif else try class ctype function type del len help" + chr(10) + "types: Bool Int Float String List Tuple RealArray Dictionary" + chr(10) + "docs: see README.md and docs/" + chr(10))
                call assembler.emit(output, x86_64.mov_imm64(0, 0))
                return
            elif target["name"] == "abs":
                call emit_expression(generator, syntax["arguments"][0])
                done_label = label_name(generator, "abs_done")
                call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                call assembler.relative(output, [15, 141], done_label)
                call assembler.emit(output, x86_64.neg_reg(0))
                call assembler.label(output, done_label)
                return
            elif target["name"] == "exit":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.emit(output, x86_64.mov_imm64(0, 60))
                call assembler.emit(output, x86_64.syscall())
                return
            end
        elif target["kind"] == "member":
            receiver_type = infer_expression_type(target["target"], generator["types"], generator["function_returns"])
            method_arity = {"strip": 0, "lstrip": 0, "rstrip": 0, "lower": 0, "upper": 0, "title": 0, "sort": 0, "copy": 0, "keys": 0, "clear": 0, "append": 1, "startswith": 1, "endswith": 1, "find": 1, "count": 1, "split": 1, "join": 1, "extend": 1, "remove": 1, "index": 1, "update": 1, "replace": 2, "insert": 2}
            if target["name"] in method_arity and not receiver_type.startswith("Class:") and not receiver_type.startswith("Instance:"):
                expected_method = method_arity[target["name"]]
                if len(syntax["arguments"]) != expected_method:
                    call unsupported(generator["path"], generator["lines"], syntax, "method " + target["name"] + " expects " + String(expected_method) + " argument(s), got " + String(len(syntax["arguments"])), "pass exactly " + String(expected_method) + " argument(s)")
                end
            end
            if receiver_type.startswith("Class:") or receiver_type.startswith("Instance:"):
                if receiver_type.startswith("Class:"):
                    class_name = receiver_type[6:len(receiver_type)]
                else:
                    class_name = receiver_type[9:len(receiver_type)]
                end
                native_method_name = class_name + "__" + target["name"]
                if native_method_name not in generator["functions"]:
                    call unsupported(generator["path"], generator["lines"], syntax, "unknown class method: " + target["name"], "declare the method inside class " + class_name)
                end
                declaration = generator["functions"][native_method_name]
                combined_arguments = []
                if len(declaration["parameters"]) > 0:
                    if declaration["parameters"][0] == "self":
                        combined_arguments.append(target["target"])
                    end
                end
                combined_arguments.extend(syntax["arguments"])
                combined_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": native_method_name}, "arguments": combined_arguments}
                call emit_expression(generator, combined_call)
                return
            elif target["name"] == "append":
                if receiver_type == "Tuple" or receiver_type == "RealArray":
                    call unsupported(generator["path"], generator["lines"], syntax, "fixed collection does not support append", "convert it with List(value) before appending")
                end
                call emit_expression(generator, target["target"])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][0])
                call emit_collection_box(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_list_append")
                return
            elif target["name"] == "clear":
                call emit_expression(generator, target["target"])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_list_clear")
                return
            elif target["name"] == "pop" and len(syntax["arguments"]) == 0:
                if receiver_type == "Tuple" or receiver_type == "RealArray":
                    call unsupported(generator["path"], generator["lines"], syntax, "fixed collection does not support pop", "convert it with List(value) before changing its length")
                end
                pop_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_pop"}, "arguments": [target["target"]]}
                call emit_expression(generator, pop_call)
                return
            elif target["name"] == "keys":
                call emit_expression(generator, target["target"])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_dict_keys")
                return
            else:
                method_target = method_function(target["name"])
                if receiver_type == "Tuple" or receiver_type == "RealArray":
                    if target["name"] == "insert" or target["name"] == "remove" or target["name"] == "extend" or target["name"] == "sort" or target["name"] == "clear" or target["name"] == "pop":
                        call unsupported(generator["path"], generator["lines"], syntax, "fixed collection does not support " + target["name"], "convert it with List(value) before changing its length")
                    end
                end
                if receiver_type == "List" or receiver_type == "Tuple" or receiver_type == "RealArray":
                    if target["name"] == "index":
                        method_target = "__lsl_list_index"
                    elif target["name"] == "count":
                        method_target = "__lsl_list_count"
                    end
                elif receiver_type == "String" and target["name"] == "index":
                    method_target = "__lsl_string_index"
                end
                if method_target != "":
                    combined_arguments = [target["target"]]
                    combined_arguments.extend(syntax["arguments"])
                    if target["name"] == "get" and len(syntax["arguments"]) == 1:
                        combined_arguments.append({"kind": "literal", "literal_kind": "name", "value": "None", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]})
                    end
                    if len(combined_arguments) > 6:
                        call unsupported(generator["path"], generator["lines"], syntax, "method has too many native ABI arguments", "use at most six arguments")
                    end
                    for argument in combined_arguments:
                        call emit_expression(generator, argument)
                        if target["name"] == "setdefault" or target["name"] == "insert":
                            call emit_collection_box(generator, argument)
                        end
                        call assembler.emit(output, x86_64.push(0))
                    end
                    method_registers = [7, 6, 2, 1, 8, 9]
                    method_index = len(combined_arguments) - 1
                    while method_index >= 0:
                        call assembler.emit(output, x86_64.pop(method_registers[method_index]))
                        method_index -= 1
                    end
                    call assembler.relative(output, [232], "function_" + method_target)
                    call emit_pending_error(generator)
                    if target["name"] == "copy":
                        if receiver_type == "Tuple":
                            call assembler.emit(output, x86_64.store_memory_imm32(0, 0, 7))
                        elif receiver_type == "RealArray":
                            call assembler.emit(output, x86_64.store_memory_imm32(0, 0, 8))
                        end
                    end
                    return
                end
            end
        end
        if target["kind"] != "name":
            call unsupported(generator["path"], generator["lines"], syntax, "only direct Function calls are supported; unresolved target kind " + target["kind"] + " member " + target.get("name", "?"), "call a declared function by name")
        end
        if target["name"] in generator["classes"]:
            class_name = target["name"]
            arguments = syntax["arguments"]
            if len(arguments) > 5:
                call unsupported(generator["path"], generator["lines"], syntax, "class initializer has too many arguments", "use at most five arguments after self")
            end
            call assembler.relative(output, [232], "runtime_dict_new")
            call assembler.emit(output, x86_64.push(0))
            initializer_name = class_name + "__init"
            if initializer_name in generator["functions"]:
                initializer = generator["functions"][initializer_name]
                if len(arguments) + 1 != len(initializer["parameters"]):
                    call unsupported(generator["path"], generator["lines"], syntax, "initializer argument count mismatch", "pass exactly " + String(len(initializer["parameters"]) - 1) + " arguments")
                end
                index = len(arguments) - 1
                while index >= 0:
                    call emit_expression(generator, arguments[index])
                    call assembler.emit(output, x86_64.push(0))
                    index -= 1
                end
                call assembler.emit(output, x86_64.load_memory(0, 4, len(arguments) * 8))
                call assembler.emit(output, x86_64.push(0))
                argument_registers = [7, 6, 2, 1, 8, 9]
                index = 0
                while index < len(arguments) + 1:
                    call assembler.emit(output, x86_64.pop(argument_registers[index]))
                    index += 1
                end
                call assembler.relative(output, [232], "function_" + initializer_name)
                call assembler.emit(output, x86_64.cmp_reg_imm8(14, 0))
                if generator["error_label"] != "":
                    call assembler.relative(output, [15, 133], generator["error_label"])
                else:
                    initializer_ok = label_name(generator, "initializer_ok")
                    call assembler.relative(output, [15, 132], initializer_ok)
                    call emit_uncaught_runtime_error(generator)
                    call assembler.label(output, initializer_ok)
                end
            end
            call assembler.emit(output, x86_64.pop(0))
            return
        end
        indirect_call = False
        if target["name"] not in generator["functions"]:
            if target["name"] in generator["variables"] or target["name"] in generator["global_variables"]:
                indirect_call = True
            else:
                call unsupported(generator["path"], generator["lines"], syntax, "unknown native function: " + target["name"], "declare the function or assign a Function value before calling it")
            end
        end
        arguments = syntax["arguments"]
        if not indirect_call:
            expected_arguments = len(generator["functions"][target["name"]]["parameters"])
            if len(arguments) != expected_arguments:
                call unsupported(generator["path"], generator["lines"], syntax, "function argument count mismatch for " + target["name"], "pass exactly " + String(expected_arguments) + " arguments")
            end
        end
        index = len(arguments) - 1
        while index >= 0:
            call emit_expression(generator, arguments[index])
            call assembler.emit(output, x86_64.push(0))
            index -= 1
        end
        argument_registers = [7, 6, 2, 1, 8, 9]
        register_count = min(len(arguments), len(argument_registers))
        index = 0
        while index < register_count:
            call assembler.emit(output, x86_64.pop(argument_registers[index]))
            index += 1
        end
        if indirect_call:
            if target["name"] in generator["variables"]:
                call assembler.emit(output, x86_64.load_stack(0, generator["variables"][target["name"]]))
            else:
                call assembler.emit(output, x86_64.load_memory(0, 12, generator["global_variables"][target["name"]]))
            end
            call assembler.emit(output, x86_64.call_reg(0))
        else:
            call assembler.relative(output, [232], "function_" + target["name"])
        end
        stack_count = len(arguments) - register_count
        if stack_count > 0:
            call assembler.emit(output, x86_64.add_reg_imm32(4, stack_count * 8))
        end
        call assembler.emit(output, x86_64.cmp_reg_imm8(14, 0))
        if generator["error_label"] != "":
            call assembler.relative(output, [15, 133], generator["error_label"])
        else:
            call_ok = label_name(generator, "call_ok")
            call assembler.relative(output, [15, 132], call_ok)
            call emit_uncaught_runtime_error(generator)
            call assembler.label(output, call_ok)
        end
    elif kind == "compare":
        if len(syntax["operators"]) > 1:
            chain_false = label_name(generator, "compare_chain_false")
            chain_end = label_name(generator, "compare_chain_end")
            chain_index = 0
            while chain_index < len(syntax["operators"]):
                pair = {"kind": "compare", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "operators": [syntax["operators"][chain_index]], "operands": [syntax["operands"][chain_index], syntax["operands"][chain_index + 1]]}
                call emit_expression(generator, pair)
                call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                call assembler.relative(output, [15, 132], chain_false)
                chain_index += 1
            end
            call assembler.emit(output, x86_64.mov_imm64(0, 1))
            call assembler.relative(output, [233], chain_end)
            call assembler.label(output, chain_false)
            call assembler.emit(output, x86_64.mov_imm64(0, 0))
            call assembler.label(output, chain_end)
            return
        end
        left = syntax["operands"][0]
        right = syntax["operands"][1]
        operator = syntax["operators"][0]
        if operator == "in" or operator == "not in":
            container_type = infer_expression_type(right, generator["types"], generator["function_returns"])
            call emit_expression(generator, right)
            call assembler.emit(output, x86_64.push(0))
            call emit_expression(generator, left)
            call assembler.emit(output, x86_64.move_reg_reg(6, 0))
            call assembler.emit(output, x86_64.pop(7))
            if container_type == "String":
                call assembler.relative(output, [232], "runtime_string_contains")
            else:
                call assembler.relative(output, [232], "runtime_contains")
            end
            if operator == "not in":
                call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                call assembler.emit(output, x86_64.set_condition(148))
            end
            return
        end
        opcode = comparison_opcode(operator)
        if opcode < 0:
            call unsupported(generator["path"], generator["lines"], syntax, "comparison " + operator + " is unavailable for current values", "use equality, membership, or an ordered Int comparison")
        end
        left_type = infer_expression_type(left, generator["types"], generator["function_returns"])
        right_type = infer_expression_type(right, generator["types"], generator["function_returns"])
        if left_type == "Float" or right_type == "Float":
            call emit_float_expression(generator, left)
            call assembler.emit(output, x86_64.push(0))
            call emit_float_expression(generator, right)
            call assembler.emit(output, x86_64.move_reg_reg(6, 0))
            call assembler.emit(output, x86_64.pop(7))
            call assembler.emit(output, x86_64.load_memory(0, 7, 8))
            call assembler.emit(output, x86_64.load_memory(1, 6, 8))
            call assembler.emit(output, x86_64.movq_xmm_from_reg(0, 0))
            call assembler.emit(output, x86_64.movq_xmm_from_reg(1, 1))
            call assembler.emit(output, x86_64.compare_double(0, 1))
            if operator == "==" or operator == "is":
                call assembler.emit(output, x86_64.set_condition_ordered(148))
            elif operator == "!=" or operator == "is not":
                call assembler.emit(output, x86_64.set_condition_unordered(149))
            elif operator == "<":
                call assembler.emit(output, x86_64.set_condition_ordered(146))
            elif operator == "<=":
                call assembler.emit(output, x86_64.set_condition_ordered(150))
            elif operator == ">":
                call assembler.emit(output, x86_64.set_condition(151))
            else:
                call assembler.emit(output, x86_64.set_condition(147))
            end
            return
        end
        call emit_expression(generator, left)
        call assembler.emit(output, x86_64.push(0))
        call emit_expression(generator, right)
        call assembler.emit(output, x86_64.move_reg_reg(6, 0))
        call assembler.emit(output, x86_64.pop(7))
        if operator == "==" or operator == "!=" or operator == "is" or operator == "is not":
            call assembler.relative(output, [232], "runtime_equal_any")
            if operator == "!=" or operator == "is not":
                call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                call assembler.emit(output, x86_64.set_condition(148))
            end
        else:
            call assembler.emit(output, x86_64.move_reg_reg(0, 7))
            call assembler.emit(output, x86_64.cmp_reg_reg(0, 6))
            call assembler.emit(output, x86_64.set_condition(opcode))
        end
    else:
        call unsupported(generator["path"], generator["lines"], syntax, "expression kind " + kind + " is not in the native scalar slice", "this construct will be enabled with the dynamic runtime")
    end
end

function emit_static_write_fd(generator, text, descriptor):
    payload = bytes.utf8(text)
    output = generator["builder"]
    call assembler.emit(output, x86_64.mov_imm64(0, 1))
    call assembler.emit(output, x86_64.mov_imm64(7, descriptor))
    lea_start = assembler.position(output)
    call assembler.emit(output, x86_64.lea_rip(6, 0))
    generator["relocations"].append([lea_start + 3, lea_start + 7, len(generator["data"])])
    call assembler.emit(output, x86_64.mov_imm64(2, len(payload)))
    call assembler.emit(output, x86_64.syscall())
    generator["data"].extend(payload)
end

function emit_static_write(generator, text):
    call emit_static_write_fd(generator, text, 1)
end

function emit_print_value(generator, expression):
    if expression["kind"] == "literal":
        if expression["literal_kind"] == "string" or expression["literal_kind"] == "name":
            call emit_static_write(generator, expression["value"])
            return
        end
    end
    if True:
        value_type = infer_expression_type(expression, generator["types"], generator["function_returns"])
        if value_type == "List" or value_type == "Tuple" or value_type == "RealArray" or value_type == "Dictionary" or value_type == "Any":
            str_call = {"kind": "call", "line": expression["line"], "column": expression["column"], "end_column": expression["end_column"], "target": {"kind": "name", "name": "__lsl_str_value"}, "arguments": [expression]}
            call emit_expression(generator, str_call)
            call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
            call assembler.relative(generator["builder"], [232], "runtime_print_string")
            return
        end
        call emit_expression(generator, expression)
        if value_type == "String":
            call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
            call assembler.relative(generator["builder"], [232], "runtime_print_string")
        elif value_type == "Float":
            call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
            call assembler.relative(generator["builder"], [232], "runtime_print_float")
        elif value_type == "Bool":
            false_label = label_name(generator, "print_false")
            done_label = label_name(generator, "print_bool_done")
            call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(0, 0))
            call assembler.relative(generator["builder"], [15, 132], false_label)
            call emit_static_write(generator, "True")
            call assembler.relative(generator["builder"], [233], done_label)
            call assembler.label(generator["builder"], false_label)
            call emit_static_write(generator, "False")
            call assembler.label(generator["builder"], done_label)
        elif value_type == "Any":
            call assembler.relative(generator["builder"], [232], "runtime_print_any")
        else:
            call assembler.relative(generator["builder"], [232], "runtime_print_int")
        end
    end
end

function emit_formatted_text(generator, text):
    index = 0
    literal_start = 0
    while index < len(text):
        if text[index] == "{":
            if index > literal_start:
                call emit_static_write(generator, text[literal_start:index])
            end
            closing = index + 1
            while closing < len(text) and text[closing] != "}":
                closing += 1
            end
            if closing >= len(text):
                call unsupported(generator["path"], generator["lines"], {"line": 1, "column": 1, "end_column": 1}, "unclosed printl interpolation", "add a closing brace")
            end
            expression_source = "print " + text[index + 1:closing] + chr(10)
            parsed = parser.parse(generator["path"], expression_source)
            call emit_print_value(generator, parsed[0]["expressions"][0])
            index = closing + 1
            literal_start = index
        else:
            index += 1
        end
    end
    if literal_start < len(text):
        call emit_static_write(generator, text[literal_start:len(text)])
    end
end

function emit_statements(generator, statements, break_label, continue_label, return_label):
    for statement in statements:
        kind = statement["kind"]
        if kind == "assign":
            target = statement["target"]
            if target["kind"] == "name":
                if statement["operator"] == "=":
                    call emit_expression(generator, statement["value"])
                else:
                    operator = statement["operator"][0:len(statement["operator"]) - 1]
                    combined = {"kind": "binary", "line": statement["line"], "column": statement["column"], "end_column": statement["end_column"], "operator": operator, "left": target, "right": statement["value"]}
                    call emit_expression(generator, combined)
                end
                call assembler.emit(generator["builder"], x86_64.store_stack(generator["variables"][target["name"]], 0))
            elif target["kind"] == "index":
                target_type = infer_expression_type(target["target"], generator["types"], generator["function_returns"])
                if statement["operator"] != "=":
                    call unsupported(generator["path"], generator["lines"], statement, "indexed augmented assignment is not implemented", "use collection[index] = value")
                end
                call emit_expression(generator, target["target"])
                call assembler.emit(generator["builder"], x86_64.push(0))
                call emit_expression(generator, target["index"])
                call assembler.emit(generator["builder"], x86_64.push(0))
                call emit_expression(generator, statement["value"])
                call assembler.emit(generator["builder"], x86_64.move_reg_reg(2, 0))
                call assembler.emit(generator["builder"], x86_64.pop(6))
                call assembler.emit(generator["builder"], x86_64.pop(7))
                if target_type == "Tuple":
                    call unsupported(generator["path"], generator["lines"], statement, "Tuple items are immutable", "use List or RealArray for indexed mutation")
                elif target_type == "Dictionary":
                    call assembler.relative(generator["builder"], [232], "runtime_dict_set")
                elif target_type == "List" or target_type == "RealArray":
                    if target_type == "RealArray":
                        call assembler.emit(generator["builder"], x86_64.push(7))
                        call assembler.emit(generator["builder"], x86_64.push(6))
                        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 2))
                        call assembler.relative(generator["builder"], [232], "function___lsl_require_real")
                        call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(14, 0))
                        if generator["error_label"] != "":
                            call assembler.relative(generator["builder"], [15, 133], generator["error_label"])
                        else:
                            real_value_ok = label_name(generator, "real_value_ok")
                            call assembler.relative(generator["builder"], [15, 132], real_value_ok)
                            call emit_uncaught_runtime_error(generator)
                            call assembler.label(generator["builder"], real_value_ok)
                        end
                        call assembler.emit(generator["builder"], x86_64.move_reg_reg(2, 0))
                        call assembler.emit(generator["builder"], x86_64.pop(6))
                        call assembler.emit(generator["builder"], x86_64.pop(7))
                    end
                    call assembler.emit(generator["builder"], x86_64.push(2))
                    call emit_bounds_check(generator, statement)
                    call assembler.emit(generator["builder"], x86_64.pop(2))
                    call assembler.relative(generator["builder"], [232], "runtime_list_set")
                else:
                    call assembler.relative(generator["builder"], [232], "runtime_set")
                end
            elif target["kind"] == "member":
                target_type = infer_expression_type(target["target"], generator["types"], generator["function_returns"])
                if not target_type.startswith("Class:") and not target_type.startswith("Instance:"):
                    call unsupported(generator["path"], generator["lines"], statement, "member assignment requires a class instance", "assign to self.field or an instance field")
                end
                call emit_expression(generator, target["target"])
                call assembler.emit(generator["builder"], x86_64.push(0))
                call emit_string_pointer(generator, target["name"])
                call assembler.emit(generator["builder"], x86_64.push(0))
                if statement["operator"] == "=":
                    call emit_expression(generator, statement["value"])
                else:
                    operator = statement["operator"][0:len(statement["operator"]) - 1]
                    combined = {"kind": "binary", "line": statement["line"], "column": statement["column"], "end_column": statement["end_column"], "operator": operator, "left": target, "right": statement["value"]}
                    call emit_expression(generator, combined)
                end
                call assembler.emit(generator["builder"], x86_64.move_reg_reg(2, 0))
                call assembler.emit(generator["builder"], x86_64.pop(6))
                call assembler.emit(generator["builder"], x86_64.pop(7))
                call assembler.relative(generator["builder"], [232], "runtime_dict_set")
            else:
                call unsupported(generator["path"], generator["lines"], statement, "unsupported assignment target", "assign to a name, index, or instance field")
            end
        elif kind == "print":
            expressions = statement["expressions"]
            if statement["formatted"] and len(expressions) == 1 and expressions[0]["kind"] == "literal" and expressions[0]["literal_kind"] == "string":
                call emit_formatted_text(generator, expressions[0]["value"])
            else:
                index = 0
                while index < len(expressions):
                    if index > 0:
                        call emit_static_write(generator, " ")
                    end
                    call emit_print_value(generator, expressions[index])
                    index += 1
                end
            end
            call emit_static_write(generator, chr(10))
        elif kind == "expression":
            call emit_expression(generator, statement["expression"])
        elif kind == "if":
            end_label = label_name(generator, "if_end")
            branch_index = 0
            while branch_index < len(statement["branches"]):
                next_label = label_name(generator, "if_next")
                branch = statement["branches"][branch_index]
                call emit_condition(generator, branch[0])
                call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(0, 0))
                call assembler.relative(generator["builder"], [15, 132], next_label)
                call emit_statements(generator, branch[1], break_label, continue_label, return_label)
                call assembler.relative(generator["builder"], [233], end_label)
                call assembler.label(generator["builder"], next_label)
                branch_index += 1
            end
            call emit_statements(generator, statement["otherwise"], break_label, continue_label, return_label)
            call assembler.label(generator["builder"], end_label)
        elif kind == "while" or kind == "loop":
            start_label = label_name(generator, "loop_start")
            end_label = label_name(generator, "loop_end")
            call assembler.label(generator["builder"], start_label)
            if kind == "while":
                call emit_condition(generator, statement["condition"])
                call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(0, 0))
                call assembler.relative(generator["builder"], [15, 132], end_label)
            end
            call emit_statements(generator, statement["body"], end_label, start_label, return_label)
            call assembler.relative(generator["builder"], [233], start_label)
            call assembler.label(generator["builder"], end_label)
        elif kind == "for":
            iterable = statement["iterable"]
            is_range_loop = False
            if iterable["kind"] == "call":
                if iterable["target"]["kind"] == "name":
                    if iterable["target"]["name"] == "rang" or iterable["target"]["name"] == "range":
                        is_range_loop = True
                    end
                end
            end
            if not is_range_loop:
                iterator_slot = generator["variables"][statement["iterator_name"]]
                index_slot = generator["variables"][statement["index_name"]]
                value_slot = generator["variables"][statement["name"]]
                call emit_expression(generator, iterable)
                iterable_type = infer_expression_type(iterable, generator["types"], generator["function_returns"])
                if iterable_type == "Dictionary":
                    call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                    call assembler.relative(generator["builder"], [232], "runtime_dict_keys")
                elif iterable_type == "Any":
                    iterator_not_dict = label_name(generator, "iterator_not_dict")
                    iterator_ready = label_name(generator, "iterator_ready")
                    call assembler.emit(generator["builder"], x86_64.push(0))
                    call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                    call assembler.relative(generator["builder"], [232], "runtime_type_code")
                    call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(0, 3))
                    call assembler.relative(generator["builder"], [15, 133], iterator_not_dict)
                    call assembler.emit(generator["builder"], x86_64.pop(7))
                    call assembler.relative(generator["builder"], [232], "runtime_dict_keys")
                    call assembler.relative(generator["builder"], [233], iterator_ready)
                    call assembler.label(generator["builder"], iterator_not_dict)
                    call assembler.emit(generator["builder"], x86_64.pop(0))
                    call assembler.label(generator["builder"], iterator_ready)
                end
                call assembler.emit(generator["builder"], x86_64.store_stack(iterator_slot, 0))
                call assembler.emit(generator["builder"], x86_64.mov_imm64(0, 0))
                call assembler.emit(generator["builder"], x86_64.store_stack(index_slot, 0))
                start_label = label_name(generator, "iter_start")
                continue_target = label_name(generator, "iter_continue")
                end_label = label_name(generator, "iter_end")
                call assembler.label(generator["builder"], start_label)
                call assembler.emit(generator["builder"], x86_64.load_stack(7, iterator_slot))
                call assembler.relative(generator["builder"], [232], "runtime_length")
                call assembler.emit(generator["builder"], x86_64.move_reg_reg(1, 0))
                call assembler.emit(generator["builder"], x86_64.load_stack(0, index_slot))
                call assembler.emit(generator["builder"], x86_64.cmp_reg_reg(0, 1))
                call assembler.relative(generator["builder"], [15, 141], end_label)
                call assembler.emit(generator["builder"], x86_64.load_stack(7, iterator_slot))
                call assembler.emit(generator["builder"], x86_64.load_stack(6, index_slot))
                call assembler.relative(generator["builder"], [232], "runtime_get")
                call assembler.emit(generator["builder"], x86_64.store_stack(value_slot, 0))
                call emit_statements(generator, statement["body"], end_label, continue_target, return_label)
                call assembler.label(generator["builder"], continue_target)
                call assembler.emit(generator["builder"], x86_64.load_stack(0, index_slot))
                call assembler.emit(generator["builder"], x86_64.increment(0))
                call assembler.emit(generator["builder"], x86_64.store_stack(index_slot, 0))
                call assembler.relative(generator["builder"], [233], start_label)
                call assembler.label(generator["builder"], end_label)
                continue
            end
            arguments = iterable["arguments"]
            if len(arguments) < 1 or len(arguments) > 3:
                call unsupported(generator["path"], generator["lines"], statement, "rang expects one to three arguments", "use rang(stop), rang(start, stop), or rang(start, stop, step)")
            end
            if len(arguments) == 1:
                start_expression = {"kind": "literal", "literal_kind": "number", "value": "0", "line": statement["line"], "column": statement["column"], "end_column": statement["end_column"]}
                stop_expression = arguments[0]
            else:
                start_expression = arguments[0]
                stop_expression = arguments[1]
            end
            step_value = 1
            if len(arguments) == 3:
                step_syntax = arguments[2]
                if step_syntax["kind"] == "literal":
                    if step_syntax["literal_kind"] != "number":
                        call unsupported(generator["path"], generator["lines"], step_syntax, "native rang step must be an Int literal", "use a positive or negative integer step")
                    end
                    step_value = Int(step_syntax["value"])
                elif step_syntax["kind"] == "unary":
                    if step_syntax["operator"] != "-" or step_syntax["operand"]["kind"] != "literal":
                        call unsupported(generator["path"], generator["lines"], step_syntax, "native rang step must currently be an Int literal", "use a positive or negative integer step")
                    end
                    step_value = -Int(step_syntax["operand"]["value"])
                else:
                    call unsupported(generator["path"], generator["lines"], step_syntax, "native rang step must currently be an Int literal", "use a positive or negative integer step")
                end
            end
            if step_value == 0:
                call unsupported(generator["path"], generator["lines"], statement, "rang step cannot be zero", "choose a non-zero step")
            end
            slot = generator["variables"][statement["name"]]
            call emit_expression(generator, start_expression)
            call assembler.emit(generator["builder"], x86_64.store_stack(slot, 0))
            start_label = label_name(generator, "for_start")
            continue_target = label_name(generator, "for_continue")
            end_label = label_name(generator, "for_end")
            call assembler.label(generator["builder"], start_label)
            call assembler.emit(generator["builder"], x86_64.load_stack(0, slot))
            call assembler.emit(generator["builder"], x86_64.push(0))
            call emit_expression(generator, stop_expression)
            call assembler.emit(generator["builder"], x86_64.move_reg_reg(1, 0))
            call assembler.emit(generator["builder"], x86_64.pop(0))
            call assembler.emit(generator["builder"], x86_64.cmp_reg_reg(0, 1))
            if step_value > 0:
                call assembler.relative(generator["builder"], [15, 141], end_label)
            else:
                call assembler.relative(generator["builder"], [15, 142], end_label)
            end
            call emit_statements(generator, statement["body"], end_label, continue_target, return_label)
            call assembler.label(generator["builder"], continue_target)
            call assembler.emit(generator["builder"], x86_64.load_stack(0, slot))
            call assembler.emit(generator["builder"], x86_64.add_reg_imm8(0, step_value))
            call assembler.emit(generator["builder"], x86_64.store_stack(slot, 0))
            call assembler.relative(generator["builder"], [233], start_label)
            call assembler.label(generator["builder"], end_label)
        elif kind == "break":
            if break_label == "":
                call unsupported(generator["path"], generator["lines"], statement, "break used outside a loop", "move break into while or loop")
            end
            call assembler.relative(generator["builder"], [233], break_label)
        elif kind == "continue":
            if continue_label == "":
                call unsupported(generator["path"], generator["lines"], statement, "continue used outside a loop", "move continue into while or loop")
            end
            call assembler.relative(generator["builder"], [233], continue_label)
        elif kind == "safe":
            safe_end = label_name(generator, "safe_end")
            old_error_label = generator["error_label"]
            generator["error_label"] = safe_end
            call emit_statements(generator, statement["body"], break_label, continue_label, return_label)
            generator["error_label"] = old_error_label
            call assembler.label(generator["builder"], safe_end)
            call assembler.emit(generator["builder"], x86_64.xor_reg_reg(14, 14))
        elif kind == "try":
            try_failure = label_name(generator, "try_failure")
            try_end = label_name(generator, "try_end")
            old_error_label = generator["error_label"]
            generator["error_label"] = try_failure
            call emit_statements(generator, statement["body"], break_label, continue_label, return_label)
            call assembler.relative(generator["builder"], [233], try_end)
            call assembler.label(generator["builder"], try_failure)
            call assembler.emit(generator["builder"], x86_64.xor_reg_reg(14, 14))
            generator["error_label"] = old_error_label
            call emit_statements(generator, statement["otherwise"], break_label, continue_label, return_label)
            call assembler.label(generator["builder"], try_end)
        elif kind == "error":
            error_message = statement["message"]
            error_prefix = statement["error_kind"] + ": "
            if error_message["kind"] == "literal":
                if error_message["literal_kind"] == "string":
                    call emit_string_pointer(generator, error_prefix + error_message["value"])
                else:
                    call emit_expression(generator, error_message)
                end
            elif error_message["kind"] == "name" and error_message["name"] not in generator["variables"] and error_message["name"] not in generator["global_variables"]:
                call emit_string_pointer(generator, error_prefix + error_message["name"])
            else:
                call emit_string_pointer(generator, error_prefix)
                call assembler.emit(generator["builder"], x86_64.push(0))
                call emit_expression(generator, error_message)
                call assembler.emit(generator["builder"], x86_64.move_reg_reg(6, 0))
                call assembler.emit(generator["builder"], x86_64.pop(7))
                call assembler.relative(generator["builder"], [232], "runtime_string_concat")
            end
            call assembler.emit(generator["builder"], x86_64.move_reg_reg(13, 0))
            call assembler.emit(generator["builder"], x86_64.mov_imm64(14, 1))
            if generator["error_label"] != "":
                call assembler.relative(generator["builder"], [233], generator["error_label"])
            else:
                message = "LSL runtime error: " + statement["error_kind"] + chr(10)
                if statement["message"]["kind"] == "literal":
                    if statement["message"]["literal_kind"] == "string":
                        message = "LSL runtime error: " + statement["error_kind"] + ": " + statement["message"]["value"] + chr(10)
                    end
                end
                call emit_static_write_fd(generator, message, 2)
                call assembler.emit(generator["builder"], x86_64.mov_imm64(7, 1))
                call assembler.emit(generator["builder"], x86_64.mov_imm64(0, 60))
                call assembler.emit(generator["builder"], x86_64.syscall())
            end
        elif kind == "delete":
            target = statement["target"]
            if target["kind"] == "index":
                target_type = infer_expression_type(target["target"], generator["types"], generator["function_returns"])
                if target_type == "Tuple" or target_type == "RealArray":
                    call unsupported(generator["path"], generator["lines"], statement, "fixed collection does not support del", "convert it with List(value) before deleting")
                end
                if target_type == "List":
                    delete_call = {"kind": "call", "line": statement["line"], "column": statement["column"], "end_column": statement["end_column"], "target": {"kind": "name", "name": "__lsl_delete_at"}, "arguments": [target["target"], target["index"]]}
                    call emit_expression(generator, delete_call)
                else:
                    call emit_expression(generator, target["target"])
                    call assembler.emit(generator["builder"], x86_64.push(0))
                    call emit_expression(generator, target["index"])
                    call assembler.emit(generator["builder"], x86_64.move_reg_reg(6, 0))
                    call assembler.emit(generator["builder"], x86_64.pop(7))
                    call assembler.relative(generator["builder"], [232], "runtime_dict_delete")
                end
            elif target["kind"] == "name":
                if target["name"] in generator["variables"]:
                    call assembler.emit(generator["builder"], x86_64.mov_imm64(0, 0))
                    call assembler.emit(generator["builder"], x86_64.store_stack(generator["variables"][target["name"]], 0))
                end
            else:
                call unsupported(generator["path"], generator["lines"], statement, "unsupported del target", "delete a name or Dictionary key")
            end
        elif kind == "class":
            class_slot = generator["variables"][statement["name"]]
            call assembler.relative(generator["builder"], [232], "runtime_dict_new")
            call assembler.emit(generator["builder"], x86_64.store_stack(class_slot, 0))
            class_end = label_name(generator, "class_end")
            if statement["condition"] != None:
                call emit_expression(generator, statement["condition"])
                call emit_truth(generator)
                call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(0, 0))
                call assembler.relative(generator["builder"], [15, 132], class_end)
            end
            for member in statement["body"]:
                if member["kind"] == "assign":
                    if member["target"]["kind"] != "name" or member["operator"] != "=":
                        call unsupported(generator["path"], generator["lines"], member, "class fields require simple assignment", "use name = value in the class body")
                    end
                    call assembler.emit(generator["builder"], x86_64.load_stack(0, class_slot))
                    call assembler.emit(generator["builder"], x86_64.push(0))
                    call emit_string_pointer(generator, member["target"]["name"])
                    call assembler.emit(generator["builder"], x86_64.push(0))
                    call emit_expression(generator, member["value"])
                    call assembler.emit(generator["builder"], x86_64.move_reg_reg(2, 0))
                    call assembler.emit(generator["builder"], x86_64.pop(6))
                    call assembler.emit(generator["builder"], x86_64.pop(7))
                    call assembler.relative(generator["builder"], [232], "runtime_dict_set")
                elif member["kind"] != "function" and member["kind"] != "ctype":
                    call unsupported(generator["path"], generator["lines"], member, "unsupported class body statement", "use fields, ctype, and function methods")
                end
            end
            call assembler.label(generator["builder"], class_end)
        elif kind == "function":
            # Function bodies are emitted in the declaration pass.
            value = None
        elif kind == "load":
            call unsupported(generator["path"], generator["lines"], statement, "load code generation reached the linked program", "check module linker lowering")
        elif kind == "return":
            if return_label == "":
                call unsupported(generator["path"], generator["lines"], statement, "return used outside a function", "move return into a function")
            end
            if statement["expression"] == None:
                call assembler.emit(generator["builder"], x86_64.mov_imm64(0, 0))
            else:
                call emit_expression(generator, statement["expression"])
            end
            call assembler.relative(generator["builder"], [233], return_label)
        else:
            call unsupported(generator["path"], generator["lines"], statement, "statement kind " + kind + " is not implemented", "use scalar assignment, print, if, while, loop, break, or continue")
        end
    end
end

function aligned_frame(variables):
    frame_size = len(variables) * 8
    while frame_size % 16 != 0:
        frame_size += 1
    end
    return frame_size
end

function class_table(program):
    result = {}
    for statement in program:
        if statement["kind"] == "class":
            result[statement["name"]] = statement
        end
    end
    return result
end

function function_table(path, lines, program):
    functions = {}
    for statement in program:
        if statement["kind"] == "function":
            name = statement["name"]
            if name in functions:
                call unsupported(path, lines, statement, "duplicate function: " + name, "rename one declaration")
            end
            functions[name] = statement
        elif statement["kind"] == "class":
            for member in statement["body"]:
                if member["kind"] == "function":
                    original_name = member["name"]
                    name = statement["name"] + "__" + original_name
                    if name in functions:
                        call unsupported(path, lines, member, "duplicate method: " + original_name, "rename one declaration")
                    end
                    member["class_name"] = statement["name"]
                    member["method_name"] = original_name
                    member["name"] = name
                    functions[name] = member
                end
            end
        end
    end
    return functions
end

function merge_return_type(current, candidate):
    if candidate == "None":
        return current
    elif current == "None":
        return candidate
    elif current == candidate:
        return current
    end
    return "Any"
end

function returned_type(statements, types, function_returns):
    result = "None"
    for statement in statements:
        kind = statement["kind"]
        if kind == "return":
            result = merge_return_type(result, infer_expression_type(statement["expression"], types, function_returns))
        elif kind == "if":
            for branch in statement["branches"]:
                branch_type = returned_type(branch[1], types, function_returns)
                result = merge_return_type(result, branch_type)
            end
            branch_type = returned_type(statement["otherwise"], types, function_returns)
            result = merge_return_type(result, branch_type)
        elif kind == "while" or kind == "loop" or kind == "for":
            branch_type = returned_type(statement["body"], types, function_returns)
            result = merge_return_type(result, branch_type)
        elif kind == "safe" or kind == "try":
            branch_type = returned_type(statement["body"], types, function_returns)
            result = merge_return_type(result, branch_type)
            branch_type = returned_type(statement["otherwise"], types, function_returns)
            result = merge_return_type(result, branch_type)
        end
    end
    return result
end

function infer_function_returns(functions):
    result = {}
    names = functions.keys()
    for name in names:
        result[name] = "Any"
    end
    for pass_index in rang(4):
        for name in names:
            declaration = functions[name]
            types = {}
            for parameter in declaration["parameters"]:
                types[parameter] = "Any"
            end
            call collect_types(declaration["body"], types, result)
            result[name] = returned_type(declaration["body"], types, result)
        end
    end
    return result
end

function emit_function(generator, declaration):
    name = declaration["name"]
    variables = {}
    for parameter in declaration["parameters"]:
        variables[parameter] = -(len(variables) + 1) * 8
    end
    call collect_variables(declaration["body"], variables)
    types = {}
    for global_name in generator["global_types"].keys():
        types[global_name] = generator["global_types"][global_name]
    end
    for parameter in declaration["parameters"]:
        types[parameter] = "Any"
    end
    if "class_name" in declaration:
        if len(declaration["parameters"]) > 0:
            if declaration["parameters"][0] == "self":
                types["self"] = "Instance:" + declaration["class_name"]
            end
        end
    end
    call collect_types(declaration["body"], types, generator["function_returns"])
    old_variables = generator["variables"]
    old_types = generator["types"]
    old_error_label = generator["error_label"]
    generator["variables"] = variables
    generator["types"] = types
    call assembler.label(generator["builder"], "function_" + name)
    call assembler.emit(generator["builder"], x86_64.function_prologue(aligned_frame(variables)))
    argument_registers = [7, 6, 2, 1, 8, 9]
    index = 0
    while index < len(declaration["parameters"]):
        parameter = declaration["parameters"][index]
        if index < len(argument_registers):
            call assembler.emit(generator["builder"], x86_64.store_stack(variables[parameter], argument_registers[index]))
        else:
            call assembler.emit(generator["builder"], x86_64.load_stack(0, 16 + (index - len(argument_registers)) * 8))
            call assembler.emit(generator["builder"], x86_64.store_stack(variables[parameter], 0))
        end
        index += 1
    end
    return_label = label_name(generator, "return_" + name)
    generator["error_label"] = return_label
    call emit_statements(generator, declaration["body"], "", "", return_label)
    call assembler.emit(generator["builder"], x86_64.mov_imm64(0, 0))
    call assembler.label(generator["builder"], return_label)
    call assembler.emit(generator["builder"], x86_64.function_epilogue())
    generator["variables"] = old_variables
    generator["types"] = old_types
    generator["error_label"] = old_error_label
end

function generate(path, source, program):
    lines = source.split(chr(10))
    classes = class_table(program)
    functions = function_table(path, lines, program)
    function_returns = infer_function_returns(functions)
    for class_name in classes.keys():
        function_returns["__class__" + class_name] = "Instance:" + class_name
    end
    main_variables = {}
    call collect_variables(program, main_variables)
    main_types = {}
    call collect_types(program, main_types, function_returns)
    output = assembler.builder()
    generator = {"path": path, "lines": lines, "variables": {}, "types": {}, "global_variables": main_variables, "global_types": main_types, "functions": functions, "classes": classes, "function_returns": function_returns, "builder": output, "data": [], "relocations": [], "counter": 0, "error_label": ""}
    call native_runtime.emit_all(output)

    for statement in program:
        if statement["kind"] == "function":
            call emit_function(generator, statement)
        elif statement["kind"] == "class":
            for member in statement["body"]:
                if member["kind"] == "function":
                    call emit_function(generator, member)
                end
            end
        end
    end

    generator["variables"] = main_variables
    generator["types"] = main_types
    call assembler.label(output, "main")
    main_offset = assembler.position(output)
    call assembler.emit(output, x86_64.move_reg_reg(15, 4))
    call assembler.emit(output, x86_64.xor_reg_reg(14, 14))
    call assembler.emit(output, x86_64.xor_reg_reg(13, 13))
    call assembler.emit(output, x86_64.function_prologue(aligned_frame(main_variables)))
    call assembler.emit(output, x86_64.mov_imm64(0, 12))
    call assembler.emit(output, x86_64.mov_imm64(7, 0))
    call assembler.emit(output, x86_64.syscall())
    call assembler.emit(output, x86_64.move_reg_reg(3, 0))
    call assembler.emit(output, x86_64.lea_base(8, 3, 64))
    call assembler.emit(output, x86_64.move_reg_reg(9, 8))
    call assembler.emit(output, x86_64.add_reg_imm32(9, 134217728))
    call assembler.emit(output, x86_64.move_reg_reg(7, 9))
    call assembler.emit(output, x86_64.add_reg_imm32(7, 1048576))
    call assembler.emit(output, x86_64.mov_imm64(0, 12))
    call assembler.emit(output, x86_64.syscall())
    call assembler.emit(output, x86_64.store_memory(3, 32, 8))
    call assembler.emit(output, x86_64.mov_imm64(10, 16777215))
    call assembler.emit(output, x86_64.store_memory(3, 40, 10))
    call assembler.emit(output, x86_64.store_memory(3, 48, 9))
    call assembler.emit(output, x86_64.mov_imm64(10, 65535))
    call assembler.emit(output, x86_64.store_memory(3, 56, 10))
    call assembler.emit(output, x86_64.move_reg_reg(12, 5))
    call assembler.emit(output, x86_64.move_reg_reg(7, 4))
    call assembler.emit(output, x86_64.move_reg_reg(6, 5))
    call assembler.relative(output, [232], "runtime_set_global_roots")
    call emit_statements(generator, program, "", "", "")
    call assembler.emit(output, x86_64.mov_imm64(0, 60))
    call assembler.emit(output, x86_64.mov_imm64(7, 0))
    call assembler.emit(output, x86_64.syscall())
    program_code = assembler.finish(output)
    for relocation in generator["relocations"]:
        displacement = len(program_code) + relocation[2] - relocation[1]
        call bytes.patch_little(program_code, relocation[0], displacement, 4)
    end
    return elf_image.image_entry(program_code, generator["data"], main_offset)
end
