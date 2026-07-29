# Native scalar/control-flow code generator over the token-span AST.

load assembler
load bytes
load diagnostics
load elf_image
load native_runtime
load parser
load x86_64

function context(path, source_text, syntax):
    line = syntax["line"]
    source = ""
    actual_path = path
    if "path" in syntax:
        actual_path = syntax["path"]
    end
    actual_source = source_text
    if actual_path != path and exists(actual_path):
        # Linked-node source text is loaded only on a failing diagnostic path;
        # successful builds keep source text compact instead of materializing
        # line Lists or duplicating a `source` field into every AST Dictionary.
        actual_source = readfile(actual_path)
    end
    actual_lines = actual_source.split(chr(10))
    if line >= 1 and line <= len(actual_lines):
        source = actual_lines[line - 1]
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
            selected = constant_if_body(statement)
            if selected[0]:
                call collect_variables(selected[1], variables)
            else:
                for branch in statement["branches"]:
                    call collect_variables(branch[1], variables)
                end
                call collect_variables(statement["otherwise"], variables)
            end
        elif kind == "while" or kind == "loop":
            include_body = True
            if kind == "while":
                condition = constant_truth_expression(statement["condition"])
                include_body = not condition[0] or condition[1]
            end
            if include_body:
                call collect_variables(statement["body"], variables)
            end
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
        if kind == "return" or kind == "break" or kind == "continue" or kind == "error":
            break
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
        # Lexical/local values shadow global function declarations. Checking the
        # function table first misclassified locals such as current/image as
        # callbacks and leaked their Function box address into generated code.
        if syntax["name"] in types:
            return types[syntax["name"]]
        elif syntax["name"] in function_returns:
            return "Function"
        end
        return "Any"
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
            elif left == "Any" or right == "Any":
                return "Any"
            end
        elif syntax["operator"] == "-" or syntax["operator"] == "/":
            if syntax["operator"] == "/" or left == "Float" or right == "Float":
                return "Float"
            elif left == "Any" or right == "Any":
                return "Any"
            end
        elif syntax["operator"] == "^":
            if left == "Float" or right == "Float":
                return "Float"
            elif left == "Any" or right == "Any":
                return "Any"
            end
        elif syntax["operator"] == "//" or syntax["operator"] == "%":
            if left == "Float" or right == "Float":
                return "Float"
            elif left == "Any" or right == "Any":
                # Dynamic Int/Float dispatch also normalizes tagged Int operands.
                return "Any"
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
        elif target_type == "IntArray":
            return "Int"
        elif target_type == "FloatArray":
            return "Float"
        elif target_type == "ByteArray":
            return "Int"
        end
        return "Any"
    elif kind == "slice":
        return infer_expression_type(syntax["target"], types, function_returns)
    elif kind == "call":
        target = syntax["target"]
        if target["kind"] == "name":
            name = target["name"]
            if name == "abs":
                return infer_expression_type(syntax["arguments"][0], types, function_returns)
            end
            if name == "min" or name == "max":
                if len(syntax["arguments"]) == 2:
                    if infer_expression_type(syntax["arguments"][0], types, function_returns) == "Int" and infer_expression_type(syntax["arguments"][1], types, function_returns) == "Int":
                        return "Int"
                    end
                end
                return "Any"
            end
            if name == "sum":
                return "Any"
            end
            if name == "len" or name == "Int" or name == "ord" or name == "arg_count" or name == "run" or name == "__lsl_run" or name == "capture_status" or name == "native_u64" or name == "native_size" or name == "native_call" or name == "native_close" or name == "__lsl_type_code" or name == "__lsl_raw_equal" or name == "__lsl_float_bits" or name == "__lsl_float_to_int" or name == "__lsl_unbox_int" or name == "__lsl_raw_int" or name == "__lsl_typed_int" or name == "__lsl_parse_literal_int" or name == "__lsl_test_fd_fault" or name == "__lsl_address" or name == "__lsl_object_table_mask" or name == "__lsl_intern_table_mask" or name == "__lsl_fd_open" or name == "__lsl_fd_read" or name == "__lsl_fd_write" or name == "__lsl_fd_seek" or name == "__lsl_fd_close" or name == "__lsl_fd_socket" or name == "__lsl_fd_connect" or name == "__lsl_raster_pack" or name == "__lsl_raster_copy" or name == "__lsl_raster_fill" or name == "__lsl_fd_ioctl" or name == "__lsl_fd_mmap" or name == "__lsl_mem_pack" or name == "__lsl_data_address" or name == "__lsl_syscall" or name == "__lsl_mem_unpack" or name == "__lsl_byte_copy" or name == "__lsl_text_byte":
                return "Int"
            elif name == "Float" or name == "__lsl_float_from_bits" or name == "float_sum" or name == "float_dot" or name == "__lsl_wall_time":
                return "Float"
            elif name == "Bool" or name == "__lsl_isatty" or name == "__lsl_stdin_eof":
                return "Bool"
            elif name == "String" or name == "chr" or name == "arg" or name == "input" or name == "readfile" or name == "last_error" or name == "type" or name == "capture" or name == "__lsl_capture" or name == "capture_stream" or name == "capture_input" or name == "capture_stderr" or name == "executable_path" or name == "__lsl_text_from_bytes":
                return "String"
            elif name == "clock":
                return "Float"
            elif name == "exists" or name == "native_name_equal":
                return "Bool"
            elif name == "__lsl_sleep":
                return "None"
            elif name == "List":
                return "List"
            elif name == "Tuple":
                return "Tuple"
            elif name == "RealArray":
                return "RealArray"
            elif name == "IntArray" or name == "__lsl_int_zeros":
                return "IntArray"
            elif name == "FloatArray" or name == "float_zeros" or name == "float_matmul":
                return "FloatArray"
            elif name == "ByteArray" or name == "readbytes" or name == "__lsl_byte_zeros":
                return "ByteArray"
            elif name == "Dictionary":
                return "Dictionary"
            elif "__class__" + name in function_returns:
                return function_returns["__class__" + name]
            elif name in function_returns:
                return function_returns[name]
            end
        elif target["kind"] == "member":
            member = target["name"]
            receiver_type = infer_expression_type(target["target"], types, function_returns)
            if receiver_type.startswith("Class:") or receiver_type.startswith("Instance:"):
                if receiver_type.startswith("Class:"):
                    receiver_class = receiver_type[6:len(receiver_type)]
                else:
                    receiver_class = receiver_type[9:len(receiver_type)]
                end
                receiver_method = receiver_class + "__" + member
                if receiver_method in function_returns:
                    return function_returns[receiver_method]
                end
            end
            if member == "append" or member == "extend" or member == "sort" or member == "reverse" or member == "clear":
                return "None"
            elif member == "strip" or member == "lstrip" or member == "rstrip" or member == "join" or member == "replace" or member == "lower" or member == "upper" or member == "title" or member == "capitalize":
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
                if statement["operator"] == "=":
                    assigned_type = infer_expression_type(statement["value"], types, function_returns)
                else:
                    operator = statement["operator"][0:len(statement["operator"]) - 1]
                    combined = {"kind": "binary", "operator": operator, "left": statement["target"], "right": statement["value"]}
                    assigned_type = infer_expression_type(combined, types, function_returns)
                end
                if name in types and types[name] != assigned_type:
                    types[name] = "Any"
                else:
                    types[name] = assigned_type
                end
            end
        elif kind == "for":
            for_is_range = False
            for_iterable = statement["iterable"]
            if for_iterable["kind"] == "call":
                if for_iterable["target"]["kind"] == "name":
                    if for_iterable["target"]["name"] == "rang" or for_iterable["target"]["name"] == "range":
                        for_is_range = True
                    end
                end
            end
            iterable_type = infer_expression_type(for_iterable, types, function_returns)
            if for_is_range:
                types[statement["name"]] = "Int"
            elif iterable_type == "String":
                types[statement["name"]] = "String"
            elif iterable_type == "IntArray":
                types[statement["name"]] = "Int"
            elif iterable_type == "FloatArray":
                types[statement["name"]] = "Float"
            elif iterable_type == "ByteArray":
                types[statement["name"]] = "Int"
            else:
                # List/Tuple/RealArray/Dictionary/Any elements are dynamic; Int
                # would miscompile boxed Float/None elements (e.g. sum of Floats).
                types[statement["name"]] = "Any"
            end
            call collect_types(statement["body"], types, function_returns)
        elif kind == "if":
            selected = constant_if_body(statement)
            if selected[0]:
                call collect_types(selected[1], types, function_returns)
            else:
                for branch in statement["branches"]:
                    call collect_types(branch[1], types, function_returns)
                end
                call collect_types(statement["otherwise"], types, function_returns)
            end
        elif kind == "while" or kind == "loop":
            include_body = True
            if kind == "while":
                condition = constant_truth_expression(statement["condition"])
                include_body = not condition[0] or condition[1]
            end
            if include_body:
                call collect_types(statement["body"], types, function_returns)
            end
        elif kind == "safe" or kind == "try":
            call collect_types(statement["body"], types, function_returns)
            call collect_types(statement["otherwise"], types, function_returns)
        end
        if kind == "return" or kind == "break" or kind == "continue" or kind == "error":
            break
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
    elif name == "capitalize":
        return "__lsl_capitalize"
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
    elif name == "reverse":
        return "__lsl_reverse"
    elif name == "copy":
        return "__lsl_copy"
    elif name == "get":
        return "__lsl_dict_get"
    elif name == "setdefault":
        return "__lsl_setdefault"
    elif name == "update":
        return "__lsl_update"
    elif name == "values":
        return "__lsl_dict_values"
    elif name == "items":
        return "__lsl_dict_items"
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
    if text in generator["string_offsets"]:
        offset = generator["string_offsets"][text]
    else:
        call align_data(generator)
        offset = len(generator["data"])
        payload = bytes.utf8(text)
        generator["data"].extend(bytes.little(1, 8))
        generator["data"].extend(bytes.little(len(payload), 8))
        generator["data"].extend(payload)
        generator["data"].append(0)
        generator["string_offsets"][text] = offset
    end
    lea_start = assembler.position(generator["builder"])
    call assembler.emit(generator["builder"], x86_64.lea_rip(0, 0))
    generator["relocations"].append([lea_start + 3, lea_start + 7, offset])
    call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
    call assembler.relative(generator["builder"], [232], "runtime_string_clone")
end

function float_bits(text):
    # Parse via the runtime Float path (hardware doubles) and read the IEEE-754
    # bit pattern. The old exact-integer algorithm overflowed Int64 for large
    # exponents (e.g. 1e20 looped forever, 1e300 gave 0); doubles handle the
    # full range including Infinity for overflow.
    return __lsl_float_bits(__lsl_parse_float(text))
end

function emit_truth(generator):
    call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
    call assembler.relative(generator["builder"], [232], "runtime_truth")
end

function maybe_collection(value_type):
    return value_type == "List" or value_type == "Tuple" or value_type == "RealArray" or value_type == "IntArray" or value_type == "FloatArray" or value_type == "ByteArray" or value_type == "Dictionary" or value_type == "Any"
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

function integer_literal(syntax):
    stored = __lsl_typed_int(syntax["integer_value"])
    parsed = __lsl_parse_literal_int(syntax["value"])
    if stored != parsed:
        Error(CompilerInvariantError: "integer literal AST changed before emission")
    end
    return parsed
end

