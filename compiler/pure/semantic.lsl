# Společná sémantika jazyka nad AST, bez strojových instrukcí a paměťových offsetů.

load declarations
load diagnostics
load flow

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

function magic_signed(divisor, width=64):
    # Granlund-Montgomery signed magic for a constant divisor d in [3, 2^31).
    # Shared by native code generation and QBE constant-division lowering.
    # Returns [M, s]: floor-free truncated quotient is high64(n*M) [+n if M<0]
    # then >> s. Pure signed 64-bit math (q2 may wrap as a bit pattern).
    pow63_minus_1 = 9223372036854775807
    if width == 32:
        pow63_minus_1 = 2147483647
    end
    ad = divisor
    t = pow63_minus_1 - ((pow63_minus_1 % ad + 1) % ad)
    anc = t
    # anc lies in (2^62, 2^63), so (2^63)//anc == 1 and (2^63)%anc == 2^63-anc.
    r1 = pow63_minus_1 - anc + 1
    q1 = 1
    divmod2 = pow63_divmod(ad)
    if width == 32:
        divmod2 = [2147483648 // ad, 2147483648 % ad]
    end
    q2 = divmod2[0]
    r2 = divmod2[1]
    p = width - 1
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
    if width == 32 and magic >= 2147483648:
        magic -= 4294967296
    end
    return [magic, p - width]
end

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

function collect_expression_variables(value, variables):
    if type(value) == "List":
        for item in value:
            call collect_expression_variables(item, variables)
        end
    elif type(value) == "Dictionary":
        if value.get("kind", "") == "comprehension":
            call collect_variables(value["body"], variables)
            return
        end
        for field in ["target", "value", "condition", "expression", "iterable", "left", "right", "operand", "index", "start", "stop", "step", "message", "parent", "arguments", "items", "operands", "expressions", "entries"]:
            if field in value:
                call collect_expression_variables(value[field], variables)
            end
        end
        if "branches" in value:
            for branch in value["branches"]:
                call collect_expression_variables(branch[0], variables)
            end
        end
    end
end

function collect_variables(statements, variables):
    for statement in statements:
        if statement.get("has_comprehension", False):
            call collect_expression_variables(statement, variables)
        end
        kind = statement["kind"]
        if kind == "class":
            name = statement["name"]
            if name not in variables:
                variables[name] = len(variables) + 1
            end
        elif kind == "assign":
            if statement["target"]["kind"] == "name":
                name = statement["target"]["name"]
                if name not in variables:
                    variables[name] = len(variables) + 1
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
        elif kind == "unsafe":
            call collect_variables(statement["body"], variables)
        elif kind == "safe" or kind == "try":
            call collect_variables(statement["body"], variables)
            call collect_variables(statement["otherwise"], variables)
        elif kind == "for":
            name = statement["name"]
            if name not in variables:
                variables[name] = len(variables) + 1
            end
            iterator_name = "@iterator@" + String(len(variables))
            variables[iterator_name] = len(variables) + 1
            index_name = "@iterator_index@" + String(len(variables))
            variables[index_name] = len(variables) + 1
            statement["iterator_name"] = iterator_name
            statement["index_name"] = index_name
            call collect_variables(statement["body"], variables)
        end
        if kind == "return" or kind == "break" or kind == "continue" or kind == "error":
            break
        end
    end
end


# Builtin return types are immutable. A single lookup replaces repeated long
# chains of String comparisons at every inference visit.
BUILTIN_RETURN_TYPES = {"len":"Int","Int":"Int","ord":"Int","arg_count":"Int","run":"Int","__lsl_run":"Int","run_clean":"Int","__lsl_run_clean":"Int","capture_status":"Int","native_u64":"Int","native_size":"Int","native_call":"Int","native_close":"Int","__lsl_type_code":"Int","__lsl_raw_equal":"Int","__lsl_float_bits":"Int","__lsl_float_candidate_bits":"Int","__lsl_float_from_decimal":"Int","__lsl_decimal_compare":"Int","__lsl_decimal_digits_compare":"Int","__lsl_float_nearer_upper":"Bool","__lsl_float_to_int":"Int","__lsl_unbox_int":"Int","__lsl_raw_int":"Int","__lsl_typed_int":"Int","__lsl_checked_index":"Int","__lsl_parse_literal_int":"Int","__lsl_test_fd_fault":"Int","__lsl_address":"Int","__lsl_object_table_mask":"Int","__lsl_intern_table_mask":"Int","__lsl_fd_open":"Int","__lsl_fd_read":"Int","__lsl_fd_write":"Int","__lsl_fd_seek":"Int","__lsl_fd_close":"Int","__lsl_fd_socket":"Int","__lsl_fd_connect":"Int","__lsl_raster_pack":"Int","__lsl_raster_copy":"Int","__lsl_raster_fill":"Int","__lsl_fd_ioctl":"Int","__lsl_fd_mmap":"Int","__lsl_mem_pack":"Int","__lsl_data_address":"Int","__lsl_syscall":"Int","__lsl_syscall6":"Int","__lsl_mem_unpack":"Int","__lsl_byte_copy":"Int","__lsl_text_byte":"Int","__lsl_text_byte_length":"Int","__lsl_text_scan_digits":"Int","__lsl_text_digits":"Int","atomic_add":"Int","atomic_xchg":"Int","atomic_cas":"Int","thread_spawn":"Int","thread_join":"Int","cpu_count":"Int","popcount":"Int","trailing_zeros":"Int","Float":"Float","sqrt":"Float","__lsl_float_from_bits":"Float","float_sum":"Float","float_dot":"Float","__lsl_wall_time":"Float","Bool":"Bool","__lsl_isatty":"Bool","__lsl_stdin_eof":"Bool","last_error":"Any","String":"String","chr":"String","arg":"Any","input":"String","readfile":"String","type":"String","capture":"String","__lsl_capture":"String","capture_clean":"String","__lsl_capture_clean":"String","capture_stream":"String","capture_stream_clean":"String","capture_input":"String","capture_input_clean":"String","capture_input_stream":"String","capture_input_stream_clean":"String","__lsl_capture_input_timeout":"String","__lsl_run_timeout":"Int","capture_stderr":"String","executable_path":"String","__lsl_text_from_bytes":"String","__lsl_text_piece":"String","__lsl_floatarray_bytes":"String","clock":"String","monotonic":"Float","__lsl_monotonic":"Float","exists":"Bool","cwd":"String","chdir":"None","remove_path":"None","listdir":"List","__lsl_list_directory":"List","eprint":"None","__lsl_rename":"Int","native_name_equal":"Bool","__lsl_sleep":"None","atomic_pause":"None","help":"None","__lsl_set_append":"None","__lsl_set_store":"None","List":"List","sorted":"List","dedup":"List","__lsl_text_split_byte":"List","set":"Set","__lsl_new_set":"Set","Tuple":"Tuple","RealArray":"RealArray","IntArray":"IntArray","__lsl_int_zeros":"IntArray","FloatArray":"FloatArray","float_zeros":"FloatArray","float_matmul":"FloatArray","__lsl_floatarray_from_bytes":"FloatArray","ByteArray":"ByteArray","readbytes":"ByteArray","__lsl_byte_zeros":"ByteArray","Dictionary":"Dictionary"}

function return_type_value(function_returns, key):
    value = function_returns[key]
    # The sentinel is not a source identifier. It exists only during a return
    # evaluation, when the result key set and globals/parameters are fixed.
    if "@return.inputs" in function_returns:
        function_returns["@return.inputs"][key] = value
    end
    return value
end

# Runtime napsaný v LSL (# lsl: runtime): literály jsou surová slova
# (String je adresa statického záznamu, Float jsou bity binary64).
RUNTIME_SOURCE = [False]

function infer_expression_type(syntax, types, function_returns):
    if syntax == None:
        return "None"
    end
    kind = syntax["kind"]
    if RUNTIME_SOURCE[0] and kind == "list":
        # Tabulka runtime: hodnotou je adresa pole slov.
        return "Int"
    end
    if kind == "literal":
        if RUNTIME_SOURCE[0] and (syntax["literal_kind"] == "string" or syntax["literal_kind"] == "number"):
            return "Int"
        end
        if syntax["literal_kind"] == "string":
            return "String"
        elif syntax["literal_kind"] == "number":
            if "." in syntax["value"] or "e" in syntax["value"] or "E" in syntax["value"]:
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
    elif kind == "comprehension":
        call collect_types(syntax["body"], types, function_returns)
        if syntax["collection_kind"] == "dictionary":
            return "Dictionary"
        elif syntax["collection_kind"] == "conditional":
            return infer_expression_type(syntax["result"], types, function_returns)
        end
        return "List"
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
        elif syntax["operator"] == "~":
            return "Int"
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
            if (left == "String" and (right == "Int" or right == "Bool")) or ((left == "Int" or left == "Bool") and right == "String"):
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
            if name.startswith("__lsl_declared_"):
                return name[15:len(name)]
            end
            if name == "abs":
                return infer_expression_type(syntax["arguments"][0], types, function_returns)
            end
            if name == "__lsl_fd_snapshot":
                return "Int"
            end
            if name == "__lsl_entry_source":
                return "String"
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
            if name.startswith("__lsl_qbe_fcall") or name in ["__lsl_qbe_f32","__lsl_qbe_loadf32","__lsl_qbe_fadd","__lsl_qbe_fsub","__lsl_qbe_fmul","__lsl_qbe_fdiv","__lsl_qbe_uitof"]:
                return "Float"
            elif name.startswith("__lsl_qbe_") or name.startswith("__lsl_raw_f") or name == "__lsl_symbol":
                return "Int"
            end
            if name in BUILTIN_RETURN_TYPES:
                return BUILTIN_RETURN_TYPES[name]
            elif "__class__" + name in function_returns:
                return return_type_value(function_returns, "__class__" + name)
            elif name in function_returns:
                return return_type_value(function_returns, name)
            end
        elif target["kind"] == "member":
            member = target["name"]
            receiver_type = infer_expression_type(target["target"], types, function_returns)
            if receiver_type == "Set":
                if member == "copy" or member == "union" or member == "intersection" or member == "difference" or member == "symmetric_difference":
                    return "Set"
                elif member == "issubset" or member == "issuperset" or member == "isdisjoint":
                    return "Bool"
                elif member == "add" or member == "discard" or member == "remove" or member == "update" or member == "clear":
                    return "None"
                end
            end
            if receiver_type.startswith("Class:") or receiver_type.startswith("Instance:"):
                if receiver_type.startswith("Class:"):
                    receiver_class = receiver_type[6:len(receiver_type)]
                else:
                    receiver_class = receiver_type[9:len(receiver_type)]
                end
                receiver_method = receiver_class + "__" + member
                if receiver_method in function_returns:
                    return return_type_value(function_returns, receiver_method)
                end
            end
            if member == "append" or member == "extend" or member == "sort" or member == "reverse" or member == "clear":
                return "None"
            elif (receiver_type == "Any" or receiver_type == "Set") and (member == "add" or member == "discard"):
                return "None"
            elif (receiver_type == "Any" or receiver_type == "Set") and (member == "issubset" or member == "issuperset" or member == "isdisjoint"):
                return "Bool"
            elif (receiver_type == "Any" or receiver_type == "Set") and (member == "union" or member == "intersection" or member == "difference" or member == "symmetric_difference"):
                return "Set"
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

# One collect_types pass depends on statement order: `x = x // p` is typed
# Int while p is still Int, and a later `for p in items` widens p to Any
# without revisiting x. Emission then boxes the division result but stores
# it into x's raw slot. Repeat until no variable type changes; widening only
# moves towards Any, so the loop converges quickly.
# Záznam kola collect_types_stable: jméno -> [existovalo, původní typ] pro
# každý klíč, do kterého kolo zapsalo. Mimo kolo None (ostatní volající
# collect_types nic nezaznamenávají).
TYPE_TRACE = None

function set_type(types, name, value):
    if TYPE_TRACE != None and name not in TYPE_TRACE:
        if name in types:
            TYPE_TRACE[name] = [True, types[name]]
        else:
            TYPE_TRACE[name] = [False, None]
        end
    end
    types[name] = value
end

function collect_types_stable(statements, types, function_returns):
    # Změnu kola pozná podle zapsaných klíčů (collect_types klíče nemaže);
    # dřív se celý slovník, včetně všech globálů, v každém kole kopíroval.
    global TYPE_TRACE
    saved = TYPE_TRACE
    for round in rang(16):
        trace = {}
        TYPE_TRACE = trace
        call collect_types(statements, types, function_returns)
        TYPE_TRACE = saved
        changed = False
        for name in trace.keys():
            entry = trace[name]
            if not entry[0] or entry[1] != types[name]:
                changed = True
                break
            end
        end
        if not changed:
            return None
        end
    end
    return None
end

function collect_types(statements, types, function_returns):
    for statement in statements:
        kind = statement["kind"]
        if kind == "class":
            call set_type(types, statement["name"], "Class:" + statement["name"])
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
                if "declared_type" in statement and statement["declared_type"] != "Any":
                    call set_type(types, name, statement["declared_type"])
                elif name in types and types[name] != assigned_type:
                    call set_type(types, name, "Any")
                else:
                    call set_type(types, name, assigned_type)
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
            # Hidden loop controls are ordinary locals in current codegen.
            # Give their unboxed integer values types so the register-local
            # allocator can keep hot counters and explicit steps off-stack.
            call set_type(types, statement["index_name"], "Int")
            if for_is_range:
                binding_type = "Int"
                call set_type(types, statement["iterator_name"], "Int")
            elif iterable_type == "String":
                binding_type = "String"
            elif iterable_type == "IntArray":
                binding_type = "Int"
            elif iterable_type == "FloatArray":
                binding_type = "Float"
            elif iterable_type == "ByteArray":
                binding_type = "Int"
            else:
                # List/Tuple/RealArray/Dictionary/Any elements are dynamic; Int
                # would miscompile boxed Float/None elements (e.g. sum of Floats).
                binding_type = "Any"
            end
            binding = statement["name"]
            if binding in types and types[binding] != binding_type:
                call set_type(types, binding, "Any")
            else:
                call set_type(types, binding, binding_type)
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
        elif kind == "unsafe":
            call collect_types(statement["body"], types, function_returns)
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

function is_sequence_type(value_type):
    return value_type == "String" or value_type == "List" or value_type == "Tuple" or value_type == "RealArray" or value_type == "IntArray" or value_type == "FloatArray" or value_type == "ByteArray"
end

function is_sized_type(value_type):
    return is_sequence_type(value_type) or value_type == "Dictionary" or value_type == "Set"
end

function set_method(name):
    return name == "add" or name == "discard" or name == "union" or name == "intersection" or name == "difference" or name == "symmetric_difference" or name == "issubset" or name == "issuperset" or name == "isdisjoint"
end

function is_mutable_index_type(value_type):
    return value_type == "List" or value_type == "RealArray" or value_type == "IntArray" or value_type == "FloatArray" or value_type == "ByteArray" or value_type == "Dictionary"
end

function is_numeric_type(value_type):
    return value_type == "Int" or value_type == "Bool" or value_type == "Float" or value_type == "Any"
end

# Metoda třídy volaná na hodnotě bez statického typu (instance v parametru):
# jméno třídy, když metodu se jménem `name` implementuje právě jedna funkce;
# "@ambiguous", když ji implementuje víc tříd různě; "" jinak (vestavěná
# metoda nebo žádná třída). Instance za běhu nenese svou třídu, proto se
# nejednoznačná metoda nedá vybrat a překlad ji odmítne.
function dynamic_method_class(classes, functions, receiver_type, name):
    if receiver_type != "Any" or method_supported("Any", name):
        return ""
    end
    found = ""
    found_class = ""
    for class_name in classes.keys():
        resolved = resolve_method_name(classes, functions, class_name, name)
        if resolved != "":
            if found == "":
                found = resolved
                found_class = class_name
            elif resolved != found:
                return "@ambiguous"
            end
        end
    end
    return found_class
end

function method_supported(receiver_type, name):
    if receiver_type == "Any":
        return method_function(name) != "" or name == "append" or name == "clear" or name == "pop" or name == "keys" or name == "index" or set_method(name)
    elif receiver_type == "Set":
        return set_method(name) or name == "remove" or name == "pop" or name == "clear" or name == "update" or name == "copy"
    elif receiver_type == "String":
        return name == "strip" or name == "lstrip" or name == "rstrip" or name == "lower" or name == "upper" or name == "title" or name == "capitalize" or name == "startswith" or name == "endswith" or name == "find" or name == "index" or name == "count" or name == "split" or name == "join" or name == "replace"
    elif receiver_type == "List":
        return name == "append" or name == "extend" or name == "insert" or name == "pop" or name == "remove" or name == "clear" or name == "find" or name == "index" or name == "count" or name == "sort" or name == "reverse" or name == "copy"
    elif receiver_type == "Dictionary":
        return name == "get" or name == "keys" or name == "values" or name == "items" or name == "update" or name == "pop" or name == "clear" or name == "setdefault" or name == "copy"
    elif receiver_type == "Tuple":
        return name == "find" or name == "index" or name == "count"
    elif receiver_type == "RealArray":
        return name == "find" or name == "index" or name == "count" or name == "copy"
    elif receiver_type == "IntArray" or receiver_type == "FloatArray" or receiver_type == "ByteArray":
        return name == "append" or name == "clear"
    end
    return False
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
        if "." in text or "e" in text or "E" in text:
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
    elif operator == "<<" and right[1] >= 0 and right[1] <= 63:
        # a << k is a * 2^k under the same Int64 wrap the multiply already has.
        return [True, left[1] * (2 ^ right[1])]
    elif operator == ">>" and right[1] >= 0 and right[1] <= 62:
        # Arithmetic shift right is floor division by 2^k. Stop at 62 so the
        # divisor stays positive; 63 keeps the immediate SAR path instead.
        return [True, left[1] // (2 ^ right[1])]
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

function class_table(path, lines, program):
    result = {}
    for statement in program:
        if statement["kind"] == "class":
            if statement["name"] in result:
                call unsupported(path, lines, statement, "duplicate class: " + statement["name"], "rename one declaration")
            end
            result[statement["name"]] = statement
        end
    end
    return result
end

function class_parent_name(classes, class_name):
    if class_name not in classes:
        return ""
    end
    parent = classes[class_name].get("parent", None)
    if parent == None:
        return ""
    end
    if parent["kind"] != "name":
        return ""
    end
    return parent["name"]
end

function validate_class_hierarchy(path, lines, classes):
    for class_name in classes.keys():
        seen = {}
        current = class_name
        depth = 0
        while current != "":
            if current in seen:
                call unsupported(path, lines, classes[class_name], "inheritance cycle involving class " + current, "make the class hierarchy acyclic")
            end
            seen[current] = True
            parent = class_parent_name(classes, current)
            if parent != "" and parent not in classes:
                call unsupported(path, lines, classes[current], "unknown parent class: " + parent, "declare or import the parent class before inheriting from it")
            end
            current = parent
            depth += 1
            if depth > len(classes):
                call unsupported(path, lines, classes[class_name], "inheritance hierarchy is cyclic", "make the class hierarchy acyclic")
            end
        end
    end
end

function resolve_method_name(classes, functions, class_name, method_name):
    current = class_name
    depth = 0
    while current != "":
        candidate = current + "__" + method_name
        if candidate in functions:
            return candidate
        end
        current = class_parent_name(classes, current)
        depth += 1
        if depth > len(classes):
            break
        end
    end
    return ""
end

function populate_inherited_returns(classes, functions, result):
    for class_name in classes.keys():
        filled = {}
        ancestor = class_parent_name(classes, class_name)
        depth = 0
        while ancestor != "":
            prefix = ancestor + "__"
            for function_name in functions.keys():
                if function_name.startswith(prefix):
                    method_name = function_name[len(prefix):len(function_name)]
                    alias = class_name + "__" + method_name
                    if alias not in functions and alias not in filled:
                        result[alias] = result.get(function_name, "Any")
                        filled[alias] = True
                    end
                end
            end
            ancestor = class_parent_name(classes, ancestor)
            depth += 1
            if depth > len(classes):
                break
            end
        end
    end
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

# "@none" je výslovné `return None` (nebo holé `return`): na rozdíl od "None"
# (zatím žádný návrat) ho nelze sloučit se skalárem Int/Float/Bool, ten by
# None přeložil jako 0/0.0/False.
function merge_return_type(current, candidate):
    if candidate == "None":
        return current
    elif current == "None":
        return candidate
    elif current == candidate:
        return current
    elif candidate == "@none":
        if current in ["Int", "Float", "Bool"]:
            return "Any"
        end
        return current
    elif current == "@none":
        if candidate in ["Int", "Float", "Bool"]:
            return "Any"
        end
        return candidate
    end
    return "Any"
end

function returned_type(statements, types, function_returns):
    result = returned_type_marked(statements, types, function_returns)
    if result == "@none":
        return "None"
    end
    return result
end

function explicit_none(expression):
    return expression == None or (expression["kind"] == "literal" and expression["value"] == "None")
end

function returned_type_marked(statements, types, function_returns):
    result = "None"
    for statement in statements:
        kind = statement["kind"]
        if kind == "return":
            if explicit_none(statement["expression"]):
                result = merge_return_type(result, "@none")
            else:
                result = merge_return_type(result, infer_expression_type(statement["expression"], types, function_returns))
            end
        elif kind == "if":
            selected = constant_if_body(statement)
            if selected[0]:
                branch_type = returned_type_marked(selected[1], types, function_returns)
                result = merge_return_type(result, branch_type)
            else:
                for branch in statement["branches"]:
                    branch_type = returned_type_marked(branch[1], types, function_returns)
                    result = merge_return_type(result, branch_type)
                end
                branch_type = returned_type_marked(statement["otherwise"], types, function_returns)
                result = merge_return_type(result, branch_type)
            end
        elif kind == "while" or kind == "loop" or kind == "for":
            include_body = True
            if kind == "while":
                condition = constant_truth_expression(statement["condition"])
                include_body = not condition[0] or condition[1]
            end
            if include_body:
                branch_type = returned_type_marked(statement["body"], types, function_returns)
                result = merge_return_type(result, branch_type)
            end
        elif kind == "unsafe":
            branch_type = returned_type_marked(statement["body"], types, function_returns)
            result = merge_return_type(result, branch_type)
        elif kind == "safe" or kind == "try":
            branch_type = returned_type_marked(statement["body"], types, function_returns)
            result = merge_return_type(result, branch_type)
            branch_type = returned_type_marked(statement["otherwise"], types, function_returns)
            result = merge_return_type(result, branch_type)
        end
        if kind == "return" or kind == "break" or kind == "continue" or kind == "error":
            break
        end
    end
    return result
end

function specializable_parameter_type(value_type):
    return value_type == "Int" or value_type == "Bool" or value_type == "None" or value_type == "Float" or value_type == "String" or value_type == "List" or value_type == "Tuple" or value_type == "RealArray" or value_type == "Dictionary" or value_type == "IntArray" or value_type == "FloatArray" or value_type == "ByteArray" or value_type == "Set" or value_type.startswith("Class:") or value_type.startswith("Instance:")
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
    # Phase 1 of parameter inference ignores dynamic arguments passed from a
    # body whose own parameters are still unresolved: a recursive call such as
    # f(ply + 1) inside f must not poison the parameter before the external
    # callers were seen. Unresolved parameters later widen to Any and phase 2
    # observes every call site again, so genuinely dynamic calls still count.
    if value_type == "Any" and "__ignore_unresolved__" in observations and "__caller_unresolved__" in observations:
        return
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
    if kind == "comprehension":
        call observe_statement_types(syntax["body"], types, function_returns, functions, observations, escaped)
    elif kind == "name":
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
            if "argument_names" in syntax:
                escaped[direct_name] = True
            end
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
        elif kind == "unsafe":
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
            call observe_expression_types(statement.get("parent", None), types, function_returns, functions, observations, escaped)
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

function expression_blocks_specialization(syntax,caller=False):
    if syntax == None:
        return False
    end
    kind = syntax["kind"]
    if kind == "comprehension":
        return statements_block_specialization(syntax["body"],caller)
    elif kind == "call":
        target = syntax["target"]
        if target["kind"] == "name":
            name = target["name"]
            if name.startswith("__lsl_") or (not caller and name in ["type","Int","Bool","String"]):
                return True
            end
        end
        if expression_blocks_specialization(target,caller):
            return True
        end
        for argument in syntax["arguments"]:
            if expression_blocks_specialization(argument,caller):
                return True
            end
        end
    elif kind == "list" or kind == "tuple" or kind == "real_array":
        for item in syntax["items"]:
            if expression_blocks_specialization(item,caller):
                return True
            end
        end
    elif kind == "dictionary":
        for entry in syntax["entries"]:
            if expression_blocks_specialization(entry[0],caller) or expression_blocks_specialization(entry[1],caller):
                return True
            end
        end
    elif kind == "member":
        return expression_blocks_specialization(syntax["target"],caller)
    elif kind == "slice":
        return expression_blocks_specialization(syntax["target"],caller) or expression_blocks_specialization(syntax["start"],caller) or expression_blocks_specialization(syntax["stop"],caller) or expression_blocks_specialization(syntax.get("step", None),caller)
    elif kind == "index":
        return expression_blocks_specialization(syntax["target"],caller) or expression_blocks_specialization(syntax["index"],caller)
    elif kind == "unary":
        return expression_blocks_specialization(syntax["operand"],caller)
    elif kind == "binary":
        return expression_blocks_specialization(syntax["left"],caller) or expression_blocks_specialization(syntax["right"],caller)
    elif kind == "compare":
        for operand in syntax["operands"]:
            if expression_blocks_specialization(operand,caller):
                return True
            end
        end
    end
    return False
end

function statements_block_specialization(statements,caller=False):
    for statement in statements:
        kind = statement["kind"]
        if kind == "assign":
            if expression_blocks_specialization(statement["target"],caller) or expression_blocks_specialization(statement["value"],caller):
                return True
            end
        elif kind == "print":
            for expression in statement["expressions"]:
                if expression_blocks_specialization(expression,caller):
                    return True
                end
            end
        elif kind == "expression" and expression_blocks_specialization(statement["expression"],caller):
            return True
        elif kind == "return" and expression_blocks_specialization(statement["expression"],caller):
            return True
        elif kind == "error" and expression_blocks_specialization(statement["message"],caller):
            return True
        elif kind == "delete" and expression_blocks_specialization(statement["target"],caller):
            return True
        elif kind == "if":
            for branch in statement["branches"]:
                if expression_blocks_specialization(branch[0],caller) or statements_block_specialization(branch[1],caller):
                    return True
                end
            end
            if statements_block_specialization(statement["otherwise"],caller):
                return True
            end
        elif kind == "while" or kind == "loop" or kind == "for":
            if kind == "while" and expression_blocks_specialization(statement["condition"],caller):
                return True
            elif kind == "for" and expression_blocks_specialization(statement["iterable"],caller):
                return True
            end
            if statements_block_specialization(statement["body"],caller):
                return True
            end
        elif kind == "unsafe":
            if statements_block_specialization(statement["body"],caller):
                return True
            end
        elif kind == "safe" or kind == "try":
            if statements_block_specialization(statement["body"],caller) or statements_block_specialization(statement["otherwise"],caller):
                return True
            end
        elif kind == "function":
            # These bodies are skipped by parameter-flow observation. Their
            # callees must retain the public generic ABI as well.
            if "defaults" in statement or statement["name"].startswith("__lsl_"):
                return True
            end
            if statements_block_specialization(statement["body"]):
                return True
            end
        elif kind == "class":
            if expression_blocks_specialization(statement["condition"],caller) or expression_blocks_specialization(statement.get("parent", None),caller):
                return True
            end
            for member in statement["body"]:
                if member["kind"] == "function":
                    # Parameter inference skips default-bearing/opaque bodies.
                    # Their calls may introduce unseen types into other helpers.
                    if "defaults" in member or member["name"].startswith("__lsl_") or statements_block_specialization(member["body"]):
                        return True
                    end
                elif member["kind"] == "assign" and expression_blocks_specialization(member["value"],caller):
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
        if not declaration.get("internal_abi", False) and len(declaration["parameters"]) > 0:
            if not statements_block_specialization(declaration["body"]):
                return True
            end
        end
    end
    return False
end

function program_blocks_specialization(program):
    # Public conversions in the caller preserve value semantics. Function bodies
    # retain conservative blockers because their argument flows may be hidden.
    for statement in program:
        if not statement.get("internal_abi", False):
            if statements_block_specialization([statement],True):
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
        blocked[name] = name.startswith("__lsl_") or "defaults" in functions[name] or statements_block_specialization(functions[name]["body"])
    end
    iteration = 0
    phase = 0
    while iteration < len(functions) * 2 + 4:
        observations = empty_parameter_types(functions)
        if phase == 0:
            observations["__ignore_unresolved__"] = []
        end
        escaped = {}
        main_types = {}
        call observe_statement_types(program, main_types, function_returns, functions, observations, escaped)
        for name in functions.keys():
            if not blocked[name]:
                types = Dictionary(global_types)
                unresolved = False
                index = 0
                while index < len(functions[name]["parameters"]):
                    parameter_type = result[name][index]
                    # Seed recursion from observations already made at known
                    # callers. An unresolved Any here used to poison f(n - 1)
                    # even when every external call supplied an Int.
                    if parameter_type == "":
                        parameter_type = observations[name][index]
                    end
                    if parameter_type == "":
                        parameter_type = "Any"
                        unresolved = True
                    end
                    types[functions[name]["parameters"][index]] = parameter_type
                    index += 1
                end
                if unresolved:
                    observations["__caller_unresolved__"] = []
                elif "__caller_unresolved__" in observations:
                    del(observations["__caller_unresolved__"])
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
            if phase == 1:
                break
            end
            # Phase 1 converged: widen the still-unresolved parameters to Any
            # and re-observe every call site without the recursion filter.
            phase = 1
            for name in functions.keys():
                index = 0
                while index < len(result[name]):
                    if result[name][index] == "":
                        result[name][index] = "Any"
                    end
                    index += 1
                end
            end
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

function return_dependency_values_unchanged(previous, result):
    for key in previous:
        if previous[key] != result[key]:
            return False
        end
    end
    return True
end

# Všechny řetězce v AST těla (jména, cíle, atributy, literály): konzervativní
# nadmnožina globálních jmen, která může inference funkce přečíst.
function syntax_strings(node, found):
    # Kód typu místo type(): obecný průchod celým AST je v překladu horký.
    code = __lsl_type_code(node)
    if code == 3:
        for key in node.keys():
            call syntax_strings(node[key], found)
        end
    elif code == 2:
        for item in node:
            call syntax_strings(item, found)
        end
    elif code == 1:
        found[node] = True
    end
end

# Funkce, jejichž výsledek z předchozího volání (memo) platí beze změny: stejné
# typy parametrů, žádné čtené globální jméno se změněným typem a všechny
# zaznamenané závislosti jsou opět takové funkce (uzavřený podsystém má
# stejný nejmenší pevný bod). Metody tříd a aliasy se nepřebírají.
function reusable_returns(functions, parameter_types, global_types, memo):
    stable = {}
    if "result" not in memo or not memo["converged"]:
        return stable
    end
    previous_parameters = memo["parameters"]
    previous_globals = memo["globals"]
    strings = memo["strings"]
    for name in functions.keys():
        declaration = functions[name]
        if "class_name" in declaration or name not in memo["inputs"] or name not in previous_parameters:
            continue
        end
        if parameter_types[name] != previous_parameters[name]:
            continue
        end
        if name not in strings:
            found = {}
            call syntax_strings(declaration["body"], found)
            strings[name] = found
        end
        locals = memo["locals"][name]
        same = True
        for text in strings[name]:
            if text not in locals and global_types.get(text, None) != previous_globals.get(text, None):
                same = False
                break
            end
        end
        if same:
            stable[name] = True
        end
    end
    removed = True
    while removed:
        removed = False
        for name in stable.keys():
            for key in memo["inputs"][name]:
                if key in functions:
                    if key not in stable:
                        del(stable[name])
                        removed = True
                        break
                    end
                elif not key.startswith("__class__"):
                    del(stable[name])
                    removed = True
                    break
                end
            end
        end
    end
    return stable
end

function infer_function_returns(functions, classes, parameter_types, global_types, memo=None):
    # Least-fixed-point over the 3-level lattice None < concrete < Any. Start at
    # bottom (None) so a not-yet-resolved recursive call is the merge identity
    # rather than Any; otherwise merge(Bool, Any) = Any poisoned recursive
    # Bool/Float returns (e.g. is_even printed 1 instead of True). Iterate until
    # stable; monotonic widening bounds it by 2*len(names).
    # Bodies see the same global types as emit_function (minus locals and
    # parameters that shadow them), so a function returning a value read from
    # a global IntArray or constant infers Int instead of Any.
    result = {}
    for class_name in classes.keys():
        result["__class__" + class_name] = "Instance:" + class_name
    end
    names = functions.keys()
    for name in names:
        result[name] = "None"
    end
    stable = {}
    if memo != None:
        stable = reusable_returns(functions, parameter_types, global_types, memo)
        for name in stable.keys():
            result[name] = memo["result"][name]
        end
    end
    call populate_inherited_returns(classes, functions, result)
    max_iterations = len(names) * 2 + 4
    iteration = 0
    changed = True
    local_names = {}
    previous_inputs = {}
    while changed and iteration < max_iterations:
        changed = False
        for name in names:
            declaration = functions[name]
            # Lexical locals do not depend on the return-type fixed point.
            # Cache keys on the first visit, retaining collect_variables scan
            # order and its initial hidden-loop annotations. Final scope IDs
            # are still collected independently by analyze_function.
            # Stabilní funkce (memo) se neprochází: anotace collect_variables
            # už nese z prvního volání.
            if name in stable:
                previous_inputs[name] = memo["inputs"][name]
                continue
            end
            if name not in local_names:
                locals = {}
                call collect_variables(declaration["body"], locals)
                local_names[name] = locals.keys()
            end
            if name in previous_inputs:
                if return_dependency_values_unchanged(previous_inputs[name], result):
                    continue
                end
            end
            # Record actual return-type value reads before updating this
            # function's result. A recursive result change invalidates its own
            # next visit; inherited aliases are checked after each full round.
            observed = {}
            result["@return.inputs"] = observed
            types = Dictionary(global_types)
            for local_name in local_names[name]:
                if local_name in types:
                    del(types[local_name])
                end
            end
            parameter_index = 0
            for parameter in declaration["parameters"]:
                types[parameter] = parameter_types[name][parameter_index]
                parameter_index += 1
            end
            # Match emit_function: self remains an instance even when call-site
            # specialization is disabled. Method chains must retain the return
            # type of another method or of self.
            if "class_name" in declaration and len(declaration["parameters"]) > 0:
                if declaration["parameters"][0] == "self":
                    types["self"] = "Instance:" + declaration["class_name"]
                end
            end
            call collect_types_stable(declaration["body"], types, result)
            inferred = returned_type(declaration["body"], types, result)
            del(result["@return.inputs"])
            previous_inputs[name] = observed
            if inferred != result[name]:
                result[name] = inferred
                changed = True
            end
        end
        call populate_inherited_returns(classes, functions, result)
        iteration += 1
    end
    if memo != None:
        memo["result"] = Dictionary(result)
        memo["inputs"] = previous_inputs
        memo["parameters"] = parameter_types
        memo["globals"] = Dictionary(global_types)
        memo["converged"] = not changed
        locals_by_name = {}
        for name in local_names.keys():
            locals_by_name[name] = set(local_names[name])
        end
        for parameter_owner in names:
            if parameter_owner not in locals_by_name:
                # Stabilní funkce: lokální jména (s parametry) z minulého memo.
                locals_by_name[parameter_owner] = set(memo["locals"][parameter_owner])
            end
            for parameter in functions[parameter_owner]["parameters"]:
                locals_by_name[parameter_owner].add(parameter)
            end
        end
        memo["locals"] = locals_by_name
        if "strings" not in memo:
            memo["strings"] = {}
        end
    end
    return result
end


# Přiřazení do jména globálu uvnitř funkce bez deklarace global by tiše
# vytvořilo lokální proměnnou a globál by se nezměnil.
function find_global_assignments(statements, globals, skipped, found):
    for statement in statements:
        kind = statement["kind"]
        if kind == "assign":
            target = statement["target"]
            if target["kind"] == "name":
                assigned = target["name"]
                if assigned in globals and assigned not in skipped and not assigned.startswith("@"):
                    found.append(statement)
                end
            end
        elif kind == "if":
            for branch in statement["branches"]:
                call find_global_assignments(branch[1], globals, skipped, found)
            end
            call find_global_assignments(statement["otherwise"], globals, skipped, found)
        elif kind == "while" or kind == "loop" or kind == "unsafe" or kind == "for":
            call find_global_assignments(statement["body"], globals, skipped, found)
        elif kind == "safe" or kind == "try":
            call find_global_assignments(statement["body"], globals, skipped, found)
            call find_global_assignments(statement["otherwise"], globals, skipped, found)
        end
    end
end

# Prefix modulu funkce: globály importovaného modulu mají jména
# "@lsl_module_N@jméno", jeho lokální proměnné prefix nemají.
function module_prefix_of(name):
    text = String(name)
    if text.startswith("@lsl_module_"):
        rest = text[1:len(text)]
        return text[0:rest.find("@") + 2]
    end
    return ""
end

# Globály podle prefixu modulu (bez prefixu), spočítané jednou pro jednotku;
# globály se po vytvoření jednotky nemění. Dřív se pro každou funkci znovu
# procházely všechny globály celého programu (O(funkce × globály)).
function module_globals(unit, prefix):
    if "module_globals" not in unit:
        groups = {}
        for variable in unit["variables"].keys():
            text = String(variable)
            group = module_prefix_of(text)
            if group not in groups:
                groups[group] = {}
            end
            groups[group][text[len(group):len(text)]] = True
        end
        unit["module_globals"] = groups
    end
    return unit["module_globals"].get(prefix, {})
end

function check_global_shadowing(unit, declaration):
    skipped = {}
    for parameter in declaration["parameters"]:
        skipped[parameter] = True
    end
    prefix = module_prefix_of(declaration["name"])
    # Vestavěná standardní knihovna sdílí jména se vstupním modulem.
    if prefix == "" and declaration.get("path", unit["path"]) != unit["path"]:
        return
    end
    globals = module_globals(unit, prefix)
    for declared in declaration.get("globals", []):
        skipped[String(declared)[len(prefix):len(String(declared))]] = True
    end
    found = []
    call find_global_assignments(declaration["body"], globals, skipped, found)
    reported = {}
    for statement in found:
        assigned = statement["target"]["name"]
        if assigned in reported:
            continue
        end
        reported[assigned] = True
        width = max(1, statement["target"]["end_column"] - statement["target"]["column"])
        details = context(unit["path"], unit["source"], statement["target"])
        call diagnostics.warn(details["path"], statement["target"]["line"], statement["target"]["column"], width, details["source"], "W2004", "assignment to '" + assigned + "' inside a function creates a local variable; the global '" + assigned + "' is not changed", "write global " + assigned + " at the start of the function to change the global, or use a different local name")
    end
end

# global x ve funkci: proměnná musí existovat na úrovni modulu.
function check_declared_globals(unit, declaration):
    for declared in declaration.get("globals", []):
        if declared not in unit["variables"]:
            shown = String(declared).split("@")[-1]
            width = max(1, declaration["end_column"] - declaration["column"])
            details = context(unit["path"], unit["source"], declaration)
            call diagnostics.fail(details["path"], declaration["line"], declaration["column"], width, details["source"], "E2005", "global '" + shown + "' has no module-level variable", "assign " + shown + " at module level before using global " + shown)
        end
    end
end

# Globál zapisovaný z funkce může mít libovolný typ; slot musí být Any.
function widen_written_globals(types, written):
    for name in written.keys():
        if name in types:
            types[name] = "Any"
        end
    end
end

# Lokální jména mají stabilní pořadová ID; rozložení zásobníku určí backend.
function analyze_function(unit, declaration):
    name = declaration["name"]
    call check_declared_globals(unit, declaration)
    call check_global_shadowing(unit, declaration)
    variables = {}
    for parameter in declaration["parameters"]:
        variables[parameter] = len(variables) + 1
    end
    call collect_variables(declaration["body"], variables)
    for declared in declaration.get("globals", []):
        if declared in variables:
            del(variables[declared])
        end
    end
    global_reads = flow.check(unit["path"], unit["source"], declaration["body"], variables, declaration["parameters"], constant_truth_expression, constant_if_body, unit["noreturn"], unit["variables"])
    # The Dictionary constructor preserves insertion order and value identity,
    # without allocating a key list and performing one lookup per global.
    types = Dictionary(unit["types"])
    # Assigned locals and parameters lexically shadow same-named globals. Do not
    # merge their type flow with an unrelated global declaration.
    for local_name in variables.keys():
        if local_name in types:
            del(types[local_name])
        end
    end
    parameter_index = 0
    for parameter in declaration["parameters"]:
        types[parameter] = unit["function_parameters"][name][parameter_index]
        parameter_index += 1
    end
    if "class_name" in declaration:
        if len(declaration["parameters"]) > 0:
            if declaration["parameters"][0] == "self":
                types["self"] = "Instance:" + declaration["class_name"]
            end
        end
        parent_name = class_parent_name(unit["classes"], declaration["class_name"])
        if parent_name != "":
            types["origin"] = "Class:" + parent_name
        end
    end
    call collect_types_stable(declaration["body"], types, unit["function_returns"])
    return {"variables": variables, "types": types, "global_reads": global_reads}
end

# ASCII compiler directives are matched in UTF-8 byte space. String indexing
# counts Unicode code points and rescans the prefix, making an absent directive
# quadratic on generated multi-megabyte source files.
function source_has_directive(source, directive):
    length = __lsl_text_byte_length(source)
    width = __lsl_text_byte_length(directive)
    if width == 0:
        return True
    end
    first = __lsl_text_byte(directive, 0)
    offset = 0
    while offset + width <= length:
        if __lsl_text_byte(source, offset) == first:
            index = 1
            while index < width and __lsl_text_byte(source, offset + index) == __lsl_text_byte(directive, index):
                index += 1
            end
            if index == width:
                return True
            end
        end
        offset += 1
    end
    return False
end

# Výstup je společný kontrakt frontendu a backendu, bez registrů a bytových offsetů.
function analyze(path, source, program, internal_abi, lazy_functions=None):
    if lazy_functions == None:
        lazy_functions = {}
    end
    lines = source
    call declarations.lower(program, path, source)
    classes = class_table(path, lines, program)
    call validate_class_hierarchy(path, lines, classes)
    functions = function_table(path, lines, program)
    noreturn = flow.noreturn_functions(functions)
    parameter_types = dynamic_parameter_types(functions)
    # Runtime napsaný v LSL pracuje jen se surovými slovy: parametry jsou Int.
    RUNTIME_SOURCE[0] = String(source).startswith("# lsl: runtime" + chr(10))
    if RUNTIME_SOURCE[0]:
        for runtime_function in parameter_types.keys():
            parameter_types[runtime_function] = ["Int" for runtime_parameter in parameter_types[runtime_function]]
        end
    end
    return_memo = {}
    function_returns = infer_function_returns(functions, classes, parameter_types, {}, return_memo)
    main_variables = {}
    call collect_variables(program, main_variables)
    main_reads = flow.check(path, source, program, main_variables, [], constant_truth_expression, constant_if_body, noreturn, main_variables, True)
    # A called function may delete a global, including through a callback.
    # Only such bindings need main-thread guards and repeated init stores;
    # ordinary proved globals keep their existing hot path.
    deleted = {}
    for name in functions.keys():
        # Funkce dynamické knihovny (lazy) mažou jen položky slovníků, nikdy
        # jména: průchod jejich těly by stál ~12 ms každého překladu.
        if name not in lazy_functions:
            call flow.deleted_names(functions[name]["body"], deleted)
        end
    end
    mutable_globals = {}
    guarded_main_reads = {}
    for name in main_variables.keys():
        if name in deleted:
            mutable_globals[name] = True
            if name in main_reads:
                guarded_main_reads[name] = main_reads[name]
            end
        end
    end
    written_globals = {}
    for function_name in functions.keys():
        for declared in functions[function_name].get("globals", []):
            written_globals[declared] = True
        end
    end
    main_types = {}
    call collect_types_stable(program, main_types, function_returns)
    call widen_written_globals(main_types, written_globals)
    # Global types and return types depend on each other; one more round with
    # the globals visible resolves returns that read global state.
    function_returns = infer_function_returns(functions, classes, parameter_types, main_types, return_memo)
    main_types = {}
    call collect_types_stable(program, main_types, function_returns)
    call widen_written_globals(main_types, written_globals)
    if not internal_abi and has_specialization_candidate(functions) and not program_blocks_specialization(program):
        # Direct-call observations propagate parameter types through helper
        # chains. Escaping callbacks retain their dynamic ABI.
        parameter_types = infer_function_parameters(program, functions, function_returns, main_types)
        function_returns = infer_function_returns(functions, classes, parameter_types, main_types, return_memo)
        main_types = {}
        call collect_types_stable(program, main_types, function_returns)
        call widen_written_globals(main_types, written_globals)
    end
    # Runtime: i globály jsou surová slova (bitové operace bez pomocných funkcí).
    if RUNTIME_SOURCE[0]:
        for runtime_global in main_variables.keys():
            main_types[runtime_global] = "Int"
        end
    end
    unit = {"path": path, "source": source, "program": program, "internal_abi": internal_abi, "unchecked_intarray": source_has_directive(source, "# lsl: unchecked-intarray"), "classes": classes, "functions": functions, "noreturn": noreturn, "function_parameters": parameter_types, "function_returns": function_returns, "variables": main_variables, "types": main_types, "global_reads": guarded_main_reads, "mutable_globals": mutable_globals, "function_scopes": {}}
    unit["lazy_functions"] = lazy_functions
    scopes = unit["function_scopes"]
    for name in functions.keys():
        if name not in lazy_functions:
            scopes[name] = analyze_function(unit, functions[name])
        end
    end
    return unit
end

# Rozsah funkce knihovny odložené v analyze (první použití).
function ensure_function_scope(unit, name):
    scopes = unit["function_scopes"]
    if name not in scopes:
        scopes[name] = analyze_function(unit, unit["functions"][name])
    end
    return scopes[name]
end

# Způsobilost raw Int stromů je společná politika; počet potřebných registrů řeší backend.
function integer_leaf(state, syntax):
    kind = syntax["kind"]
    if kind == "literal":
        if syntax["literal_kind"] == "number":
            value = syntax["value"]
            return value.find(".") < 0 and value.find("e") < 0 and value.find("E") < 0
        end
        return False
    elif kind == "name":
        name = syntax["name"]
        return name in state["variables"] or name in state["global_variables"]
    end
    return False
end


function fast_integer_index(state, syntax):
    if infer_expression_type(syntax, state["types"], state["function_returns"]) != "Int":
        return False
    end
    if integer_leaf(state, syntax):
        return True
    end
    if syntax["kind"] == "binary":
        operator = syntax["operator"]
        if operator == "+" or operator == "-" or operator == "*":
            return fast_integer_index(state, syntax["left"]) and fast_integer_index(state, syntax["right"])
        end
    end
    return False
end


function fast_integer_value(state, syntax):
    if integer_leaf(state, syntax):
        return True
    end
    if syntax["kind"] == "index":
        target_type = infer_expression_type(syntax["target"], state["types"], state["function_returns"])
        return target_type == "IntArray" and fast_integer_index(state, syntax["index"])
    elif syntax["kind"] == "binary":
        operator = syntax["operator"]
        if operator == "+" or operator == "-" or operator == "*" or operator == "&" or operator == "|" or operator == "~":
            return fast_integer_value(state, syntax["left"]) and fast_integer_value(state, syntax["right"])
        end
    elif syntax["kind"] == "unary" and syntax["operator"] == "~":
        return fast_integer_value(state, syntax["operand"])
    end
    return False
end


function pure_integer_expression(state, syntax):
    kind = syntax["kind"]
    if kind == "literal":
        return syntax["literal_kind"] == "number" and syntax["value"].find(".") < 0 and syntax["value"].find("e") < 0 and syntax["value"].find("E") < 0
    elif kind == "name":
        return integer_leaf(state, syntax) and infer_expression_type(syntax, state["types"], state["function_returns"]) == "Int"
    elif kind == "index":
        target = syntax["target"]
        return state.get("unchecked_intarray", False) and target["kind"] == "name" and integer_leaf(state, target) and infer_expression_type(target, state["types"], state["function_returns"]) == "IntArray" and pure_integer_expression(state, syntax["index"])
    elif kind == "unary":
        return syntax["operator"] in ["-", "~"] and pure_integer_expression(state, syntax["operand"])
    elif kind == "binary":
        operator = syntax["operator"]
        if operator not in ["+", "-", "*", "&", "|", "~", "<<", ">>"] or not pure_integer_expression(state, syntax["left"]):
            return False
        end
        right = syntax["right"]
        if operator == "<<" or operator == ">>":
            if right["kind"] == "literal" and pure_integer_expression(state, right):
                count = integer_literal(right)
                return count >= 0 and count <= 63
            elif right["kind"] == "unary" and right["operand"]["kind"] == "literal" and pure_integer_expression(state, right["operand"]):
                return False
            end
        end
        return pure_integer_expression(state, right)
    end
    return False
end