function constant_int_expression(syntax):
    if syntax == None:
        return [False, 0]
    end
    kind = syntax["kind"]
    if kind == "literal":
        if syntax["literal_kind"] != "number":
            return [False, 0]
        end
        text = syntax["value"]
        if text.find(".") >= 0 or text.find("e") >= 0 or text.find("E") >= 0:
            return [False, 0]
        end
        return [True, integer_literal(syntax)]
    elif kind == "unary" and syntax["operator"] == "-":
        operand = constant_int_expression(syntax["operand"])
        if operand[0]:
            return [True, -operand[1]]
        end
        return [False, 0]
    elif kind != "binary":
        return [False, 0]
    end
    left = constant_int_expression(syntax["left"])
    right = constant_int_expression(syntax["right"])
    if not left[0] or not right[0]:
        return [False, 0]
    end
    operator = syntax["operator"]
    if operator == "+":
        return [True, left[1] + right[1]]
    elif operator == "-":
        return [True, left[1] - right[1]]
    elif operator == "*":
        return [True, left[1] * right[1]]
    elif operator == "//" and right[1] != 0:
        return [True, left[1] // right[1]]
    elif operator == "%" and right[1] != 0:
        return [True, left[1] % right[1]]
    elif operator == "^" and right[1] >= 0 and right[1] <= 63:
        return [True, left[1] ^ right[1]]
    end
    return [False, 0]
end

function constant_truth_expression(syntax):
    if syntax == None:
        return [False, False]
    end
    kind = syntax["kind"]
    if kind == "literal":
        if syntax["value"] == "True":
            return [True, True]
        elif syntax["value"] == "False" or syntax["value"] == "None":
            return [True, False]
        end
        integer = constant_int_expression(syntax)
        if integer[0]:
            return [True, integer[1] != 0]
        end
        return [False, False]
    elif kind == "unary" and syntax["operator"] == "not":
        operand = constant_truth_expression(syntax["operand"])
        if operand[0]:
            return [True, not operand[1]]
        end
        return [False, False]
    elif kind == "binary" and (syntax["operator"] == "and" or syntax["operator"] == "or"):
        left_truth = constant_truth_expression(syntax["left"])
        right_truth = constant_truth_expression(syntax["right"])
        if left_truth[0] and right_truth[0]:
            if syntax["operator"] == "and":
                return [True, left_truth[1] and right_truth[1]]
            end
            return [True, left_truth[1] or right_truth[1]]
        end
        return [False, False]
    elif kind != "compare":
        return [False, False]
    end
    index = 0
    while index < len(syntax["operators"]):
        left = constant_int_expression(syntax["operands"][index])
        right = constant_int_expression(syntax["operands"][index + 1])
        if not left[0] or not right[0]:
            return [False, False]
        end
        operator = syntax["operators"][index]
        matches = False
        if operator == "==" or operator == "is":
            matches = left[1] == right[1]
        elif operator == "!=" or operator == "is not":
            matches = left[1] != right[1]
        elif operator == "<":
            matches = left[1] < right[1]
        elif operator == "<=":
            matches = left[1] <= right[1]
        elif operator == ">":
            matches = left[1] > right[1]
        elif operator == ">=":
            matches = left[1] >= right[1]
        else:
            return [False, False]
        end
        if not matches:
            return [True, False]
        end
        index += 1
    end
    return [True, True]
end

function constant_string_expression(syntax):
    if syntax == None:
        return [False, ""]
    end
    if syntax["kind"] == "literal" and syntax["literal_kind"] == "string":
        return [True, syntax["value"]]
    elif syntax["kind"] != "binary" or syntax["operator"] != "+":
        return [False, ""]
    end
    left = constant_string_expression(syntax["left"])
    right = constant_string_expression(syntax["right"])
    if left[0] and right[0]:
        return [True, left[1] + right[1]]
    end
    return [False, ""]
end

function constant_if_body(statement):
    for branch in statement["branches"]:
        condition = constant_truth_expression(branch[0])
        if not condition[0]:
            return [False, []]
        elif condition[1]:
            return [True, branch[1]]
        end
    end
    return [True, statement["otherwise"]]
end

function power_of_two_exponent(syntax):
    # k if syntax is a positive power-of-two Int literal (2^k), else -1.
    if syntax["kind"] != "literal":
        return -1
    end
    if syntax["literal_kind"] != "number":
        return -1
    end
    value = syntax["value"]
    if value.find(".") >= 0 or value.find("e") >= 0 or value.find("E") >= 0:
        return -1
    end
    number = integer_literal(syntax)
    if number <= 0:
        return -1
    end
    exponent = 0
    while number > 1:
        if number % 2 != 0:
            return -1
        end
        number = number // 2
        exponent += 1
    end
    return exponent
end

function pow63_divmod(m):
    # Returns [q, r] with q = (2^63) // m, r = (2^63) % m, for 1 <= m < 2^62,
    # using 2^62 (representable) to avoid materializing 2^63.
    pow62 = 4611686018427387904
    q = (pow62 // m) * 2
    r = (pow62 % m) * 2
    if r >= m:
        q += 1
        r -= m
    end
    return [q, r]
end

function magic_signed(divisor):
    # Granlund-Montgomery signed magic for a constant divisor d in [3, 2^31).
    # Returns [M, s]: floor-free truncated quotient is high64(n*M) [+n if M<0]
    # then >> s. Pure signed 64-bit math (q2 may wrap as a bit pattern).
    pow63_minus_1 = 9223372036854775807
    ad = divisor
    t = pow63_minus_1 - ((pow63_minus_1 % ad + 1) % ad)
    anc = t
    # anc lies in (2^62, 2^63), so (2^63)//anc == 1 and (2^63)%anc == 2^63-anc.
    r1 = pow63_minus_1 - anc + 1
    q1 = 1
    divmod2 = pow63_divmod(ad)
    q2 = divmod2[0]
    r2 = divmod2[1]
    p = 63
    delta = 0
    keep_going = True
    while keep_going:
        p += 1
        q1 = q1 * 2
        if r1 >= anc - r1:
            q1 += 1
            r1 = r1 - (anc - r1)
        else:
            r1 = r1 + r1
        end
        q2 = q2 * 2
        if r2 >= ad - r2:
            q2 += 1
            r2 = r2 * 2 - ad
        else:
            r2 = r2 * 2
        end
        delta = ad - r2
        keep_going = q1 < delta or (q1 == delta and r1 == 0)
    end
    magic = q2 + 1
    return [magic, p - 64]
end

function inverted_branch(operator):
    # jcc bytes that jump when the comparison is FALSE.
    if operator == "==" or operator == "is":
        return [15, 133]
    elif operator == "!=" or operator == "is not":
        return [15, 132]
    elif operator == "<":
        return [15, 141]
    elif operator == "<=":
        return [15, 143]
    elif operator == ">":
        return [15, 142]
    elif operator == ">=":
        return [15, 140]
    end
    return []
end

function direct_scalar_equality(left_type, right_type):
    return left_type == right_type and (left_type == "Int" or left_type == "Bool" or left_type == "None")
end

function emit_branch_if_false(generator, syntax, target_label):
    # Static scalar comparisons branch directly on flags (cmp + inverted jcc),
    # skipping setcc/movzx/cmp-0 and dynamic equality dispatch. Returns True if
    # it handled the branch.
    if syntax["kind"] != "compare":
        return False
    end
    if len(syntax["operators"]) != 1:
        return False
    end
    operator = syntax["operators"][0]
    ordered = operator == "<" or operator == "<=" or operator == ">" or operator == ">="
    equality = operator == "==" or operator == "!=" or operator == "is" or operator == "is not"
    if not ordered and not equality:
        return False
    end
    left = syntax["operands"][0]
    right = syntax["operands"][1]
    left_type = infer_expression_type(left, generator["types"], generator["function_returns"])
    right_type = infer_expression_type(right, generator["types"], generator["function_returns"])
    if equality:
        if not direct_scalar_equality(left_type, right_type):
            return False
        end
    elif left_type == "Float" or right_type == "Float" or left_type == "Any" or right_type == "Any":
        return False
    end
    output = generator["builder"]
    right_constant = constant_int_expression(right)
    if right_constant[0] and x86_64.fits_signed32(right_constant[1]):
        call emit_expression(generator, left)
        call assembler.emit(output, x86_64.cmp_reg_imm32(0, right_constant[1]))
        call assembler.relative(output, inverted_branch(operator), target_label)
        return True
    elif is_int_leaf(generator, right):
        call emit_expression(generator, left)
        call emit_int_leaf(generator, right, 6)
    elif is_int_leaf(generator, left):
        call emit_expression(generator, right)
        call assembler.emit(output, x86_64.move_reg_reg(6, 0))
        call emit_int_leaf(generator, left, 0)
    else:
        call emit_expression(generator, left)
        call assembler.emit(output, x86_64.push(0))
        call emit_expression(generator, right)
        call assembler.emit(output, x86_64.move_reg_reg(6, 0))
        call assembler.emit(output, x86_64.pop(0))
    end
    call assembler.emit(output, x86_64.cmp_reg_reg(0, 6))
    call assembler.relative(output, inverted_branch(operator), target_label)
    return True
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
        call assembler.emit(output, x86_64.mov_imm64(register, integer_literal(syntax)))
    else:
        name = syntax["name"]
        if name in generator["variables"]:
            call assembler.emit(output, x86_64.load_stack(register, generator["variables"][name]))
        else:
            call assembler.emit(output, x86_64.load_memory(register, 12, generator["global_variables"][name]))
        end
    end
end

function runtime_scalar_tag(value_type):
    if value_type == "Int":
        return 0
    elif value_type == "Bool":
        return 4
    elif value_type == "None":
        return 5
    elif value_type == "Float":
        return 6
    elif value_type == "Function":
        return 10
    end
    return -1
end

function emit_collection_box(generator, syntax):
    value_type = infer_expression_type(syntax, generator["types"], generator["function_returns"])
    if value_type == "Bool":
        if generator["internal_abi"]:
            return
        end
        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
        call assembler.relative(generator["builder"], [232], "runtime_box_bool")
    elif value_type == "Int":
        # The self-host compiler is a typed trust core: its byte, token, index,
        # register and offset Lists keep Ints raw. Public programs still use the
        # unambiguous boxed dynamic ABI at call/collection boundaries.
        if generator["internal_abi"]:
            return
        end
        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
        call assembler.relative(generator["builder"], [232], "runtime_box_typed_int")
    elif value_type == "Function":
        # Function boxes carry the statically known return scalar tag so an
        # indirect call can re-establish the tagged Any result ABI.
        if not generator["internal_abi"]:
            return_type = "Any"
            if syntax["kind"] == "name" and syntax["name"] in generator["function_returns"]:
                return_type = generator["function_returns"][syntax["name"]]
            end
            call assembler.emit(generator["builder"], x86_64.mov_imm64(6, runtime_scalar_tag(return_type)))
            call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
            call assembler.relative(generator["builder"], [232], "runtime_box_dynamic_function")
        end
    elif value_type == "Any" and syntax["kind"] == "binary" and syntax["operator"] != "and" and syntax["operator"] != "or":
        if generator["internal_abi"]:
            return
        end
        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
        call assembler.relative(generator["builder"], [232], "runtime_box_dynamic_int")
    elif value_type == "None":
        if generator["internal_abi"]:
            return
        end
        call assembler.relative(generator["builder"], [232], "runtime_box_none")
    end
end

function emit_dynamic_boundary_box(generator, syntax):
    if not generator["internal_abi"]:
        call emit_collection_box(generator, syntax)
    end
end

function emit_dictionary_key_box(generator, syntax):
    key_type = infer_expression_type(syntax, generator["types"], generator["function_returns"])
    if key_type == "List" or key_type == "Tuple" or key_type == "RealArray" or key_type == "IntArray" or key_type == "FloatArray" or key_type == "ByteArray" or key_type == "Dictionary" or key_type.startswith("Class:") or key_type.startswith("Instance:"):
        call unsupported(generator["path"], generator["lines"], syntax, "mutable or collection value cannot be a Dictionary key", "use String, Int, Bool, None, Float, or Function keys")
    end
    call emit_collection_box(generator, syntax)
end

function dynamic_numeric_runtime(generator, name):
    if generator["internal_abi"]:
        return name + "_raw"
    end
    return name
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

function emit_bounds_check(generator, syntax, target_type):
    source_path = syntax.get("path", generator["path"])
    bounds_nonnegative = label_name(generator, "bounds_nonnegative")
    bounds_ok = label_name(generator, "bounds_ok")
    call assembler.emit(generator["builder"], x86_64.push(7))
    call assembler.emit(generator["builder"], x86_64.push(6))
    if target_type == "List" or target_type == "Tuple" or target_type == "RealArray" or target_type == "IntArray" or target_type == "FloatArray" or target_type == "ByteArray":
        call assembler.emit(generator["builder"], x86_64.load_memory(0, 7, 8))
    else:
        call assembler.relative(generator["builder"], [232], "runtime_length")
    end
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
        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
        call assembler.relative(generator["builder"], [232], "runtime_coerce_float")
    elif value_type != "Float":
        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
        call assembler.relative(generator["builder"], [232], "runtime_float_from_int")
    end
end

function emit_expression(generator, syntax):
    output = generator["builder"]
    kind = syntax["kind"]
    if kind == "binary" or kind == "unary":
        constant_string = constant_string_expression(syntax)
        if constant_string[0]:
            call emit_string_pointer(generator, constant_string[1])
            return
        end
        constant_integer = constant_int_expression(syntax)
        if constant_integer[0]:
            call assembler.emit(output, x86_64.mov_imm64(0, constant_integer[1]))
            return
        end
    elif kind == "compare":
        constant_truth = constant_truth_expression(syntax)
        if constant_truth[0]:
            truth_value = 0
            if constant_truth[1]:
                truth_value = 1
            end
            call assembler.emit(output, x86_64.mov_imm64(0, truth_value))
            return
        end
    end
    if kind == "literal":
        value = syntax["value"]
        if syntax["literal_kind"] == "string":
            call emit_string_pointer(generator, value)
        elif syntax["literal_kind"] == "number":
            if value.find(".") >= 0 or value.find("e") >= 0 or value.find("E") >= 0:
                call assembler.emit(output, x86_64.mov_imm64(7, float_bits(value)))
                call assembler.relative(output, [232], "runtime_float_new")
            else:
                call assembler.emit(output, x86_64.mov_imm64(0, integer_literal(syntax)))
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
            call emit_dictionary_key_box(generator, entry[0])
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
        target_slice_type = infer_expression_type(syntax["target"], generator["types"], generator["function_returns"])
        if target_slice_type == "ByteArray":
            call unsupported(generator["path"], generator["lines"], syntax, "ByteArray slicing is not implemented", "copy bytes with indexed access")
        end
        if syntax.get("step", None) != None:
            # Strided slice via pure-LSL helper (Python step semantics).
            zero_literal = {"kind": "literal", "literal_kind": "number", "value": "0", "integer_value": 0, "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
            true_literal = {"kind": "literal", "literal_kind": "name", "value": "True", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
            false_literal = {"kind": "literal", "literal_kind": "name", "value": "False", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
            start_arg = zero_literal
            has_start = false_literal
            if syntax["start"] != None:
                start_arg = syntax["start"]
                has_start = true_literal
            end
            stop_arg = zero_literal
            has_stop = false_literal
            if syntax["stop"] != None:
                stop_arg = syntax["stop"]
                has_stop = true_literal
            end
            slice_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_slice3"}, "arguments": [syntax["target"], start_arg, has_start, stop_arg, has_stop, syntax["step"]]}
            call emit_expression(generator, slice_call)
            target_slice_type = infer_expression_type(syntax["target"], generator["types"], generator["function_returns"])
            if target_slice_type == "Tuple":
                call assembler.emit(output, x86_64.store_memory_imm32(0, 0, 7))
            elif target_slice_type == "RealArray":
                call assembler.emit(output, x86_64.store_memory_imm32(0, 0, 8))
            elif target_slice_type == "IntArray":
                call assembler.emit(output, x86_64.store_memory_imm32(0, 0, 13))
            elif target_slice_type == "FloatArray":
                call assembler.emit(output, x86_64.store_memory_imm32(0, 0, 14))
            end
            return
        end
        call emit_expression(generator, syntax["target"])
        call assembler.emit(output, x86_64.push(0))
        if syntax["start"] == None:
            call assembler.emit(output, x86_64.mov_imm64(0, 0))
        else:
            call emit_expression(generator, syntax["start"])
            if infer_expression_type(syntax["start"], generator["types"], generator["function_returns"]) == "Any":
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
            end
        end
        call assembler.emit(output, x86_64.push(0))
        if syntax["stop"] == None:
            call assembler.emit(output, x86_64.load_memory(7, 4, 8))
            call assembler.relative(output, [232], "runtime_length")
        else:
            call emit_expression(generator, syntax["stop"])
            if infer_expression_type(syntax["stop"], generator["types"], generator["function_returns"]) == "Any":
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
            end
        end
        call assembler.emit(output, x86_64.move_reg_reg(2, 0))
        call assembler.emit(output, x86_64.pop(6))
        call assembler.emit(output, x86_64.pop(7))
        call assembler.relative(output, [232], "runtime_slice")
        target_slice_type = infer_expression_type(syntax["target"], generator["types"], generator["function_returns"])
        if target_slice_type == "Tuple":
            call assembler.emit(output, x86_64.store_memory_imm32(0, 0, 7))
        elif target_slice_type == "RealArray":
            call assembler.emit(output, x86_64.store_memory_imm32(0, 0, 8))
        elif target_slice_type == "IntArray":
            call assembler.emit(output, x86_64.store_memory_imm32(0, 0, 13))
        elif target_slice_type == "FloatArray":
            call assembler.emit(output, x86_64.store_memory_imm32(0, 0, 14))
        end
    elif kind == "index":
        target_type = infer_expression_type(syntax["target"], generator["types"], generator["function_returns"])
        call emit_expression(generator, syntax["target"])
        call assembler.emit(output, x86_64.push(0))
        call emit_expression(generator, syntax["index"])
        if target_type == "Dictionary":
            call emit_dictionary_key_box(generator, syntax["index"])
        elif infer_expression_type(syntax["index"], generator["types"], generator["function_returns"]) == "Any":
            call assembler.emit(output, x86_64.move_reg_reg(7, 0))
            call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
        end
        call assembler.emit(output, x86_64.move_reg_reg(6, 0))
        call assembler.emit(output, x86_64.pop(7))
        if target_type == "Dictionary":
            call assembler.relative(output, [232], "runtime_dict_get")
        else:
            if target_type == "String" or target_type == "List" or target_type == "Tuple" or target_type == "RealArray" or target_type == "IntArray" or target_type == "FloatArray" or target_type == "ByteArray":
                call emit_bounds_check(generator, syntax, target_type)
            end
            if target_type == "ByteArray":
                call assembler.relative(output, [232], "runtime_byte_array_get")
            elif target_type == "List" or target_type == "Tuple" or target_type == "RealArray" or target_type == "IntArray" or target_type == "FloatArray":
                call assembler.relative(output, [232], "runtime_list_get")
                if target_type == "FloatArray":
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_float_new")
                end
            else:
                call assembler.relative(output, [232], "runtime_get")
            end
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
            elif operand_type == "Any":
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], dynamic_numeric_runtime(generator, "runtime_neg_any"))
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
        if (operator == "//" or operator == "%") and (expression_type == "Float" or expression_type == "Any"):
            # Float floor-division/modulo, or dynamic Int/Float dispatch when both
            # operands are Any. Must precede the Float +-*/ block (which rejects
            # // and %).
            if operator == "%":
                floor_target = "__lsl_fmod"
                if expression_type == "Any":
                    floor_target = "__lsl_mod_dyn"
                end
            else:
                floor_target = "__lsl_ffloordiv"
                if expression_type == "Any":
                    floor_target = "__lsl_floordiv_dyn"
                end
            end
            floor_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": floor_target}, "arguments": [syntax["left"], syntax["right"]]}
            call emit_expression(generator, floor_call)
            return
        end
        if expression_type == "Float":
            if operator == "^":
                exponent_type = infer_expression_type(syntax["right"], generator["types"], generator["function_returns"])
                if exponent_type != "Int" and exponent_type != "Any":
                    call unsupported(generator["path"], generator["lines"], syntax, "Float ^ requires an Int exponent", "use an Int exponent such as x ^ 3")
                end
                call emit_float_expression(generator, syntax["left"])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["right"])
                if exponent_type == "Any":
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                end
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
            if expression_type == "Any":
                call emit_dynamic_boundary_box(generator, syntax["left"])
            end
            call assembler.emit(output, x86_64.push(0))
            call emit_expression(generator, syntax["right"])
            if expression_type == "Any":
                call emit_dynamic_boundary_box(generator, syntax["right"])
            end
            call assembler.emit(output, x86_64.move_reg_reg(6, 0))
            call assembler.emit(output, x86_64.pop(7))
            if expression_type == "String":
                call assembler.relative(output, [232], "runtime_string_concat")
            else:
                call assembler.relative(output, [232], dynamic_numeric_runtime(generator, "runtime_add_any"))
            end
            return
        elif (operator == "-" or operator == "*") and expression_type == "Any":
            # Dynamic - / * : dispatch Int vs boxed Float at runtime.
            call emit_expression(generator, syntax["left"])
            call emit_dynamic_boundary_box(generator, syntax["left"])
            call assembler.emit(output, x86_64.push(0))
            call emit_expression(generator, syntax["right"])
            call emit_dynamic_boundary_box(generator, syntax["right"])
            call assembler.emit(output, x86_64.move_reg_reg(6, 0))
            call assembler.emit(output, x86_64.pop(7))
            if operator == "-":
                call assembler.relative(output, [232], dynamic_numeric_runtime(generator, "runtime_sub_any"))
            else:
                call assembler.relative(output, [232], dynamic_numeric_runtime(generator, "runtime_mul_any"))
            end
            return
        elif operator == "^" and expression_type == "Any":
            # Dynamic ^ : base may be boxed Float or raw Int; Int exponent.
            any_exp_type = infer_expression_type(syntax["right"], generator["types"], generator["function_returns"])
            if any_exp_type != "Int" and any_exp_type != "Any":
                call unsupported(generator["path"], generator["lines"], syntax, "^ requires an Int exponent", "use an Int exponent such as x ^ 3")
            end
            call emit_expression(generator, syntax["left"])
            call emit_dynamic_boundary_box(generator, syntax["left"])
            call assembler.emit(output, x86_64.push(0))
            call emit_expression(generator, syntax["right"])
            call emit_dynamic_boundary_box(generator, syntax["right"])
            call assembler.emit(output, x86_64.move_reg_reg(6, 0))
            call assembler.emit(output, x86_64.pop(7))
            call assembler.relative(output, [232], dynamic_numeric_runtime(generator, "runtime_pow_any"))
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
        # Int arithmetic path (Float/String/List handled above). Fold constant
        # subtrees into immediate operations while preserving evaluation of the
        # non-constant side. This makes mechanically generated or noisy source
        # as cheap as the direct spelling without reordering side effects.
        right_constant = constant_int_expression(syntax["right"])
        left_constant = constant_int_expression(syntax["left"])
        if right_constant[0] and x86_64.fits_signed32(right_constant[1]) and (operator == "+" or operator == "-" or operator == "*"):
            immediate = right_constant[1]
            call emit_expression(generator, syntax["left"])
            if operator == "+" and immediate != 0:
                call assembler.emit(output, x86_64.add_reg_imm32(0, immediate))
            elif operator == "-" and immediate != 0:
                call assembler.emit(output, x86_64.sub_reg_imm(0, immediate))
            elif operator == "*":
                if immediate == 0:
                    call assembler.emit(output, x86_64.mov_imm64(0, 0))
                elif immediate == -1:
                    call assembler.emit(output, x86_64.neg_reg(0))
                elif immediate != 1:
                    call assembler.emit(output, x86_64.imul_reg_imm(0, 0, immediate))
                end
            end
            return
        elif left_constant[0] and x86_64.fits_signed32(left_constant[1]) and (operator == "+" or operator == "*"):
            immediate = left_constant[1]
            call emit_expression(generator, syntax["right"])
            if operator == "+" and immediate != 0:
                call assembler.emit(output, x86_64.add_reg_imm32(0, immediate))
            elif operator == "*":
                if immediate == 0:
                    call assembler.emit(output, x86_64.mov_imm64(0, 0))
                elif immediate == -1:
                    call assembler.emit(output, x86_64.neg_reg(0))
                elif immediate != 1:
                    call assembler.emit(output, x86_64.imul_reg_imm(0, 0, immediate))
                end
            end
            return
        elif operator == "^" and right_constant[0] and right_constant[1] >= 0 and right_constant[1] <= 4:
            # Small fixed powers are cheaper inline than the generic
            # exponentiation-by-squaring call. Evaluate the base exactly once.
            small_power = right_constant[1]
            call emit_expression(generator, syntax["left"])
            if small_power == 0:
                call assembler.emit(output, x86_64.mov_imm64(0, 1))
            elif small_power == 2:
                call assembler.emit(output, x86_64.imul_reg_reg(0, 0))
            elif small_power == 3:
                call assembler.emit(output, x86_64.move_reg_reg(1, 0))
                call assembler.emit(output, x86_64.imul_reg_reg(0, 0))
                call assembler.emit(output, x86_64.imul_reg_reg(0, 1))
            elif small_power == 4:
                call assembler.emit(output, x86_64.imul_reg_reg(0, 0))
                call assembler.emit(output, x86_64.imul_reg_reg(0, 0))
            end
            return
        end
        # Avoid the push/pop spill when an operand is a literal or variable leaf.
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
        elif operator == "^":
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
        elif (operator == "//" or operator == "%") and power_of_two_exponent(syntax["right"]) >= 0:
            # Strength reduction: a % 2^k == a & (2^k-1), a // 2^k == a >> k
            # (arithmetic), exact under Python floor semantics for every a
            # including negatives and INT64_MIN. No idiv, no -1/overflow guard.
            power_exponent = power_of_two_exponent(syntax["right"])
            if operator == "%":
                call assembler.emit(output, x86_64.mov_imm64(1, integer_literal(syntax["right"]) - 1))
                call assembler.emit(output, x86_64.and_reg_reg(0, 1))
            else:
                call assembler.emit(output, x86_64.shift_right_arithmetic_imm(0, power_exponent))
            end
        elif (operator == "//" or operator == "%") and syntax["right"]["kind"] == "literal" and syntax["right"]["literal_kind"] == "number" and syntax["right"]["value"].find(".") < 0 and syntax["right"]["value"].find("e") < 0 and syntax["right"]["value"].find("E") < 0 and integer_literal(syntax["right"]) >= 3 and integer_literal(syntax["right"]) < 2147483648 and power_of_two_exponent(syntax["right"]) < 0:
            # Magic-number division: replace idiv by a signed high-multiply.
            # n is already in reg0. quotient q = floor(n/d); remainder via
            # n - q*d. d is a positive non-power-of-two constant in [3, 2^31).
            divisor_value = integer_literal(syntax["right"])
            magic_pair = magic_signed(divisor_value)
            magic_number = magic_pair[0]
            magic_shift = magic_pair[1]
            floor_done = label_name(generator, "magic_floor_done")
            call assembler.emit(output, x86_64.move_reg_reg(6, 0))
            call assembler.emit(output, x86_64.mov_imm64(1, magic_number))
            call assembler.emit(output, x86_64.imul_high_reg(1))
            if magic_number < 0:
                call assembler.emit(output, x86_64.add_reg_reg(2, 6))
            end
            if magic_shift > 0:
                call assembler.emit(output, x86_64.shift_right_arithmetic_imm(2, magic_shift))
            end
            call assembler.emit(output, x86_64.move_reg_reg(8, 6))
            call assembler.emit(output, x86_64.shift_right_logical_imm(8, 63))
            call assembler.emit(output, x86_64.add_reg_reg(2, 8))
            # reg2 = trunc(n/d). Convert to Python floor via the remainder.
            call assembler.emit(output, x86_64.mov_imm64(1, divisor_value))
            call assembler.emit(output, x86_64.move_reg_reg(9, 2))
            call assembler.emit(output, x86_64.imul_reg_reg(9, 1))
            call assembler.emit(output, x86_64.move_reg_reg(0, 6))
            call assembler.emit(output, x86_64.sub_reg_reg(0, 9))
            # reg0 = C remainder (sign of n). d>0, so if remainder<0 floor-correct.
            call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
            call assembler.relative(output, [15, 141], floor_done)
            call assembler.emit(output, x86_64.decrement(2))
            call assembler.emit(output, x86_64.add_reg_reg(0, 1))
            call assembler.label(output, floor_done)
            if operator == "//":
                call assembler.emit(output, x86_64.move_reg_reg(0, 2))
            end
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
            builtin_arity = {"Bool": 1, "Int": 1, "Float": 1, "String": 1, "List": 1, "Tuple": 1, "RealArray": 1, "Dictionary": 1, "len": 1, "chr": 1, "ord": 1, "abs": 1, "sum": 1, "float_zeros": 1, "float_fill": 2, "float_sum": 1, "float_dot": 2, "float_axpy": 3, "float_matmul": 5, "type": 1, "exit": 1, "input": 1, "readfile": 1, "readbytes": 1, "__lsl_getenv": 1, "mkdir": 1, "unlink": 1, "exists": 1, "gc": 0, "clock": 0, "arg_count": 0, "last_error": 0, "executable_path": 0, "help": 0, "run": 2, "capture": 2, "capture_stream": 3, "capture_input": 3, "capture_status": 0, "capture_stderr": 0, "writefile": 2, "appendfile": 2, "writebytes": 2, "check": 2, "native_open": 1, "native_size": 1, "native_u64": 2, "native_name_equal": 3, "native_function": 2, "native_call": 2, "native_close": 1, "__lsl_test_small_tables": 0, "__lsl_test_fd_fault": 1, "__lsl_object_table_mask": 0, "__lsl_intern_table_mask": 0, "__lsl_wall_time": 0, "__lsl_sleep": 1, "__lsl_isatty": 1, "__lsl_stdin_eof": 0, "__lsl_run": 2, "__lsl_capture": 2, "__lsl_fd_open": 2, "__lsl_fd_read": 3, "__lsl_fd_write": 3, "__lsl_fd_seek": 2, "__lsl_fd_close": 1, "__lsl_fd_socket": 2, "__lsl_fd_connect": 3, "__lsl_int_zeros": 1, "__lsl_byte_zeros": 1, "__lsl_raster_pack": 5, "__lsl_raster_copy": 5, "__lsl_raster_fill": 4, "__lsl_fd_ioctl": 3, "__lsl_fd_mmap": 3, "__lsl_mem_pack": 5, "__lsl_data_address": 1, "__lsl_syscall": 5, "__lsl_mem_unpack": 4, "__lsl_text_from_bytes": 3, "__lsl_byte_copy": 5, "__lsl_text_byte": 2}
            if target["name"] in builtin_arity:
                expected_builtin = builtin_arity[target["name"]]
                if len(syntax["arguments"]) != expected_builtin:
                    call unsupported(generator["path"], generator["lines"], syntax, "builtin " + target["name"] + " expects " + String(expected_builtin) + " argument(s), got " + String(len(syntax["arguments"])), "pass exactly " + String(expected_builtin) + " argument(s)")
                end
            elif target["name"] == "IntArray" or target["name"] == "FloatArray" or target["name"] == "ByteArray":
                if len(syntax["arguments"]) > 1:
                    call unsupported(generator["path"], generator["lines"], syntax, "builtin " + target["name"] + " expects zero or one argument", "pass no argument for a new array or an existing array as a checked cast")
                end
            end
            if target["name"] == "IntArray" or target["name"] == "FloatArray" or target["name"] == "ByteArray":
                expected_array_code = 13
                if target["name"] == "FloatArray":
                    expected_array_code = 14
                elif target["name"] == "ByteArray":
                    expected_array_code = 15
                end
                if len(syntax["arguments"]) == 0:
                    if target["name"] == "ByteArray":
                        call assembler.relative(output, [232], "runtime_byte_array_new")
                    else:
                        call assembler.emit(output, x86_64.mov_imm64(7, 0))
                        call assembler.emit(output, x86_64.mov_imm64(6, 0))
                        call assembler.relative(output, [232], "runtime_list_new")
                        call assembler.emit(output, x86_64.store_memory_imm32(0, 0, expected_array_code))
                    end
                    return
                end
                array_cast_ok = label_name(generator, "array_cast_ok")
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_type_code")
                call assembler.emit(output, x86_64.cmp_reg_imm8(0, expected_array_code))
                call assembler.relative(output, [15, 132], array_cast_ok)
                call assembler.emit(output, x86_64.pop(0))
                call emit_runtime_raise(generator, "TypeError: " + target["name"] + " cast requires an existing " + target["name"])
                call assembler.label(output, array_cast_ok)
                call assembler.emit(output, x86_64.pop(0))
                return
            elif target["name"] == "float_zeros":
                if infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"]) != "Int":
                    call unsupported(generator["path"], generator["lines"], syntax["arguments"][0], "float_zeros size must be an Int", "convert the size with Int(...)")
                end
                call emit_expression(generator, syntax["arguments"][0])
                zeros_size_ok = label_name(generator, "zeros_size_ok")
                call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                call assembler.relative(output, [15, 141], zeros_size_ok)
                call emit_runtime_raise(generator, "ValueError: float_zeros size cannot be negative")
                call assembler.label(output, zeros_size_ok)
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.emit(output, x86_64.xor_reg_reg(6, 6))
                call assembler.relative(output, [232], "runtime_list_new")
                call assembler.emit(output, x86_64.store_memory_imm32(0, 0, 14))
                return
            elif target["name"] == "__lsl_int_zeros":
                call emit_expression(generator, syntax["arguments"][0])
                if infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"]) == "Any":
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                end
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.emit(output, x86_64.xor_reg_reg(6, 6))
                call assembler.relative(output, [232], "runtime_list_new")
                call assembler.emit(output, x86_64.store_memory_imm32(0, 0, 13))
                return
            elif target["name"] == "__lsl_byte_zeros":
                call emit_expression(generator, syntax["arguments"][0])
                if infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"]) == "Any":
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                end
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_byte_array_zeros")
                return
            elif target["name"] == "__lsl_raster_pack" or target["name"] == "__lsl_raster_copy" or target["name"] == "__lsl_byte_copy":
                # (array, array, off, off, count): arrays stay boxed object
                # pointers, the three scalars go through the dynamic unboxer
                # (a no-op for raw Ints). The runtime type-checks and clamps.
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][3])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][4])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(8, 0))
                call assembler.emit(output, x86_64.pop(1))
                call assembler.emit(output, x86_64.pop(2))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                if target["name"] == "__lsl_raster_pack":
                    call assembler.relative(output, [232], "runtime_raster_pack")
                elif target["name"] == "__lsl_byte_copy":
                    call assembler.relative(output, [232], "runtime_byte_copy")
                else:
                    call assembler.relative(output, [232], "runtime_raster_copy")
                end
                return
            elif target["name"] == "__lsl_raster_fill":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][3])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(1, 0))
                call assembler.emit(output, x86_64.pop(2))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_raster_fill")
                return
            elif target["name"] == "float_fill":
                if infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"]) != "FloatArray" or infer_expression_type(syntax["arguments"][1], generator["types"], generator["function_returns"]) != "Float":
                    call unsupported(generator["path"], generator["lines"], syntax, "float_fill requires (FloatArray, Float)", "cast the array and convert the value with Float(...)")
                end
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.load_memory(6, 0, 8))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_float_array_fill")
                return
            elif target["name"] == "float_sum":
                if infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"]) != "FloatArray":
                    call unsupported(generator["path"], generator["lines"], syntax["arguments"][0], "float_sum requires a FloatArray", "use FloatArray(value) for a checked cast")
                end
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_float_array_sum")
                return
            elif target["name"] == "float_dot":
                if infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"]) != "FloatArray" or infer_expression_type(syntax["arguments"][1], generator["types"], generator["function_returns"]) != "FloatArray":
                    call unsupported(generator["path"], generator["lines"], syntax, "float_dot requires two FloatArrays", "use FloatArray(value) for checked casts")
                end
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                dot_lengths_ok = label_name(generator, "dot_lengths_ok")
                call assembler.emit(output, x86_64.load_memory(1, 7, 8))
                call assembler.emit(output, x86_64.load_memory(2, 6, 8))
                call assembler.emit(output, x86_64.cmp_reg_reg(1, 2))
                call assembler.relative(output, [15, 132], dot_lengths_ok)
                call emit_runtime_raise(generator, "ValueError: float_dot requires equal lengths")
                call assembler.label(output, dot_lengths_ok)
                call assembler.relative(output, [232], "runtime_float_array_dot")
                return
            elif target["name"] == "float_matmul":
                if infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"]) != "FloatArray" or infer_expression_type(syntax["arguments"][1], generator["types"], generator["function_returns"]) != "FloatArray" or infer_expression_type(syntax["arguments"][2], generator["types"], generator["function_returns"]) != "Int" or infer_expression_type(syntax["arguments"][3], generator["types"], generator["function_returns"]) != "Int" or infer_expression_type(syntax["arguments"][4], generator["types"], generator["function_returns"]) != "Int":
                    call unsupported(generator["path"], generator["lines"], syntax, "float_matmul requires (FloatArray, FloatArray, Int, Int, Int)", "pass A, B, m, k, n")
                end
                for argument in syntax["arguments"]:
                    call emit_expression(generator, argument)
                    call assembler.emit(output, x86_64.push(0))
                end
                call assembler.emit(output, x86_64.pop(8))
                call assembler.emit(output, x86_64.pop(1))
                call assembler.emit(output, x86_64.pop(2))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                matmul_shape_error = label_name(generator, "matmul_shape_error")
                matmul_shape_ok = label_name(generator, "matmul_shape_ok")
                call assembler.emit(output, x86_64.cmp_reg_imm8(2, 0))
                call assembler.relative(output, [15, 140], matmul_shape_error)
                call assembler.emit(output, x86_64.cmp_reg_imm8(1, 0))
                call assembler.relative(output, [15, 140], matmul_shape_error)
                call assembler.emit(output, x86_64.cmp_reg_imm8(8, 0))
                call assembler.relative(output, [15, 140], matmul_shape_error)
                call assembler.emit(output, x86_64.move_reg_reg(9, 2))
                call assembler.emit(output, x86_64.imul_reg_reg(9, 1))
                call assembler.emit(output, x86_64.load_memory(10, 7, 8))
                call assembler.emit(output, x86_64.cmp_reg_reg(9, 10))
                call assembler.relative(output, [15, 133], matmul_shape_error)
                call assembler.emit(output, x86_64.move_reg_reg(9, 1))
                call assembler.emit(output, x86_64.imul_reg_reg(9, 8))
                call assembler.emit(output, x86_64.load_memory(10, 6, 8))
                call assembler.emit(output, x86_64.cmp_reg_reg(9, 10))
                call assembler.relative(output, [15, 132], matmul_shape_ok)
                call assembler.label(output, matmul_shape_error)
                call emit_runtime_raise(generator, "ValueError: float_matmul shape does not match array lengths")
                call assembler.label(output, matmul_shape_ok)
                call assembler.relative(output, [232], "runtime_float_array_matmul")
                return
            elif target["name"] == "float_axpy":
                if infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"]) != "Float" or infer_expression_type(syntax["arguments"][1], generator["types"], generator["function_returns"]) != "FloatArray" or infer_expression_type(syntax["arguments"][2], generator["types"], generator["function_returns"]) != "FloatArray":
                    call unsupported(generator["path"], generator["lines"], syntax, "float_axpy requires (Float, FloatArray, FloatArray)", "convert alpha with Float(...) and cast arrays with FloatArray(...)")
                end
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.load_memory(0, 0, 8))
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.move_reg_reg(2, 0))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                axpy_lengths_ok = label_name(generator, "axpy_lengths_ok")
                call assembler.emit(output, x86_64.load_memory(1, 6, 8))
                call assembler.emit(output, x86_64.load_memory(8, 2, 8))
                call assembler.emit(output, x86_64.cmp_reg_reg(1, 8))
                call assembler.relative(output, [15, 132], axpy_lengths_ok)
                call emit_runtime_raise(generator, "ValueError: float_axpy requires equal lengths")
                call assembler.label(output, axpy_lengths_ok)
                call assembler.relative(output, [232], "runtime_float_array_axpy")
                return
            elif target["name"] == "Bool":
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
            elif target["name"] == "Dictionary":
                dictionary_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_dictionary"}, "arguments": syntax["arguments"]}
                call emit_expression(generator, dictionary_call)
                return
            elif target["name"] == "sum":
                sum_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_sum"}, "arguments": syntax["arguments"]}
                call emit_expression(generator, sum_call)
                if generator["path"].find("compiler/pure/") < 0:
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_box_dynamic_int")
                end
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
            elif target["name"] == "__lsl_float_bits":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.load_memory(0, 0, 8))
                return
            elif target["name"] == "__lsl_float_from_bits":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_float_new")
                return
            elif target["name"] == "__lsl_raw_equal":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_equal_any")
                return
            elif target["name"] == "__lsl_is_heap":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_is_heap_object")
                return
            elif target["name"] == "__lsl_test_small_tables":
                call assembler.relative(output, [232], "runtime_test_small_tables")
                return
            elif target["name"] == "__lsl_test_fd_fault":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_test_fd_fault")
                return
            elif target["name"] == "__lsl_object_table_mask":
                call assembler.relative(output, [232], "runtime_object_table_mask")
                return
            elif target["name"] == "__lsl_intern_table_mask":
                call assembler.relative(output, [232], "runtime_intern_table_mask")
                return
            elif target["name"] == "__lsl_address":
                # Test/audit intrinsic: expose object bits as a statically typed
                # Int to prove that every dynamic boundary boxes the collision.
                call emit_expression(generator, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_raw_int":
                # Identity that types the value as Int, so a known-raw-Int Any
                # takes the static Int path without the is_heap/type_code probe
                # in Int() (which errors on raw 0, whose type code reads as None).
                call emit_expression(generator, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_typed_int":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                return
            elif target["name"] == "__lsl_parse_literal_int":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_parse_literal_int")
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
            elif target["name"] == "__lsl_box_int":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_box_int")
                return
            elif target["name"] == "__lsl_box_function":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.mov_imm64(6, -1))
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_box_function")
                return
            elif target["name"] == "__lsl_box_none":
                call assembler.relative(output, [232], "runtime_box_none")
                return
            elif target["name"] == "__lsl_unbox_bool":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_bool")
                return
            elif target["name"] == "__lsl_unbox_int":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_int")
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
                    format_float_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_format_float"}, "arguments": syntax["arguments"]}
                    call emit_expression(generator, format_float_call)
                elif argument_type == "Int":
                    call emit_expression(generator, syntax["arguments"][0])
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_int_to_string")
                elif argument_type == "Bool":
                    # Static Bool is a raw 0/1, which __lsl_str_value would
                    # misread as Int; select the String literal directly.
                    bool_false = label_name(generator, "string_bool_false")
                    bool_done = label_name(generator, "string_bool_done")
                    call emit_expression(generator, syntax["arguments"][0])
                    call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                    call assembler.relative(output, [15, 132], bool_false)
                    call emit_string_pointer(generator, "True")
                    call assembler.relative(output, [233], bool_done)
                    call assembler.label(output, bool_false)
                    call emit_string_pointer(generator, "False")
                    call assembler.label(output, bool_done)
                elif argument_type == "None":
                    call emit_string_pointer(generator, "None")
                else:
                    str_value_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_str_value"}, "arguments": syntax["arguments"]}
                    call emit_expression(generator, str_value_call)
                end
                return
            elif target["name"] == "chr":
                call emit_expression(generator, syntax["arguments"][0])
                if infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"]) == "Any":
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                end
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
                if infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"]) == "Any":
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                end
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
                call emit_pending_error(generator)
                return
            elif target["name"] == "__lsl_getenv":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_getenv")
                return
            elif target["name"] == "run" or target["name"] == "__lsl_run" or target["name"] == "capture" or target["name"] == "__lsl_capture" or target["name"] == "capture_stream" or target["name"] == "capture_input":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.push(0))
                if target["name"] == "capture_stream":
                    call emit_expression(generator, syntax["arguments"][2])
                    call emit_collection_box(generator, syntax["arguments"][2])
                    call assembler.emit(output, x86_64.move_reg_reg(2, 0))
                    call assembler.emit(output, x86_64.xor_reg_reg(1, 1))
                elif target["name"] == "capture_input":
                    call emit_expression(generator, syntax["arguments"][2])
                    call assembler.emit(output, x86_64.move_reg_reg(1, 0))
                    call assembler.emit(output, x86_64.xor_reg_reg(2, 2))
                else:
                    call assembler.emit(output, x86_64.xor_reg_reg(2, 2))
                    call assembler.emit(output, x86_64.xor_reg_reg(1, 1))
                end
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                if target["name"] == "run" or target["name"] == "__lsl_run":
                    call assembler.relative(output, [232], "runtime_run")
                else:
                    call assembler.relative(output, [232], "runtime_capture")
                    call emit_pending_error(generator)
                end
                return
            elif target["name"] == "native_open":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_native_open")
                return
            elif target["name"] == "native_size":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_native_size")
                return
            elif target["name"] == "native_u64" or target["name"] == "native_function" or target["name"] == "native_call":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                if target["name"] == "native_u64" or target["name"] == "native_function":
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                end
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                if target["name"] == "native_u64":
                    call assembler.relative(output, [232], "runtime_native_u64")
                elif target["name"] == "native_function":
                    call assembler.relative(output, [232], "runtime_native_function")
                else:
                    call assembler.relative(output, [232], "runtime_native_call")
                    call emit_pending_error(generator)
                end
                return
            elif target["name"] == "native_name_equal":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.move_reg_reg(2, 0))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_native_name_equal")
                return
            elif target["name"] == "native_close":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_native_close")
                return
            elif target["name"] == "__lsl_fd_open":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_fd_open")
                return
            elif target["name"] == "__lsl_fd_socket":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_fd_socket")
                return
            elif target["name"] == "__lsl_fd_read" or target["name"] == "__lsl_fd_write" or target["name"] == "__lsl_fd_connect" or target["name"] == "__lsl_fd_ioctl":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(2, 0))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                if target["name"] == "__lsl_fd_read":
                    call assembler.relative(output, [232], "runtime_fd_read")
                elif target["name"] == "__lsl_fd_connect":
                    call assembler.relative(output, [232], "runtime_fd_connect")
                elif target["name"] == "__lsl_fd_ioctl":
                    call assembler.relative(output, [232], "runtime_fd_ioctl")
                else:
                    call assembler.relative(output, [232], "runtime_fd_write")
                end
                return
            elif target["name"] == "__lsl_data_address":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_data_address")
                return
            elif target["name"] == "__lsl_fd_mmap":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(2, 0))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_fd_mmap")
                return
            elif target["name"] == "__lsl_mem_pack":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][3])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][4])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(8, 0))
                call assembler.emit(output, x86_64.pop(1))
                call assembler.emit(output, x86_64.pop(2))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_mem_pack")
                return
            elif target["name"] == "__lsl_mem_unpack":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][3])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(1, 0))
                call assembler.emit(output, x86_64.pop(2))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_mem_unpack")
                return
            elif target["name"] == "__lsl_text_byte":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_text_byte")
                return
            elif target["name"] == "__lsl_text_from_bytes":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(2, 0))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_text_from_bytes")
                return
            elif target["name"] == "__lsl_syscall":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][3])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][4])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(8, 0))
                call assembler.emit(output, x86_64.pop(1))
                call assembler.emit(output, x86_64.pop(2))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_syscall")
                return
            elif target["name"] == "__lsl_fd_seek":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_fd_seek")
                return
            elif target["name"] == "__lsl_fd_close":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_fd_close")
                return
            elif target["name"] == "capture_status":
                call assembler.relative(output, [232], "runtime_capture_status")
                return
            elif target["name"] == "capture_stderr":
                call assembler.relative(output, [232], "runtime_capture_stderr")
                return
            elif target["name"] == "input":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_input")
                call emit_pending_error(generator)
                return
            elif target["name"] == "clock" or target["name"] == "__lsl_wall_time":
                if target["name"] == "clock":
                    call assembler.relative(output, [232], "runtime_clock")
                else:
                    call assembler.relative(output, [232], "runtime_wall_time")
                end
                return
            elif target["name"] == "__lsl_sleep":
                call emit_float_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_sleep")
                call emit_pending_error(generator)
                return
            elif target["name"] == "__lsl_isatty":
                call emit_expression(generator, syntax["arguments"][0])
                if infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"]) == "Any":
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                end
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_isatty")
                return
            elif target["name"] == "__lsl_stdin_eof":
                call assembler.relative(output, [232], "runtime_stdin_eof")
                return
            elif target["name"] == "readfile" or target["name"] == "readbytes":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                if target["name"] == "readbytes":
                    call assembler.relative(output, [232], "runtime_readbytes")
                else:
                    call assembler.relative(output, [232], "runtime_readfile")
                end
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
                if value_type == "Any":
                    call emit_expression(generator, syntax["arguments"][0])
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "function___lsl_type_name")
                    call emit_pending_error(generator)
                    return
                end
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
                minmax_left_type = infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"])
                minmax_right_type = infer_expression_type(syntax["arguments"][1], generator["types"], generator["function_returns"])
                minmax_dynamic = minmax_left_type == "Float" or minmax_right_type == "Float" or minmax_left_type == "Any" or minmax_right_type == "Any"
                call emit_expression(generator, syntax["arguments"][0])
                if minmax_dynamic:
                    call emit_dynamic_boundary_box(generator, syntax["arguments"][0])
                end
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                if minmax_dynamic:
                    call emit_dynamic_boundary_box(generator, syntax["arguments"][1])
                end
                done_label = label_name(generator, "minmax_done")
                if minmax_dynamic:
                    # Dispatch Int/Float; keep the original boxed value.
                    call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                    call assembler.emit(output, x86_64.pop(0))
                    call assembler.emit(output, x86_64.push(0))
                    call assembler.emit(output, x86_64.push(6))
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_compare_any")
                    call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                    call assembler.emit(output, x86_64.pop(1))
                    call assembler.emit(output, x86_64.pop(0))
                    if target["name"] == "min":
                        call assembler.relative(output, [15, 142], done_label)
                    else:
                        call assembler.relative(output, [15, 141], done_label)
                    end
                    call assembler.emit(output, x86_64.move_reg_reg(0, 1))
                    call assembler.label(output, done_label)
                    return
                end
                call assembler.emit(output, x86_64.move_reg_reg(1, 0))
                call assembler.emit(output, x86_64.pop(0))
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
                call emit_static_write(generator, "Lux Simple Lang (LSL) 0.6" + chr(10) + "functions: print printl input for loop safe if elif else try class ctype function type del len help" + chr(10) + "types: Bool Int Float String List Tuple RealArray IntArray FloatArray ByteArray Dictionary" + chr(10) + "modules: os time json process config ai tensor cuda native" + chr(10) + "docs: see README.md and docs/" + chr(10))
                call assembler.emit(output, x86_64.mov_imm64(0, 0))
                return
            elif target["name"] == "abs":
                abs_arg_type = infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"])
                call emit_expression(generator, syntax["arguments"][0])
                if abs_arg_type == "Float":
                    # Clear the IEEE-754 sign bit of the boxed double and rebox.
                    call assembler.emit(output, x86_64.load_memory(7, 0, 8))
                    call assembler.emit(output, x86_64.mov_imm64(1, 9223372036854775807))
                    call assembler.emit(output, x86_64.and_reg_reg(7, 1))
                    call assembler.relative(output, [232], "runtime_float_new")
                elif abs_arg_type == "Any":
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], dynamic_numeric_runtime(generator, "runtime_abs_any"))
                else:
                    done_label = label_name(generator, "abs_done")
                    call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                    call assembler.relative(output, [15, 141], done_label)
                    call assembler.emit(output, x86_64.neg_reg(0))
                    call assembler.label(output, done_label)
                end
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
            method_arity = {"strip": 0, "lstrip": 0, "rstrip": 0, "lower": 0, "upper": 0, "title": 0, "capitalize": 0, "sort": 0, "reverse": 0, "copy": 0, "keys": 0, "values": 0, "items": 0, "clear": 0, "append": 1, "startswith": 1, "endswith": 1, "find": 1, "count": 1, "split": 1, "join": 1, "extend": 1, "remove": 1, "index": 1, "update": 1, "replace": 2, "insert": 2}
            if target["name"] in method_arity and not receiver_type.startswith("Class:") and not receiver_type.startswith("Instance:"):
                expected_method = method_arity[target["name"]]
                if len(syntax["arguments"]) != expected_method:
                    call unsupported(generator["path"], generator["lines"], syntax, "method " + target["name"] + " expects " + String(expected_method) + " argument(s), got " + String(len(syntax["arguments"])), "pass exactly " + String(expected_method) + " argument(s)")
                end
            elif target["name"] == "pop":
                pop_arity_valid = False
                if receiver_type == "Dictionary":
                    pop_arity_valid = len(syntax["arguments"]) == 1 or len(syntax["arguments"]) == 2
                else:
                    pop_arity_valid = len(syntax["arguments"]) == 0 or len(syntax["arguments"]) == 1
                end
                if not pop_arity_valid:
                    call unsupported(generator["path"], generator["lines"], syntax, "invalid pop argument count", "use list.pop([index]) or dictionary.pop(key[, default])")
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
            elif (receiver_type == "IntArray" or receiver_type == "FloatArray" or receiver_type == "ByteArray") and target["name"] != "append" and target["name"] != "clear":
                call unsupported(generator["path"], generator["lines"], syntax, receiver_type + " method is not implemented: " + target["name"], "use append, clear, indexed access, indexed assignment, len, or iteration")
            elif target["name"] == "append":
                if receiver_type == "Tuple" or receiver_type == "RealArray":
                    call unsupported(generator["path"], generator["lines"], syntax, "fixed collection does not support append", "convert it with List(value) before appending")
                end
                if receiver_type == "IntArray":
                    if infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"]) != "Int":
                        call unsupported(generator["path"], generator["lines"], syntax["arguments"][0], "IntArray append requires an Int", "convert the value with Int(...) before appending")
                    end
                elif receiver_type == "FloatArray":
                    if infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"]) != "Float":
                        call unsupported(generator["path"], generator["lines"], syntax["arguments"][0], "FloatArray append requires a Float", "convert the value with Float(...) before appending")
                    end
                elif receiver_type == "ByteArray":
                    if infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"]) != "Int":
                        call unsupported(generator["path"], generator["lines"], syntax["arguments"][0], "ByteArray append requires an Int", "convert the value with Int(...) before appending")
                    end
                end
                call emit_expression(generator, target["target"])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][0])
                if receiver_type == "FloatArray":
                    call assembler.emit(output, x86_64.load_memory(0, 0, 8))
                elif receiver_type == "ByteArray":
                    byte_append_ok = label_name(generator, "byte_append_ok")
                    byte_append_error = label_name(generator, "byte_append_error")
                    call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                    call assembler.relative(output, [15, 140], byte_append_error)
                    call assembler.emit(output, x86_64.cmp_reg_imm32(0, 255))
                    call assembler.relative(output, [15, 142], byte_append_ok)
                    call assembler.label(output, byte_append_error)
                    call assembler.emit(output, x86_64.pop(7))
                    call emit_runtime_raise(generator, "ValueError: ByteArray value is outside 0..255")
                    call assembler.label(output, byte_append_ok)
                elif receiver_type != "IntArray":
                    call emit_collection_box(generator, syntax["arguments"][0])
                end
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                if receiver_type == "ByteArray":
                    call assembler.relative(output, [232], "runtime_byte_array_append")
                else:
                    call assembler.relative(output, [232], "runtime_list_append")
                end
                return
            elif target["name"] == "clear":
                if receiver_type == "Tuple" or receiver_type == "RealArray":
                    call unsupported(generator["path"], generator["lines"], syntax, "fixed collection does not support clear", "convert it with List(value) before changing its length")
                elif receiver_type == "Dictionary":
                    clear_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_dict_clear"}, "arguments": [target["target"]]}
                    call emit_expression(generator, clear_call)
                else:
                    call emit_expression(generator, target["target"])
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_list_clear")
                end
                return
            elif target["name"] == "pop":
                if receiver_type == "Tuple" or receiver_type == "RealArray":
                    call unsupported(generator["path"], generator["lines"], syntax, "fixed collection does not support pop", "convert it with List(value) before changing its length")
                end
                pop_target = "__lsl_pop"
                pop_arguments = [target["target"]]
                if receiver_type == "Dictionary":
                    if len(syntax["arguments"]) == 1:
                        pop_target = "__lsl_dict_pop"
                    else:
                        pop_target = "__lsl_dict_pop_default"
                    end
                    pop_arguments.extend(syntax["arguments"])
                elif len(syntax["arguments"]) == 1:
                    pop_target = "__lsl_pop_at"
                    pop_arguments.extend(syntax["arguments"])
                end
                pop_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": pop_target}, "arguments": pop_arguments}
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
                if receiver_type == "List" or receiver_type == "Tuple" or receiver_type == "RealArray" or receiver_type == "IntArray" or receiver_type == "FloatArray":
                    if target["name"] == "index":
                        method_target = "__lsl_list_index"
                    elif target["name"] == "count":
                        method_target = "__lsl_list_count"
                    end
                elif receiver_type == "String" and target["name"] == "index":
                    method_target = "__lsl_string_index"
                elif receiver_type == "Dictionary" and target["name"] == "copy":
                    method_target = "__lsl_dict_copy"
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
                        call emit_collection_box(generator, argument)
                        call assembler.emit(output, x86_64.push(0))
                    end
                    method_registers = [7, 6, 2, 1, 8, 9]
                    method_index = len(combined_arguments) - 1
                    while method_index >= 0:
                        call assembler.emit(output, x86_64.pop(__lsl_typed_int(method_registers[method_index])))
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
                    call emit_collection_box(generator, arguments[index])
                    call assembler.emit(output, x86_64.push(0))
                    index -= 1
                end
                call assembler.emit(output, x86_64.load_memory(0, 4, len(arguments) * 8))
                call assembler.emit(output, x86_64.push(0))
                argument_registers = [7, 6, 2, 1, 8, 9]
                total_arguments = len(arguments) + 1
                register_count = min(total_arguments, len(argument_registers))
                index = 0
                while index < register_count:
                    call assembler.emit(output, x86_64.pop(__lsl_typed_int(argument_registers[index])))
                    index += 1
                end
                call assembler.relative(output, [232], "function_" + initializer_name)
                stack_count = total_arguments - register_count
                if stack_count > 0:
                    call assembler.emit(output, x86_64.add_reg_imm32(4, stack_count * 8))
                end
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
            expected_parameter_type = "Any"
            if not indirect_call:
                expected_parameter_type = generator["function_parameters"][target["name"]][index]
            end
            if expected_parameter_type == "Any":
                call emit_collection_box(generator, arguments[index])
            end
            call assembler.emit(output, x86_64.push(0))
            index -= 1
        end
        argument_registers = [7, 6, 2, 1, 8, 9]
        register_count = min(len(arguments), len(argument_registers))
        index = 0
        while index < register_count:
            call assembler.emit(output, x86_64.pop(__lsl_typed_int(argument_registers[index])))
            index += 1
        end
        if indirect_call:
            if target["name"] in generator["variables"]:
                call assembler.emit(output, x86_64.load_stack(0, generator["variables"][target["name"]]))
            else:
                call assembler.emit(output, x86_64.load_memory(0, 12, generator["global_variables"][target["name"]]))
            end
            # Callable classification uses rdi and may clobber caller-saved
            # registers, so preserve the already loaded user arguments.
            index = 0
            while index < register_count:
                call assembler.emit(output, x86_64.push(__lsl_typed_int(argument_registers[index])))
                index += 1
            end
            call assembler.emit(output, x86_64.move_reg_reg(7, 0))
            call assembler.relative(output, [232], "runtime_unbox_dynamic_function")
            call assembler.emit(output, x86_64.move_reg_reg(11, 0))
            index = register_count - 1
            while index >= 0:
                call assembler.emit(output, x86_64.pop(__lsl_typed_int(argument_registers[index])))
                index -= 1
            end
            call assembler.emit(output, x86_64.call_reg(11))
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
        if indirect_call and generator["path"].find("compiler/pure/") < 0:
            call assembler.emit(output, x86_64.push(0))
            if target["name"] in generator["variables"]:
                call assembler.emit(output, x86_64.load_stack(7, generator["variables"][target["name"]]))
            else:
                call assembler.emit(output, x86_64.load_memory(7, 12, generator["global_variables"][target["name"]]))
            end
            call assembler.relative(output, [232], "runtime_function_return_tag")
            call assembler.emit(output, x86_64.move_reg_reg(10, 0))
            call assembler.emit(output, x86_64.pop(0))
            callback_return_done = label_name(generator, "callback_return_done")
            callback_return_bool = label_name(generator, "callback_return_bool")
            callback_return_none = label_name(generator, "callback_return_none")
            callback_return_function = label_name(generator, "callback_return_function")
            call assembler.emit(output, x86_64.cmp_reg_imm8(10, 0))
            call assembler.relative(output, [15, 132], callback_return_bool)
            call assembler.emit(output, x86_64.cmp_reg_imm8(10, 4))
            call assembler.relative(output, [15, 132], callback_return_bool)
            call assembler.emit(output, x86_64.cmp_reg_imm8(10, 5))
            call assembler.relative(output, [15, 132], callback_return_none)
            call assembler.emit(output, x86_64.cmp_reg_imm8(10, 10))
            call assembler.relative(output, [15, 132], callback_return_function)
            call assembler.relative(output, [233], callback_return_done)
            call assembler.label(output, callback_return_bool)
            # Tag 0 means Int; tag 4 means Bool.
            call assembler.emit(output, x86_64.cmp_reg_imm8(10, 4))
            callback_box_bool = label_name(generator, "callback_box_bool")
            call assembler.relative(output, [15, 132], callback_box_bool)
            call assembler.emit(output, x86_64.move_reg_reg(7, 0))
            call assembler.relative(output, [232], "runtime_box_int")
            call assembler.relative(output, [233], callback_return_done)
            call assembler.label(output, callback_box_bool)
            call assembler.emit(output, x86_64.move_reg_reg(7, 0))
            call assembler.relative(output, [232], "runtime_box_bool")
            call assembler.relative(output, [233], callback_return_done)
            call assembler.label(output, callback_return_none)
            call assembler.relative(output, [232], "runtime_box_none")
            call assembler.relative(output, [233], callback_return_done)
            call assembler.label(output, callback_return_function)
            call assembler.emit(output, x86_64.mov_imm64(6, -1))
            call assembler.emit(output, x86_64.move_reg_reg(7, 0))
            call assembler.relative(output, [232], "runtime_box_dynamic_function")
            call assembler.label(output, callback_return_done)
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
        if operator == "==" or operator == "!=" or operator == "is" or operator == "is not":
            left_equal_type = infer_expression_type(left, generator["types"], generator["function_returns"])
            right_equal_type = infer_expression_type(right, generator["types"], generator["function_returns"])
            use_deep = (operator == "==" or operator == "!=") and maybe_collection(left_equal_type) and maybe_collection(right_equal_type)
            if direct_scalar_equality(left_equal_type, right_equal_type):
                right_constant = constant_int_expression(right)
                if right_constant[0] and x86_64.fits_signed32(right_constant[1]):
                    call emit_expression(generator, left)
                    call assembler.emit(output, x86_64.cmp_reg_imm32(0, right_constant[1]))
                elif is_int_leaf(generator, right):
                    call emit_expression(generator, left)
                    call emit_int_leaf(generator, right, 6)
                    call assembler.emit(output, x86_64.cmp_reg_reg(0, 6))
                else:
                    call emit_expression(generator, left)
                    call assembler.emit(output, x86_64.push(0))
                    call emit_expression(generator, right)
                    call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                    call assembler.emit(output, x86_64.pop(0))
                    call assembler.emit(output, x86_64.cmp_reg_reg(0, 6))
                end
                call assembler.emit(output, x86_64.set_condition(opcode))
            elif use_deep:
                # Deep equality for collections (recursive, element-wise). Scalar
                # pairs stay on the runtime_equal_any fast path below.
                equal_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_equal"}, "arguments": [left, right]}
                call emit_expression(generator, equal_call)
                if operator == "!=":
                    call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                    call assembler.emit(output, x86_64.set_condition(148))
                end
            else:
                call emit_expression(generator, left)
                call emit_dynamic_boundary_box(generator, left)
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, right)
                call emit_dynamic_boundary_box(generator, right)
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_equal_any")
                if operator == "!=" or operator == "is not":
                    call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                    call assembler.emit(output, x86_64.set_condition(148))
                end
            end
        elif left_type == "Any" or right_type == "Any":
            # Operand may be a boxed Float at runtime; dispatch tagged Int/Float.
            call emit_expression(generator, left)
            call emit_dynamic_boundary_box(generator, left)
            call assembler.emit(output, x86_64.push(0))
            call emit_expression(generator, right)
            call emit_dynamic_boundary_box(generator, right)
            call assembler.emit(output, x86_64.move_reg_reg(6, 0))
            call assembler.emit(output, x86_64.pop(7))
            call assembler.relative(output, [232], "runtime_compare_any")
            call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
            call assembler.emit(output, x86_64.set_condition(opcode))
        else:
            # Ordered comparison compiles directly against a constant when it
            # fits x86-64's sign-extended imm32 form; otherwise leaf operands
            # still avoid a stack spill.
            right_constant = constant_int_expression(right)
            if right_constant[0] and x86_64.fits_signed32(right_constant[1]):
                call emit_expression(generator, left)
                call assembler.emit(output, x86_64.cmp_reg_imm32(0, right_constant[1]))
                call assembler.emit(output, x86_64.set_condition(opcode))
                return
            elif is_int_leaf(generator, right):
                call emit_expression(generator, left)
                call emit_int_leaf(generator, right, 6)
            elif is_int_leaf(generator, left):
                call emit_expression(generator, right)
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call emit_int_leaf(generator, left, 0)
            else:
                call emit_expression(generator, left)
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, right)
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(0))
            end
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
        if value_type == "List" or value_type == "Tuple" or value_type == "RealArray" or value_type == "IntArray" or value_type == "FloatArray" or value_type == "ByteArray" or value_type == "Dictionary" or value_type == "Any":
            str_call = {"kind": "call", "line": expression["line"], "column": expression["column"], "end_column": expression["end_column"], "target": {"kind": "name", "name": "__lsl_str_value"}, "arguments": [expression]}
            call emit_expression(generator, str_call)
            call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
            call assembler.relative(generator["builder"], [232], "runtime_print_string")
            return
        elif value_type == "Float":
            format_float_call = {"kind": "call", "line": expression["line"], "column": expression["column"], "end_column": expression["end_column"], "target": {"kind": "name", "name": "__lsl_format_float"}, "arguments": [expression]}
            call emit_expression(generator, format_float_call)
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

function emit_statements(generator, statements, break_label, continue_label, return_label):
    for statement in statements:
        kind = statement["kind"]
        if kind == "assign":
            target = statement["target"]
            if target["kind"] == "name":
                if statement["operator"] == "=":
                    call emit_expression(generator, statement["value"])
                    if infer_expression_type(statement["value"], generator["types"], generator["function_returns"]) == "Function":
                        call emit_collection_box(generator, statement["value"])
                    end
                else:
                    operator = statement["operator"][0:len(statement["operator"]) - 1]
                    combined = {"kind": "binary", "line": statement["line"], "column": statement["column"], "end_column": statement["end_column"], "operator": operator, "left": target, "right": statement["value"]}
                    call emit_expression(generator, combined)
                end
                call assembler.emit(generator["builder"], x86_64.store_stack(generator["variables"][target["name"]], 0))
            elif target["kind"] == "index":
                target_type = infer_expression_type(target["target"], generator["types"], generator["function_returns"])
                call emit_expression(generator, target["target"])
                call assembler.emit(generator["builder"], x86_64.push(0))
                call emit_expression(generator, target["index"])
                if target_type == "Dictionary":
                    call emit_dictionary_key_box(generator, target["index"])
                elif infer_expression_type(target["index"], generator["types"], generator["function_returns"]) == "Any":
                    call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                    call assembler.relative(generator["builder"], [232], "runtime_unbox_dynamic_int")
                end
                call assembler.emit(generator["builder"], x86_64.push(0))
                if statement["operator"] == "=":
                    assigned_type = infer_expression_type(statement["value"], generator["types"], generator["function_returns"])
                    if target_type == "IntArray" and assigned_type != "Int":
                        call unsupported(generator["path"], generator["lines"], statement["value"], "IntArray assignment requires an Int", "convert the value with Int(...) before assignment")
                    elif target_type == "FloatArray" and assigned_type != "Float":
                        call unsupported(generator["path"], generator["lines"], statement["value"], "FloatArray assignment requires a Float", "convert the value with Float(...) before assignment")
                    elif target_type == "ByteArray" and assigned_type != "Int":
                        call unsupported(generator["path"], generator["lines"], statement["value"], "ByteArray assignment requires an Int", "convert the value with Int(...) before assignment")
                    end
                    call emit_expression(generator, statement["value"])
                    if target_type == "FloatArray":
                        call assembler.emit(generator["builder"], x86_64.load_memory(0, 0, 8))
                    elif target_type != "IntArray" and target_type != "ByteArray":
                        call emit_collection_box(generator, statement["value"])
                    end
                else:
                    operator = statement["operator"][0:len(statement["operator"]) - 1]
                    combined = {"kind": "binary", "line": statement["line"], "column": statement["column"], "end_column": statement["end_column"], "operator": operator, "left": target, "right": statement["value"]}
                    combined_type = infer_expression_type(combined, generator["types"], generator["function_returns"])
                    if target_type == "IntArray" and combined_type != "Int":
                        call unsupported(generator["path"], generator["lines"], statement["value"], "IntArray assignment requires an Int result", "use integer arithmetic for augmented assignment")
                    elif target_type == "FloatArray" and combined_type != "Float":
                        call unsupported(generator["path"], generator["lines"], statement["value"], "FloatArray assignment requires a Float result", "use Float arithmetic for augmented assignment")
                    elif target_type == "ByteArray" and combined_type != "Int":
                        call unsupported(generator["path"], generator["lines"], statement["value"], "ByteArray assignment requires an Int result", "use integer arithmetic for augmented assignment")
                    end
                    call emit_expression(generator, combined)
                    if target_type == "FloatArray":
                        call assembler.emit(generator["builder"], x86_64.load_memory(0, 0, 8))
                    elif target_type != "IntArray" and target_type != "ByteArray":
                        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                        call assembler.relative(generator["builder"], [232], "runtime_box_dynamic_int")
                    end
                end
                if target_type == "ByteArray":
                    byte_set_ok = label_name(generator, "byte_set_ok")
                    byte_set_error = label_name(generator, "byte_set_error")
                    call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(0, 0))
                    call assembler.relative(generator["builder"], [15, 140], byte_set_error)
                    call assembler.emit(generator["builder"], x86_64.cmp_reg_imm32(0, 255))
                    call assembler.relative(generator["builder"], [15, 142], byte_set_ok)
                    call assembler.label(generator["builder"], byte_set_error)
                    call assembler.emit(generator["builder"], x86_64.pop(6))
                    call assembler.emit(generator["builder"], x86_64.pop(7))
                    call emit_runtime_raise(generator, "ValueError: ByteArray value is outside 0..255")
                    call assembler.label(generator["builder"], byte_set_ok)
                end
                call assembler.emit(generator["builder"], x86_64.move_reg_reg(2, 0))
                call assembler.emit(generator["builder"], x86_64.pop(6))
                call assembler.emit(generator["builder"], x86_64.pop(7))
                if target_type == "Tuple":
                    call unsupported(generator["path"], generator["lines"], statement, "Tuple items are immutable", "use List or RealArray for indexed mutation")
                elif target_type == "Dictionary":
                    call assembler.relative(generator["builder"], [232], "runtime_dict_set")
                elif target_type == "List" or target_type == "RealArray" or target_type == "IntArray" or target_type == "FloatArray" or target_type == "ByteArray":
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
                    call emit_bounds_check(generator, statement, target_type)
                    call assembler.emit(generator["builder"], x86_64.pop(2))
                    if target_type == "ByteArray":
                        call assembler.relative(generator["builder"], [232], "runtime_byte_array_set")
                    else:
                        call assembler.relative(generator["builder"], [232], "runtime_list_set")
                    end
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
                    call emit_collection_box(generator, statement["value"])
                else:
                    operator = statement["operator"][0:len(statement["operator"]) - 1]
                    combined = {"kind": "binary", "line": statement["line"], "column": statement["column"], "end_column": statement["end_column"], "operator": operator, "left": target, "right": statement["value"]}
                    call emit_expression(generator, combined)
                    call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                    call assembler.relative(generator["builder"], [232], "runtime_box_dynamic_int")
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
            index = 0
            while index < len(expressions):
                if index > 0:
                    call emit_static_write(generator, " ")
                end
                call emit_print_value(generator, expressions[index])
                index += 1
            end
            call emit_static_write(generator, chr(10))
        elif kind == "expression":
            call emit_expression(generator, statement["expression"])
        elif kind == "if":
            selected = constant_if_body(statement)
            if selected[0]:
                call emit_statements(generator, selected[1], break_label, continue_label, return_label)
            else:
                end_label = label_name(generator, "if_end")
                branch_index = 0
                while branch_index < len(statement["branches"]):
                    next_label = label_name(generator, "if_next")
                    branch = statement["branches"][branch_index]
                    if not emit_branch_if_false(generator, branch[0], next_label):
                        call emit_condition(generator, branch[0])
                        call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(0, 0))
                        call assembler.relative(generator["builder"], [15, 132], next_label)
                    end
                    call emit_statements(generator, branch[1], break_label, continue_label, return_label)
                    call assembler.relative(generator["builder"], [233], end_label)
                    call assembler.label(generator["builder"], next_label)
                    branch_index += 1
                end
                call emit_statements(generator, statement["otherwise"], break_label, continue_label, return_label)
                call assembler.label(generator["builder"], end_label)
            end
        elif kind == "while" or kind == "loop":
            constant_condition = [False, False]
            if kind == "while":
                constant_condition = constant_truth_expression(statement["condition"])
            end
            if kind == "while" and constant_condition[0] and not constant_condition[1]:
                continue
            end
            start_label = label_name(generator, "loop_start")
            end_label = label_name(generator, "loop_end")
            call assembler.label(generator["builder"], start_label)
            if kind == "while" and not constant_condition[0]:
                if not emit_branch_if_false(generator, statement["condition"], end_label):
                    call emit_condition(generator, statement["condition"])
                    call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(0, 0))
                    call assembler.relative(generator["builder"], [15, 132], end_label)
                end
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
                if iterable_type == "ByteArray":
                    call assembler.relative(generator["builder"], [232], "runtime_byte_array_get")
                elif iterable_type == "List" or iterable_type == "Tuple" or iterable_type == "RealArray" or iterable_type == "IntArray" or iterable_type == "FloatArray":
                    call assembler.relative(generator["builder"], [232], "runtime_list_get")
                    if iterable_type == "FloatArray":
                        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                        call assembler.relative(generator["builder"], [232], "runtime_float_new")
                    end
                else:
                    call assembler.relative(generator["builder"], [232], "runtime_get")
                end
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
                start_expression = {"kind": "literal", "literal_kind": "number", "value": "0", "integer_value": 0, "line": statement["line"], "column": statement["column"], "end_column": statement["end_column"]}
                stop_expression = arguments[0]
            else:
                start_expression = arguments[0]
                stop_expression = arguments[1]
            end
            slot = generator["variables"][statement["name"]]
            stop_slot = generator["variables"][statement["iterator_name"]]
            step_slot = generator["variables"][statement["index_name"]]
            call emit_expression(generator, start_expression)
            if infer_expression_type(start_expression, generator["types"], generator["function_returns"]) == "Any":
                call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                call assembler.relative(generator["builder"], [232], "runtime_unbox_dynamic_int")
            end
            call assembler.emit(generator["builder"], x86_64.store_stack(slot, 0))
            call emit_expression(generator, stop_expression)
            if infer_expression_type(stop_expression, generator["types"], generator["function_returns"]) == "Any":
                call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                call assembler.relative(generator["builder"], [232], "runtime_unbox_dynamic_int")
            end
            call assembler.emit(generator["builder"], x86_64.store_stack(stop_slot, 0))
            if len(arguments) == 3:
                step_syntax = arguments[2]
                step_type = infer_expression_type(step_syntax, generator["types"], generator["function_returns"])
                if step_type != "Int" and step_type != "Any":
                    call unsupported(generator["path"], generator["lines"], step_syntax, "rang step must be an Int", "pass an Int expression with a non-zero value")
                end
                call emit_expression(generator, step_syntax)
                if step_type == "Any":
                    call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                    call assembler.relative(generator["builder"], [232], "function___lsl_require_rang_step")
                    call emit_pending_error(generator)
                end
                call assembler.emit(generator["builder"], x86_64.store_stack(step_slot, 0))
            else:
                call assembler.emit(generator["builder"], x86_64.mov_imm64(0, 1))
                call assembler.emit(generator["builder"], x86_64.store_stack(step_slot, 0))
            end
            rang_step_ready = label_name(generator, "rang_step_ready")
            call assembler.emit(generator["builder"], x86_64.load_stack(0, step_slot))
            call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(0, 0))
            call assembler.relative(generator["builder"], [15, 133], rang_step_ready)
            rang_source_path = statement.get("path", generator["path"])
            call emit_runtime_raise(generator, "ValueError: rang step cannot be zero at " + rang_source_path + ":" + String(statement["line"]))
            call assembler.label(generator["builder"], rang_step_ready)
            start_label = label_name(generator, "for_start")
            positive_check = label_name(generator, "for_positive_check")
            body_label = label_name(generator, "for_body")
            continue_target = label_name(generator, "for_continue")
            end_label = label_name(generator, "for_end")
            call assembler.label(generator["builder"], start_label)
            call assembler.emit(generator["builder"], x86_64.load_stack(0, slot))
            call assembler.emit(generator["builder"], x86_64.load_stack(1, stop_slot))
            call assembler.emit(generator["builder"], x86_64.load_stack(2, step_slot))
            call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(2, 0))
            call assembler.relative(generator["builder"], [15, 143], positive_check)
            call assembler.emit(generator["builder"], x86_64.cmp_reg_reg(0, 1))
            call assembler.relative(generator["builder"], [15, 142], end_label)
            call assembler.relative(generator["builder"], [233], body_label)
            call assembler.label(generator["builder"], positive_check)
            call assembler.emit(generator["builder"], x86_64.cmp_reg_reg(0, 1))
            call assembler.relative(generator["builder"], [15, 141], end_label)
            call assembler.label(generator["builder"], body_label)
            call emit_statements(generator, statement["body"], end_label, continue_target, return_label)
            call assembler.label(generator["builder"], continue_target)
            call assembler.emit(generator["builder"], x86_64.load_stack(0, slot))
            call assembler.emit(generator["builder"], x86_64.load_stack(1, step_slot))
            call assembler.emit(generator["builder"], x86_64.add_reg_reg(0, 1))
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
                elif target_type == "ByteArray":
                    call unsupported(generator["path"], generator["lines"], statement, "ByteArray deletion is not implemented", "use clear or overwrite indexed bytes")
                end
                if target_type == "List" or target_type == "IntArray" or target_type == "FloatArray":
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
                call assembler.emit(generator["builder"], x86_64.mov_imm64(0, 0))
                if target["name"] in generator["variables"]:
                    call assembler.emit(generator["builder"], x86_64.store_stack(generator["variables"][target["name"]], 0))
                elif target["name"] in generator["global_variables"]:
                    call assembler.emit(generator["builder"], x86_64.store_memory(12, generator["global_variables"][target["name"]], 0))
                else:
                    call unsupported(generator["path"], generator["lines"], statement, "cannot delete unknown name " + target["name"], "assign the name before deleting it")
                end
            elif target["kind"] == "member":
                target_type = infer_expression_type(target["target"], generator["types"], generator["function_returns"])
                if not target_type.startswith("Class:") and not target_type.startswith("Instance:"):
                    call unsupported(generator["path"], generator["lines"], statement, "member deletion requires a class instance", "delete a field from an LSL class or instance")
                end
                call emit_expression(generator, target["target"])
                call assembler.emit(generator["builder"], x86_64.push(0))
                call emit_string_pointer(generator, target["name"])
                call assembler.emit(generator["builder"], x86_64.move_reg_reg(6, 0))
                call assembler.emit(generator["builder"], x86_64.pop(7))
                call assembler.relative(generator["builder"], [232], "runtime_dict_delete")
            else:
                call unsupported(generator["path"], generator["lines"], statement, "unsupported del target", "delete a name, mutable index, Dictionary key, or instance field")
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
            dynamic_return = generator.get("current_return_type", "Any") == "Any"
            if statement["expression"] == None:
                if dynamic_return and generator["path"].find("compiler/pure/") < 0 and not generator.get("current_internal_function", False):
                    call assembler.relative(generator["builder"], [232], "runtime_box_none")
                else:
                    call assembler.emit(generator["builder"], x86_64.mov_imm64(0, 0))
                end
            else:
                call emit_expression(generator, statement["expression"])
                if generator["path"].find("compiler/pure/") < 0 and not generator.get("current_internal_function", False):
                    return_type = infer_expression_type(statement["expression"], generator["types"], generator["function_returns"])
                    if return_type == "Function" or (dynamic_return and (return_type == "Int" or return_type == "Bool" or return_type == "None")):
                        call emit_collection_box(generator, statement["expression"])
                    elif return_type == "Any" and statement["expression"]["kind"] == "binary":
                        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                        call assembler.relative(generator["builder"], [232], "runtime_box_dynamic_int")
                    end
                end
            end
            call assembler.relative(generator["builder"], [233], return_label)
        else:
            call unsupported(generator["path"], generator["lines"], statement, "statement kind " + kind + " is not implemented", "use scalar assignment, print, if, while, loop, break, or continue")
        end
        # No following statement in this block can execute after an
        # unconditional transfer. Avoid dead code and its literal data.
        if kind == "return" or kind == "break" or kind == "continue" or kind == "error":
            break
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
            selected = constant_if_body(statement)
            if selected[0]:
                branch_type = returned_type(selected[1], types, function_returns)
                result = merge_return_type(result, branch_type)
            else:
                for branch in statement["branches"]:
                    branch_type = returned_type(branch[1], types, function_returns)
                    result = merge_return_type(result, branch_type)
                end
                branch_type = returned_type(statement["otherwise"], types, function_returns)
                result = merge_return_type(result, branch_type)
            end
        elif kind == "while" or kind == "loop" or kind == "for":
            include_body = True
            if kind == "while":
                condition = constant_truth_expression(statement["condition"])
                include_body = not condition[0] or condition[1]
            end
            if include_body:
                branch_type = returned_type(statement["body"], types, function_returns)
                result = merge_return_type(result, branch_type)
            end
        elif kind == "safe" or kind == "try":
            branch_type = returned_type(statement["body"], types, function_returns)
            result = merge_return_type(result, branch_type)
            branch_type = returned_type(statement["otherwise"], types, function_returns)
            result = merge_return_type(result, branch_type)
        end
        if kind == "return" or kind == "break" or kind == "continue" or kind == "error":
            break
        end
    end
    return result
end

function specializable_parameter_type(value_type):
    return value_type == "Int" or value_type == "Bool" or value_type == "None" or value_type == "Float" or value_type == "String" or value_type == "List" or value_type == "Tuple" or value_type == "RealArray" or value_type == "Dictionary" or value_type == "IntArray" or value_type == "FloatArray" or value_type == "ByteArray" or value_type.startswith("Class:") or value_type.startswith("Instance:")
end

function empty_parameter_types(functions):
    result = {}
    for name in functions.keys():
        values = []
        for parameter in functions[name]["parameters"]:
            values.append("")
        end
        result[name] = values
    end
    return result
end

function dynamic_parameter_types(functions):
    result = empty_parameter_types(functions)
    for name in functions.keys():
        index = 0
        while index < len(result[name]):
            result[name][index] = "Any"
            index += 1
        end
    end
    return result
end

function observe_parameter(observations, name, index, value_type):
    if not specializable_parameter_type(value_type):
        value_type = "Any"
    end
    current = observations[name][index]
    if current == "":
        observations[name][index] = value_type
    elif current != value_type:
        observations[name][index] = "Any"
    end
end

function observe_expression_types(syntax, types, function_returns, functions, observations, escaped):
    if syntax == None:
        return
    end
    kind = syntax["kind"]
    if kind == "name":
        name = syntax["name"]
        if name in functions:
            escaped[name] = True
        end
    elif kind == "list" or kind == "tuple" or kind == "real_array":
        for item in syntax["items"]:
            call observe_expression_types(item, types, function_returns, functions, observations, escaped)
        end
    elif kind == "dictionary":
        for entry in syntax["entries"]:
            call observe_expression_types(entry[0], types, function_returns, functions, observations, escaped)
            call observe_expression_types(entry[1], types, function_returns, functions, observations, escaped)
        end
    elif kind == "member":
        call observe_expression_types(syntax["target"], types, function_returns, functions, observations, escaped)
    elif kind == "slice":
        call observe_expression_types(syntax["target"], types, function_returns, functions, observations, escaped)
        call observe_expression_types(syntax["start"], types, function_returns, functions, observations, escaped)
        call observe_expression_types(syntax["stop"], types, function_returns, functions, observations, escaped)
        call observe_expression_types(syntax.get("step", None), types, function_returns, functions, observations, escaped)
    elif kind == "index":
        call observe_expression_types(syntax["target"], types, function_returns, functions, observations, escaped)
        call observe_expression_types(syntax["index"], types, function_returns, functions, observations, escaped)
    elif kind == "unary":
        call observe_expression_types(syntax["operand"], types, function_returns, functions, observations, escaped)
    elif kind == "binary":
        call observe_expression_types(syntax["left"], types, function_returns, functions, observations, escaped)
        call observe_expression_types(syntax["right"], types, function_returns, functions, observations, escaped)
    elif kind == "compare":
        for operand in syntax["operands"]:
            call observe_expression_types(operand, types, function_returns, functions, observations, escaped)
        end
    elif kind == "call":
        target = syntax["target"]
        direct_name = ""
        if target["kind"] == "name" and target["name"] in functions:
            direct_name = target["name"]
        else:
            call observe_expression_types(target, types, function_returns, functions, observations, escaped)
        end
        index = 0
        while index < len(syntax["arguments"]):
            argument = syntax["arguments"][index]
            call observe_expression_types(argument, types, function_returns, functions, observations, escaped)
            if direct_name != "" and index < len(observations[direct_name]):
                call observe_parameter(observations, direct_name, index, infer_expression_type(argument, types, function_returns))
            end
            index += 1
        end
    end
end

function observe_statement_types(statements, types, function_returns, functions, observations, escaped):
    for statement in statements:
        kind = statement["kind"]
        if kind == "assign":
            target = statement["target"]
            if target["kind"] != "name":
                call observe_expression_types(target, types, function_returns, functions, observations, escaped)
            end
            call observe_expression_types(statement["value"], types, function_returns, functions, observations, escaped)
            if target["kind"] == "name":
                if statement["operator"] == "=":
                    assigned_type = infer_expression_type(statement["value"], types, function_returns)
                else:
                    operator = statement["operator"][0:len(statement["operator"]) - 1]
                    combined = {"kind": "binary", "operator": operator, "left": target, "right": statement["value"]}
                    assigned_type = infer_expression_type(combined, types, function_returns)
                end
                types[target["name"]] = assigned_type
            end
        elif kind == "print":
            for expression in statement["expressions"]:
                call observe_expression_types(expression, types, function_returns, functions, observations, escaped)
            end
        elif kind == "expression":
            call observe_expression_types(statement["expression"], types, function_returns, functions, observations, escaped)
        elif kind == "if":
            selected = constant_if_body(statement)
            if selected[0]:
                call observe_statement_types(selected[1], types, function_returns, functions, observations, escaped)
            else:
                for branch in statement["branches"]:
                    call observe_expression_types(branch[0], types, function_returns, functions, observations, escaped)
                    call observe_statement_types(branch[1], types, function_returns, functions, observations, escaped)
                end
                call observe_statement_types(statement["otherwise"], types, function_returns, functions, observations, escaped)
            end
        elif kind == "while" or kind == "loop":
            include_body = True
            if kind == "while":
                call observe_expression_types(statement["condition"], types, function_returns, functions, observations, escaped)
                condition = constant_truth_expression(statement["condition"])
                include_body = not condition[0] or condition[1]
            end
            if include_body:
                call observe_statement_types(statement["body"], types, function_returns, functions, observations, escaped)
            end
        elif kind == "for":
            iterable = statement["iterable"]
            call observe_expression_types(iterable, types, function_returns, functions, observations, escaped)
            iterable_type = infer_expression_type(iterable, types, function_returns)
            item_type = "Any"
            if iterable["kind"] == "call" and iterable["target"]["kind"] == "name" and (iterable["target"]["name"] == "rang" or iterable["target"]["name"] == "range"):
                item_type = "Int"
            elif iterable_type == "String":
                item_type = "String"
            elif iterable_type == "IntArray" or iterable_type == "ByteArray":
                item_type = "Int"
            elif iterable_type == "FloatArray":
                item_type = "Float"
            end
            types[statement["name"]] = item_type
            call observe_statement_types(statement["body"], types, function_returns, functions, observations, escaped)
        elif kind == "safe" or kind == "try":
            call observe_statement_types(statement["body"], types, function_returns, functions, observations, escaped)
            call observe_statement_types(statement["otherwise"], types, function_returns, functions, observations, escaped)
        elif kind == "return":
            call observe_expression_types(statement["expression"], types, function_returns, functions, observations, escaped)
        elif kind == "error":
            call observe_expression_types(statement["message"], types, function_returns, functions, observations, escaped)
        elif kind == "delete":
            call observe_expression_types(statement["target"], types, function_returns, functions, observations, escaped)
        elif kind == "class":
            call observe_expression_types(statement["condition"], types, function_returns, functions, observations, escaped)
            types[statement["name"]] = "Class:" + statement["name"]
            for member in statement["body"]:
                if member["kind"] == "assign":
                    call observe_expression_types(member["value"], types, function_returns, functions, observations, escaped)
                end
            end
        end
        if kind == "return" or kind == "break" or kind == "continue" or kind == "error":
            break
        end
    end
end

function expression_blocks_specialization(syntax):
    if syntax == None:
        return False
    end
    kind = syntax["kind"]
    if kind == "call":
        target = syntax["target"]
        if target["kind"] == "name":
            name = target["name"]
            if name.startswith("__lsl_") or name == "type" or name == "Int" or name == "Bool" or name == "String":
                return True
            end
        end
        if expression_blocks_specialization(target):
            return True
        end
        for argument in syntax["arguments"]:
            if expression_blocks_specialization(argument):
                return True
            end
        end
    elif kind == "list" or kind == "tuple" or kind == "real_array":
        for item in syntax["items"]:
            if expression_blocks_specialization(item):
                return True
            end
        end
    elif kind == "dictionary":
        for entry in syntax["entries"]:
            if expression_blocks_specialization(entry[0]) or expression_blocks_specialization(entry[1]):
                return True
            end
        end
    elif kind == "member":
        return expression_blocks_specialization(syntax["target"])
    elif kind == "slice":
        return expression_blocks_specialization(syntax["target"]) or expression_blocks_specialization(syntax["start"]) or expression_blocks_specialization(syntax["stop"]) or expression_blocks_specialization(syntax.get("step", None))
    elif kind == "index":
        return expression_blocks_specialization(syntax["target"]) or expression_blocks_specialization(syntax["index"])
    elif kind == "unary":
        return expression_blocks_specialization(syntax["operand"])
    elif kind == "binary":
        return expression_blocks_specialization(syntax["left"]) or expression_blocks_specialization(syntax["right"])
    elif kind == "compare":
        for operand in syntax["operands"]:
            if expression_blocks_specialization(operand):
                return True
            end
        end
    end
    return False
end

function statements_block_specialization(statements):
    for statement in statements:
        kind = statement["kind"]
        if kind == "assign":
            if expression_blocks_specialization(statement["target"]) or expression_blocks_specialization(statement["value"]):
                return True
            end
        elif kind == "print":
            for expression in statement["expressions"]:
                if expression_blocks_specialization(expression):
                    return True
                end
            end
        elif kind == "expression" and expression_blocks_specialization(statement["expression"]):
            return True
        elif kind == "return" and expression_blocks_specialization(statement["expression"]):
            return True
        elif kind == "error" and expression_blocks_specialization(statement["message"]):
            return True
        elif kind == "delete" and expression_blocks_specialization(statement["target"]):
            return True
        elif kind == "if":
            for branch in statement["branches"]:
                if expression_blocks_specialization(branch[0]) or statements_block_specialization(branch[1]):
                    return True
                end
            end
            if statements_block_specialization(statement["otherwise"]):
                return True
            end
        elif kind == "while" or kind == "loop" or kind == "for":
            if kind == "while" and expression_blocks_specialization(statement["condition"]):
                return True
            elif kind == "for" and expression_blocks_specialization(statement["iterable"]):
                return True
            end
            if statements_block_specialization(statement["body"]):
                return True
            end
        elif kind == "safe" or kind == "try":
            if statements_block_specialization(statement["body"]) or statements_block_specialization(statement["otherwise"]):
                return True
            end
        elif kind == "function":
            if statements_block_specialization(statement["body"]):
                return True
            end
        elif kind == "class":
            if expression_blocks_specialization(statement["condition"]):
                return True
            end
            for member in statement["body"]:
                if member["kind"] == "function":
                    if statements_block_specialization(member["body"]):
                        return True
                    end
                elif member["kind"] == "assign" and expression_blocks_specialization(member["value"]):
                    return True
                end
            end
        end
    end
    return False
end

function has_specialization_candidate(functions):
    for name in functions.keys():
        declaration = functions[name]
        declaration_path = declaration.get("path", "")
        if declaration_path.find("compiler/pure/") < 0 and len(declaration["parameters"]) > 0:
            if not statements_block_specialization(declaration["body"]):
                return True
            end
        end
    end
    return False
end

function program_blocks_specialization(program):
    for statement in program:
        statement_path = statement.get("path", "")
        if statement_path.find("compiler/pure/") < 0:
            if statements_block_specialization([statement]):
                return True
            end
        end
    end
    return False
end

function infer_function_parameters(program, functions, function_returns, global_types):
    result = empty_parameter_types(functions)
    blocked = {}
    for name in functions.keys():
        blocked[name] = name.startswith("__lsl_") or statements_block_specialization(functions[name]["body"])
    end
    iteration = 0
    while iteration < len(functions) + 2:
        observations = empty_parameter_types(functions)
        escaped = {}
        main_types = {}
        call observe_statement_types(program, main_types, function_returns, functions, observations, escaped)
        for name in functions.keys():
            if not blocked[name]:
                types = {}
                for global_name in global_types.keys():
                    types[global_name] = global_types[global_name]
                end
                index = 0
                while index < len(functions[name]["parameters"]):
                    parameter_type = result[name][index]
                    if parameter_type == "":
                        parameter_type = "Any"
                    end
                    types[functions[name]["parameters"][index]] = parameter_type
                    index += 1
                end
                call observe_statement_types(functions[name]["body"], types, function_returns, functions, observations, escaped)
            end
        end
        changed = False
        for name in functions.keys():
            index = 0
            while index < len(result[name]):
                candidate = observations[name][index]
                if name in escaped or blocked[name]:
                    candidate = "Any"
                end
                if candidate != "" and candidate != result[name][index]:
                    result[name][index] = candidate
                    changed = True
                end
                index += 1
            end
        end
        if not changed:
            break
        end
        iteration += 1
    end
    for name in functions.keys():
        index = 0
        while index < len(result[name]):
            if result[name][index] == "":
                result[name][index] = "Any"
            end
            index += 1
        end
    end
    return result
end

function infer_function_returns(functions, classes, parameter_types):
    # Least-fixed-point over the 3-level lattice None < concrete < Any. Start at
    # bottom (None) so a not-yet-resolved recursive call is the merge identity
    # rather than Any; otherwise merge(Bool, Any) = Any poisoned recursive
    # Bool/Float returns (e.g. is_even printed 1 instead of True). Iterate until
    # stable; monotonic widening bounds it by 2*len(names).
    result = {}
    for class_name in classes.keys():
        result["__class__" + class_name] = "Instance:" + class_name
    end
    names = functions.keys()
    for name in names:
        result[name] = "None"
    end
    max_iterations = len(names) * 2 + 4
    iteration = 0
    changed = True
    while changed and iteration < max_iterations:
        changed = False
        for name in names:
            declaration = functions[name]
            types = {}
            parameter_index = 0
            for parameter in declaration["parameters"]:
                types[parameter] = parameter_types[name][parameter_index]
                parameter_index += 1
            end
            call collect_types(declaration["body"], types, result)
            inferred = returned_type(declaration["body"], types, result)
            if inferred != result[name]:
                result[name] = inferred
                changed = True
            end
        end
        iteration += 1
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
    # Assigned locals and parameters lexically shadow same-named globals. Do not
    # merge their type flow with an unrelated global declaration.
    for local_name in variables.keys():
        if local_name in types:
            del(types[local_name])
        end
    end
    parameter_index = 0
    for parameter in declaration["parameters"]:
        types[parameter] = generator["function_parameters"][name][parameter_index]
        parameter_index += 1
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
    old_current_return_type = generator.get("current_return_type", "Any")
    old_internal_function = generator.get("current_internal_function", False)
    generator["variables"] = variables
    generator["types"] = types
    generator["current_return_type"] = generator["function_returns"].get(name, "Any")
    generator["current_internal_function"] = declaration.get("path", generator["path"]).find("compiler/pure/") >= 0
    call assembler.label(generator["builder"], "function_" + name)
    call assembler.emit(generator["builder"], x86_64.function_prologue(aligned_frame(variables)))
    argument_registers = [7, 6, 2, 1, 8, 9]
    index = 0
    while index < len(declaration["parameters"]):
        parameter = declaration["parameters"][index]
        if index < len(argument_registers):
            call assembler.emit(generator["builder"], x86_64.store_stack(__lsl_typed_int(variables[parameter]), __lsl_typed_int(argument_registers[index])))
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
    generator["current_return_type"] = old_current_return_type
    generator["current_internal_function"] = old_internal_function
end

function generate(path, source, program):
    lines = source
    classes = class_table(program)
    functions = function_table(path, lines, program)
    parameter_types = dynamic_parameter_types(functions)
    function_returns = infer_function_returns(functions, classes, parameter_types)
    main_variables = {}
    call collect_variables(program, main_variables)
    main_types = {}
    call collect_types(program, main_types, function_returns)
    internal_abi = path.find("compiler/pure/") >= 0
    if not internal_abi and has_specialization_candidate(functions) and not program_blocks_specialization(program):
        # Direct-call observations propagate parameter types through helper
        # chains. Escaping callbacks retain their dynamic ABI.
        parameter_types = infer_function_parameters(program, functions, function_returns, main_types)
        function_returns = infer_function_returns(functions, classes, parameter_types)
        main_types = {}
        call collect_types(program, main_types, function_returns)
    end
    output = assembler.builder()
    generator = {"path": path, "internal_abi": internal_abi, "lines": lines, "variables": {}, "types": {}, "global_variables": main_variables, "global_types": main_types, "functions": functions, "classes": classes, "function_returns": function_returns, "function_parameters": parameter_types, "builder": output, "data": [], "string_offsets": {}, "relocations": [], "counter": 0, "error_label": ""}
    registry_bytes = 524288
    registry_mask = 65535
    if generator["internal_abi"]:
        # The compiler allocates millions of short-lived objects; avoid repeated
        # rehash stages there. Normal programs start at 64K slots and grow.
        registry_bytes = 67108864
        registry_mask = 8388607
    end
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
    # State uses bytes 0..95. Keep only the 1 MiB String-intern table on brk;
    # the object registry starts small in mmap and returns old growth tables.
    call assembler.emit(output, x86_64.lea_base(9, 3, 96))
    call assembler.emit(output, x86_64.move_reg_reg(7, 9))
    call assembler.emit(output, x86_64.add_reg_imm32(7, 1048576))
    call assembler.emit(output, x86_64.mov_imm64(0, 12))
    call assembler.emit(output, x86_64.syscall())
    call assembler.emit(output, x86_64.cmp_reg_reg(0, 7))
    call assembler.relative(output, [15, 133], "runtime_fatal_allocation")
    call assembler.emit(output, x86_64.mov_imm64(0, 9))
    call assembler.emit(output, x86_64.xor_reg_reg(7, 7))
    call assembler.emit(output, x86_64.mov_imm64(6, registry_bytes))
    call assembler.emit(output, x86_64.mov_imm64(2, 3))
    call assembler.emit(output, x86_64.mov_imm64(10, 34))
    call assembler.emit(output, x86_64.mov_imm64(8, -1))
    call assembler.emit(output, x86_64.xor_reg_reg(9, 9))
    call assembler.emit(output, x86_64.syscall())
    call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
    call assembler.relative(output, [15, 140], "runtime_fatal_allocation")
    call assembler.emit(output, x86_64.store_memory(3, 32, 0))
    call assembler.emit(output, x86_64.mov_imm64(10, registry_mask))
    call assembler.emit(output, x86_64.store_memory(3, 40, 10))
    call assembler.emit(output, x86_64.lea_base(9, 3, 96))
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
