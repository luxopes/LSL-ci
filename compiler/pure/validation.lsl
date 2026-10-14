# Sémantická validace a příprava volání. Neobsahuje strojové instrukce ani ABI offsety.
# Chyby zachytitelné ve funkci/safe zůstávají pokyny pro runtime na původním místě.

load semantic

HELP_FAMILY = ["__lsl_help_text", "__lsl_help", "__lsl_about_table", "__lsl_comment_header", "__lsl_library_about", "__lsl_about_text"]
LAZY_RUNTIME = ["__lsl_rang_list", "__lsl_dynamic_find"]

function help_family(name):
    return name in HELP_FAMILY
end

function lazy_runtime(name):
    return name in LAZY_RUNTIME
end

# Klíč zahrnuje lexikální funkci i původní zdroj; syntetické helpery dědí jeho polohu.
function source_key(state, syntax):
    return state["scope_name"] + ":" + syntax.get("path", state["path"]) + ":" + String(syntax.get("line", 1)) + ":" + String(syntax.get("column", 1))
end

function argument_key(state, syntax, declaration, skip):
    return source_key(state, syntax) + ":" + declaration["name"] + ":" + String(skip)
end

function record_error(state, syntax, rule, error_type, message):
    errors = state["validation_errors"]
    if rule not in errors:
        errors[rule] = {}
    end
    errors[rule][source_key(state, syntax)] = [error_type, message]
end

function error_for(state, syntax, rule):
    if "validation_errors" not in state:
        return None
    end
    errors = state["validation_errors"]
    if rule not in errors:
        return None
    end
    return errors[rule].get(source_key(state, syntax), None)
end

# Backend používá hotové pořadí argumentů, žádné nové bindování ani diagnostiku.
function arguments(state, syntax, declaration, skip):
    if len(syntax.get("argument_names", [])) == 0 and "defaults" not in declaration:
        return syntax["arguments"]
    end
    return state["prepared_arguments"][argument_key(state, syntax, declaration, skip)]
end

function condition(state, syntax):
    constant = semantic.constant_truth_expression(syntax)
    if constant[0]:
        return
    end
    call expression(state, syntax)
end

function shift(state, syntax, left, right):
    count = semantic.constant_int_expression(right)
    if count[0] and count[1] < 0:
        if state["error_label"] != "":
            call record_error(state, syntax, "negative_shift", "ValueError", "negative shift count")
            return
        end
        call semantic.unsupported(state["path"], state["lines"], syntax, "negative shift count", "use a shift count of 0 or more")
    end
    call expression(state, left)
    call expression(state, right)
end

function bitwise(state, syntax):
    left = bit_operand_node(state, syntax["left"])
    right = bit_operand_node(state, syntax["right"])
    if syntax["operator"] == "<<" or syntax["operator"] == ">>":
        call shift(state, syntax, left, right)
    else:
        call expression(state, left)
        call expression(state, right)
    end
end

function dictionary_key(state, syntax):
    key_type = semantic.infer_expression_type(syntax, state["types"], state["function_returns"])
    if key_type == "List" or key_type == "Tuple" or key_type == "RealArray" or key_type == "IntArray" or key_type == "FloatArray" or key_type == "ByteArray" or key_type == "Dictionary" or key_type == "Set" or key_type.startswith("Class:") or key_type.startswith("Instance:"):
        if state["error_label"] != "":
            call record_error(state, syntax, "dictionary_key", "TypeError", "mutable or collection value cannot be a Dictionary key")
            return
        end
        call semantic.unsupported(state["path"], state["lines"], syntax, "mutable or collection value cannot be a Dictionary key", "use String, Int, Bool, None, Float, or Function keys")
    end
end

function checked_index_node(state, syntax):
    if syntax != None and semantic.infer_expression_type(syntax, state["types"], state["function_returns"]) == "Any" and not state["internal_abi"] and not state.get("current_internal_function", False):
        return {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_checked_index"}, "arguments": [syntax]}
    end
    return syntax
end

function checked_string_node(state, syntax):
    value_type = semantic.infer_expression_type(syntax, state["types"], state["function_returns"])
    if value_type != "String" and value_type != "Any":
        if state["error_label"] != "":
            call record_error(state, syntax, "string_value", "TypeError", "value must be a String")
            return syntax
        end
        call semantic.unsupported(state["path"], state["lines"], syntax, "value must be a String", "convert the value with String(...)")
    end
    if value_type == "Any" and not state["internal_abi"] and not state.get("current_internal_function", False):
        return {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_require_string_value"}, "arguments": [syntax]}
    end
    return syntax
end

function checked_list_node(state, syntax):
    value_type = semantic.infer_expression_type(syntax, state["types"], state["function_returns"])
    if value_type != "List" and value_type != "Any":
        if state["error_label"] != "":
            call record_error(state, syntax, "list_value", "TypeError", "value must be a List")
            return syntax
        end
        call semantic.unsupported(state["path"], state["lines"], syntax, "value must be a List", "pass a List value")
    end
    if value_type == "Any" and not state["internal_abi"] and not state.get("current_internal_function", False):
        return {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_require_list"}, "arguments": [syntax]}
    end
    return syntax
end

function checked_byte_sequence_node(state, syntax):
    value_type = semantic.infer_expression_type(syntax, state["types"], state["function_returns"])
    if value_type != "ByteArray" and value_type != "List" and value_type != "Any":
        if state["error_label"] != "":
            call record_error(state, syntax, "byte_sequence", "TypeError", "binary data must be a ByteArray or List")
            return syntax
        end
        call semantic.unsupported(state["path"], state["lines"], syntax, "binary data must be a ByteArray or List", "pass a ByteArray value")
    end
    if value_type == "Any" and not state["internal_abi"] and not state.get("current_internal_function", False):
        return {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_require_byte_sequence"}, "arguments": [syntax]}
    end
    return syntax
end

function checked_int(state, syntax, purpose):
    value_type = semantic.infer_expression_type(syntax, state["types"], state["function_returns"])
    if value_type != "Int" and value_type != "Bool" and value_type != "Any":
        if state["error_label"] != "":
            call record_error(state, syntax, "integer_value", "TypeError", purpose + " must be an Int")
            return
        end
        call semantic.unsupported(state["path"], state["lines"], syntax, purpose + " must be an Int", "convert the value with Int(...)")
    end
    call expression(state, syntax)
end

function bit_operand_node(state, syntax):
    operand_type = semantic.infer_expression_type(syntax, state["types"], state["function_returns"])
    if operand_type == "Int" or operand_type == "Bool":
        return syntax
    end
    if operand_type != "Any":
        if state["error_label"] != "":
            call record_error(state, syntax, "bit_operand", "TypeError", "bitwise operators require Int operands, got " + operand_type)
            return syntax
        end
        call semantic.unsupported(state["path"], state["lines"], syntax, "bitwise operators require Int operands, got " + operand_type, "convert the value with Int(...) first")
    end
    coerce = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
    coerce["target"] = {"kind": "name", "name": "__lsl_bit_operand"}
    coerce["arguments"] = [syntax]
    return coerce
end

function bind_arguments(state, syntax, declaration, skip):
    parameters = declaration["parameters"]
    supplied = syntax["arguments"]
    names = syntax.get("argument_names", [])
    if len(names) == 0 and "defaults" not in declaration:
        return supplied
    end
    values = []
    for index in rang(skip, len(parameters)):
        values.append(None)
    end
    for index in rang(len(supplied)):
        position = index
        if len(names) > 0 and names[index] != "":
            position = -1
            for parameter_index in rang(skip, len(parameters)):
                if parameters[parameter_index] == names[index]:
                    position = parameter_index - skip
                end
            end
        end
        if position < 0 or position >= len(values):
            if state["error_label"] != "":
                call record_error(state, syntax, "arguments", "TypeError", "unknown keyword or too many arguments")
                return None
            end
            call semantic.unsupported(state["path"], state["lines"], syntax, "unknown keyword or too many arguments: " + String(names) + " for " + String(parameters), "use the function's declared parameters")
        elif values[position] != None:
            if state["error_label"] != "":
                call record_error(state, syntax, "arguments", "TypeError", "multiple values for one argument")
                return None
            end
            call semantic.unsupported(state["path"], state["lines"], syntax, "multiple values for one argument", "pass each parameter only once")
        end
        values[position] = supplied[index]
    end
    defaults = declaration.get("defaults", [])
    for index in rang(len(values)):
        if values[index] == None:
            if len(defaults) == 0 or defaults[index + skip] == None:
                if state["error_label"] != "":
                    call record_error(state, syntax, "arguments", "TypeError", "missing required argument: " + parameters[index + skip])
                    return None
                end
                call semantic.unsupported(state["path"], state["lines"], syntax, "missing required argument: " + parameters[index + skip], "supply the required argument")
            end
            values[index] = defaults[index + skip]
        end
    end
    state["prepared_arguments"][argument_key(state, syntax, declaration, skip)] = values
    return values
end

# Název typu pro hlášku (třída nebo instance bez vnitřního jména).
function shown_type(value_type):
    text = String(value_type)
    if text.startswith("Class:"):
        return "Class"
    elif text.startswith("Instance:"):
        return "Instance"
    end
    return text
end

function builtin_arities():
    builtin_arity = {"Bool": 1, "Int": 1, "Float": 1, "String": 1, "List": 1, "Tuple": 1, "RealArray": 1, "Dictionary": 1, "len": 1, "chr": 1, "ord": 1, "abs": 1, "sqrt": 1, "sum": 1, "float_zeros": 1, "float_fill": 2, "float_sum": 1, "float_dot": 2, "float_axpy": 3, "float_matmul": 5, "type": 1, "exit": 1, "input": 1, "readfile": 1, "readbytes": 1, "__lsl_getenv": 1, "mkdir": 1, "unlink": 1, "rmdir": 1, "exists": 1, "gc": 0, "clock": 0, "arg_count": 0, "last_error": 0, "executable_path": 0, "help": 0, "run": 2, "run_clean": 2, "capture": 2, "capture_clean": 2, "capture_stream": 3, "capture_stream_clean": 3, "capture_input": 3, "capture_input_clean": 3, "capture_input_stream": 4, "capture_input_stream_clean": 4, "__lsl_capture_input_timeout": 4, "__lsl_run_timeout": 3, "capture_status": 0, "capture_stderr": 0, "writefile": 2, "appendfile": 2, "writebytes": 2, "check": 2, "native_open": 1, "native_size": 1, "native_u64": 2, "native_name_equal": 3, "native_function": 2, "native_call": 2, "native_close": 1, "__lsl_test_small_tables": 0, "__lsl_test_fd_fault": 1, "__lsl_object_table_mask": 0, "__lsl_intern_table_mask": 0, "__lsl_wall_time": 0, "__lsl_sleep": 1, "__lsl_isatty": 1, "__lsl_stdin_eof": 0, "__lsl_run": 2, "__lsl_run_clean": 2, "__lsl_capture": 2, "__lsl_capture_clean": 2, "__lsl_fd_open": 2, "__lsl_fd_read": 3, "__lsl_fd_write": 3, "__lsl_fd_seek": 2, "__lsl_fd_close": 1, "__lsl_fd_socket": 2, "__lsl_fd_connect": 3, "__lsl_checked_index": 1, "__lsl_int_zeros": 1, "__lsl_byte_zeros": 1, "__lsl_raster_pack": 5, "__lsl_raster_copy": 5, "__lsl_raster_fill": 4, "__lsl_fd_ioctl": 3, "__lsl_fd_mmap": 3, "__lsl_mem_pack": 5, "__lsl_data_address": 1, "__lsl_syscall": 5, "__lsl_mem_unpack": 4, "__lsl_text_from_bytes": 3, "__lsl_byte_copy": 5, "__lsl_text_byte": 2, "__lsl_text_byte_length": 1, "__lsl_text_piece": 3, "__lsl_text_scan_digits": 2, "__lsl_text_digits": 3, "__lsl_text_split_byte": 2, "__lsl_floatarray_bytes": 1, "__lsl_floatarray_from_bytes": 1, "atomic_add": 3, "atomic_xchg": 3, "atomic_cas": 4, "atomic_pause": 0, "thread_spawn": 1, "thread_join": 1, "cpu_count": 0, "popcount": 1, "trailing_zeros": 1}
    builtin_arity["__lsl_mkdir_private"] = 1
    builtin_arity["__lsl_entry_source"] = 0
    builtin_arity["monotonic"] = 0
    builtin_arity["__lsl_monotonic"] = 0
    builtin_arity["__lsl_fd_snapshot"] = 3
    builtin_arity["arg"] = 1
    builtin_arity["__lsl_address"] = 1
    builtin_arity["__lsl_qbe_label"] = 1
    builtin_arity["__lsl_qbe_jump"] = 1
    builtin_arity["__lsl_qbe_branch"] = 3
    builtin_arity["__lsl_qbe_alloc"] = 1
    builtin_arity["__lsl_qbe_copy"] = 3
    builtin_arity["__lsl_qbe_zero"] = 2
    builtin_arity["__lsl_qbe_raw_int"] = 1
    # Runtime LSL (# lsl: runtime): adresa symbolu a surová desetinná čísla.
    builtin_arity["__lsl_symbol"] = 1
    for operation in ["fadd","fsub","fmul","fdiv","feq","fne","flt","fle","fgt","fge"]:
        builtin_arity["__lsl_raw_"+operation] = 2
    end
    for operation in ["fitof","fftoi","fneg"]:
        builtin_arity["__lsl_raw_"+operation] = 1
    end
    # Až deset argumentů: funkce Win32 jako CreateProcessW (runtime/os_windows.lsl).
    for count in rang(11):
        builtin_arity["__lsl_qbe_call"+String(count)] = count + 1
        builtin_arity["__lsl_qbe_fcall"+String(count)] = count + 1
    end
    builtin_arity["__lsl_qbe_loadf32"] = 1
    builtin_arity["__lsl_qbe_storef32"] = 2
    builtin_arity["__lsl_qbe_f32"] = 1
    builtin_arity["__lsl_qbe_uitof"] = 1
    builtin_arity["__lsl_qbe_ftoui"] = 1
    for operation in ["fadd","fsub","fmul","fdiv","feq","fne","flt","fle","fgt","fge"]:
        builtin_arity["__lsl_qbe_"+operation] = 2
    end
    for operation in ["s8","s16","s32","u8","u16","u32"]:
        builtin_arity["__lsl_qbe_"+operation] = 1
    end
    for operation in ["lshr","shl","ashr","udiv","urem","idiv","irem","ult","ule"]:
        builtin_arity["__lsl_qbe_"+operation] = 2
    end
    for width in ["8","16","32","64"]:
        builtin_arity["__lsl_qbe_load"+width] = 1
        builtin_arity["__lsl_qbe_store"+width] = 2
    end
    builtin_arity["__lsl_box_bool"] = 1
    builtin_arity["__lsl_box_function"] = 1
    builtin_arity["__lsl_box_int"] = 1
    builtin_arity["__lsl_box_none"] = 0
    builtin_arity["__lsl_ffloordiv"] = 2
    builtin_arity["__lsl_float_accumulate"] = 2
    builtin_arity["__lsl_float_bits"] = 1
    builtin_arity["__lsl_float_candidate_bits"] = 3
    builtin_arity["__lsl_float_from_decimal"] = 2
    builtin_arity["__lsl_decimal_compare"] = 4
    builtin_arity["__lsl_decimal_digits_compare"] = 5
    builtin_arity["__lsl_float_nearer_upper"] = 4
    builtin_arity["__lsl_float_from_bits"] = 1
    builtin_arity["__lsl_float_from_int"] = 1
    builtin_arity["__lsl_float_string"] = 1
    builtin_arity["__lsl_float_to_int"] = 1
    builtin_arity["__lsl_floordiv_dyn"] = 2
    builtin_arity["__lsl_fmod"] = 2
    builtin_arity["__lsl_is_heap"] = 1
    builtin_arity["__lsl_mod_dyn"] = 2
    builtin_arity["__lsl_parse_literal_int"] = 1
    builtin_arity["__lsl_pop_last"] = 1
    builtin_arity["__lsl_public_floordiv_dyn"] = 2
    builtin_arity["__lsl_public_mod_dyn"] = 2
    builtin_arity["__lsl_raw_equal"] = 2
    builtin_arity["__lsl_raw_int"] = 1
    builtin_arity["__lsl_string_chars"] = 1
    builtin_arity["__lsl_type_code"] = 1
    builtin_arity["__lsl_typed_int"] = 1
    builtin_arity["__lsl_unbox_bool"] = 1
    builtin_arity["__lsl_unbox_int"] = 1
    builtin_arity["__lsl_syscall6"] = 7
    builtin_arity["sorted"] = 1
    builtin_arity["dedup"] = 1
    builtin_arity["__lsl_new_set"] = 0
    builtin_arity["__lsl_set_append"] = 2
    builtin_arity["__lsl_set_store"] = 3
    return builtin_arity
end

function expression(state, syntax):
    kind = syntax["kind"]
    if kind == "binary" or kind == "unary":
        constant_string = semantic.constant_string_expression(syntax)
        if constant_string[0]:
            return
        end
        constant_integer = semantic.constant_int_expression(syntax)
        if constant_integer[0]:
            return
        end
    elif kind == "compare":
        constant_truth = semantic.constant_truth_expression(syntax)
        if constant_truth[0]:
            return
        end
    end
    if kind == "literal":
        if syntax["literal_kind"] != "string" and syntax["literal_kind"] != "number" and syntax["value"] not in ["True", "False", "None"]:
            call semantic.unsupported(state["path"], state["lines"], syntax, "String is only valid directly inside print in this stage", "move the String to a print statement")
        end
    elif kind == "name":
        name = syntax["name"]
        if name in state["variables"] or name in state["global_variables"]:
            value = None
        elif name in state["functions"]:
            if "defaults" in state["functions"][name]:
                call semantic.unsupported(state["path"], state["lines"], syntax, "functions with defaults cannot be used as Function values yet", "wrap the call in a function with explicit parameters")
            end
            if lazy_runtime(name):
                state["lazy_used"][name] = True
            end
        else:
            if state["error_label"] != "":
                call record_error(state, syntax, "unknown_variable", "NameError", "unknown native variable: " + name)
                return
            end
            call semantic.unsupported(state["path"], state["lines"], syntax, "unknown native variable: " + name, "assign the variable before reading it")
        end
    elif kind == "comprehension":
        call semantic.collect_types(syntax["body"], state["types"], state["function_returns"])
        call statements(state, syntax["body"], "", "", "")
        call expression(state, syntax["result"])
    elif kind == "real_array":
        array_values = {"kind": "list", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "items": syntax["items"]}
        array_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_real_array"}, "arguments": [array_values]}
        call expression(state, array_call)
    elif kind == "list" or kind == "tuple":
        for item in syntax["items"]:
            call expression(state, item)
        end
    elif kind == "dictionary":
        for entry in syntax["entries"]:
            call expression(state, entry[0])
            call dictionary_key(state, entry[0])
            call expression(state, entry[1])
        end
    elif kind == "member":
        target_type = semantic.infer_expression_type(syntax["target"], state["types"], state["function_returns"])
        if target_type.startswith("Class:") or target_type.startswith("Instance:") or target_type == "Dictionary":
            call expression(state, syntax["target"])
        else:
            if state["error_label"] != "":
                call record_error(state, syntax, "member_value", "AttributeError", "member value requires a class or instance")
                return
            end
            call semantic.unsupported(state["path"], state["lines"], syntax, "member value requires a class or instance", "access a declared class field")
        end
    elif kind == "slice":
        target_slice_type = semantic.infer_expression_type(syntax["target"], state["types"], state["function_returns"])
        if target_slice_type != "Any" and not semantic.is_sequence_type(target_slice_type):
            if state["error_label"] != "":
                call record_error(state, syntax, "slice_target", "TypeError", "value of type " + target_slice_type + " does not support slicing")
                return
            end
            call semantic.unsupported(state["path"], state["lines"], syntax, "value of type " + target_slice_type + " does not support slicing", "slice a String, collection, or typed array")
        end
        for slice_bound in [syntax["start"], syntax["stop"], syntax.get("step", None)]:
            if slice_bound != None:
                bound_type = semantic.infer_expression_type(slice_bound, state["types"], state["function_returns"])
                if bound_type != "Int" and bound_type != "Bool" and bound_type != "Any":
                    if state["error_label"] != "":
                        call record_error(state, slice_bound, "slice_bound", "TypeError", "slice bounds must be Int")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], slice_bound, "slice bounds must be Int", "convert the bound with Int(...)")
                end
            end
        end
        if syntax.get("step", None) != None or target_slice_type == "ByteArray" or (target_slice_type == "Any" and not state["internal_abi"]):
            zero_literal = {"kind": "literal", "literal_kind": "number", "value": "0", "integer_value": 0, "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
            one_literal = {"kind": "literal", "literal_kind": "number", "value": "1", "integer_value": 1, "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
            true_literal = {"kind": "literal", "literal_kind": "name", "value": "True", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
            false_literal = {"kind": "literal", "literal_kind": "name", "value": "False", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
            start_arg = zero_literal
            has_start = false_literal
            if syntax["start"] != None:
                start_arg = checked_index_node(state, syntax["start"])
                has_start = true_literal
            end
            stop_arg = zero_literal
            has_stop = false_literal
            if syntax["stop"] != None:
                stop_arg = checked_index_node(state, syntax["stop"])
                has_stop = true_literal
            end
            step_arg = one_literal
            if syntax.get("step", None) != None:
                step_arg = checked_index_node(state, syntax["step"])
            end
            slice_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_slice3"}, "arguments": [syntax["target"], start_arg, has_start, stop_arg, has_stop, step_arg]}
            call expression(state, slice_call)
            target_slice_type = semantic.infer_expression_type(syntax["target"], state["types"], state["function_returns"])
            return
        end
        call expression(state, syntax["target"])
        if syntax["start"] == None:
            value = None
        else:
            call expression(state, syntax["start"])
        end
        if syntax["stop"] == None:
            value = None
        else:
            call expression(state, syntax["stop"])
        end
        target_slice_type = semantic.infer_expression_type(syntax["target"], state["types"], state["function_returns"])
    elif kind == "index":
        target_type = semantic.infer_expression_type(syntax["target"], state["types"], state["function_returns"])
        index_type = semantic.infer_expression_type(syntax["index"], state["types"], state["function_returns"])
        if target_type != "Any" and target_type != "Dictionary" and not semantic.is_sequence_type(target_type):
            if state["error_label"] != "":
                call record_error(state, syntax, "index_target", "TypeError", "value of type " + target_type + " is not indexable")
                return
            end
            call semantic.unsupported(state["path"], state["lines"], syntax, "value of type " + target_type + " is not indexable", "index a String, collection, typed array, or Dictionary")
        elif semantic.is_sequence_type(target_type) and index_type != "Int" and index_type != "Bool" and index_type != "Any":
            if state["error_label"] != "":
                call record_error(state, syntax["index"], "index_value", "TypeError", "sequence index must be Int, got " + shown_type(index_type))
                return
            end
            call semantic.unsupported(state["path"], state["lines"], syntax["index"], "sequence index must be Int, got " + shown_type(index_type), "convert the index with Int(...)")
        end
        call expression(state, syntax["target"])
        call expression(state, syntax["index"])
        if target_type == "Dictionary" or (target_type == "Any" and not state["internal_abi"]):
            call dictionary_key(state, syntax["index"])
        elif index_type == "Any":
            value = None
        end
    elif kind == "unary":
        if syntax["operator"] == "~":
            call expression(state, bit_operand_node(state, syntax["operand"]))
            return
        end
        operand_type = semantic.infer_expression_type(syntax["operand"], state["types"], state["function_returns"])
        if syntax["operator"] == "-" and not semantic.is_numeric_type(operand_type):
            if state["error_label"] != "":
                call record_error(state, syntax, "unary_numeric", "TypeError", "unary - requires a numeric operand")
                return
            end
            call semantic.unsupported(state["path"], state["lines"], syntax, "unary - requires a numeric operand", "pass an Int, Bool, or Float value")
        end
        call expression(state, syntax["operand"])
    elif kind == "binary":
        operator = syntax["operator"]
        expression_type = semantic.infer_expression_type(syntax, state["types"], state["function_returns"])
        binary_left_type = semantic.infer_expression_type(syntax["left"], state["types"], state["function_returns"])
        binary_right_type = semantic.infer_expression_type(syntax["right"], state["types"], state["function_returns"])
        if operator == "+":
            valid_add = binary_left_type == "Any" or binary_right_type == "Any" or (semantic.is_numeric_type(binary_left_type) and semantic.is_numeric_type(binary_right_type)) or (binary_left_type == "String" and binary_right_type == "String") or (binary_left_type == "List" and binary_right_type == "List")
            if not valid_add:
                if state["error_label"] != "":
                    call record_error(state, syntax, "add_operands", "TypeError", "+ requires two numbers, two Strings, or two Lists")
                    return
                end
                call semantic.unsupported(state["path"], state["lines"], syntax, "+ requires two numbers, two Strings, or two Lists", "use matching operand types or convert explicitly")
            end
        elif operator == "*":
            valid_multiply = binary_left_type == "Any" or binary_right_type == "Any" or (semantic.is_numeric_type(binary_left_type) and semantic.is_numeric_type(binary_right_type)) or (binary_left_type == "String" and (binary_right_type == "Int" or binary_right_type == "Bool")) or (binary_right_type == "String" and (binary_left_type == "Int" or binary_left_type == "Bool"))
            if not valid_multiply:
                if state["error_label"] != "":
                    call record_error(state, syntax, "multiply_operands", "TypeError", "* requires numeric operands or a String and Int")
                    return
                end
                call semantic.unsupported(state["path"], state["lines"], syntax, "* requires numeric operands or a String and Int", "use numeric values or String * Int")
            end
        elif operator == "-" or operator == "/" or operator == "//" or operator == "%":
            if not semantic.is_numeric_type(binary_left_type) or not semantic.is_numeric_type(binary_right_type):
                if state["error_label"] != "":
                    call record_error(state, syntax, "numeric_operands", "TypeError", "operator " + operator + " requires numeric operands")
                    return
                end
                call semantic.unsupported(state["path"], state["lines"], syntax, "operator " + operator + " requires numeric operands", "pass Int, Bool, or Float values")
            end
        elif operator == "^":
            valid_exponent = binary_right_type == "Int" or binary_right_type == "Bool" or binary_right_type == "Any"
            if not semantic.is_numeric_type(binary_left_type) or not valid_exponent:
                if state["error_label"] != "":
                    call record_error(state, syntax, "exponent_operands", "TypeError", "^ requires a numeric base and Int exponent")
                    return
                end
                call semantic.unsupported(state["path"], state["lines"], syntax, "^ requires a numeric base and Int exponent", "use an Int exponent such as x ^ 3")
            end
        end
        if (operator == "//" or operator == "%") and (expression_type == "Float" or expression_type == "Any"):
            floor_left_type = semantic.infer_expression_type(syntax["left"], state["types"], state["function_returns"])
            floor_right_type = semantic.infer_expression_type(syntax["right"], state["types"], state["function_returns"])
            floor_left_numeric = floor_left_type == "Int" or floor_left_type == "Bool" or floor_left_type == "Float" or floor_left_type == "Any"
            floor_right_numeric = floor_right_type == "Int" or floor_right_type == "Bool" or floor_right_type == "Float" or floor_right_type == "Any"
            if not floor_left_numeric or not floor_right_numeric:
                if state["error_label"] != "":
                    call record_error(state, syntax, "floor_operands", "TypeError", "operator " + operator + " requires numeric operands")
                    return
                end
                call semantic.unsupported(state["path"], state["lines"], syntax, "operator " + operator + " requires numeric operands", "pass Int, Bool, or Float values")
            end
            if operator == "%":
                floor_target = "__lsl_fmod"
                if expression_type == "Any":
                    floor_target = "__lsl_mod_dyn"
                    if not state["internal_abi"] and not state.get("current_internal_function", False):
                        floor_target = "__lsl_public_mod_dyn"
                    end
                end
            else:
                floor_target = "__lsl_ffloordiv"
                if expression_type == "Any":
                    floor_target = "__lsl_floordiv_dyn"
                    if not state["internal_abi"] and not state.get("current_internal_function", False):
                        floor_target = "__lsl_public_floordiv_dyn"
                    end
                end
            end
            floor_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": floor_target}, "arguments": [syntax["left"], syntax["right"]]}
            call expression(state, floor_call)
            return
        end
        if expression_type == "Float":
            if operator == "^":
                exponent_type = semantic.infer_expression_type(syntax["right"], state["types"], state["function_returns"])
                if exponent_type != "Int" and exponent_type != "Bool" and exponent_type != "Any":
                    if state["error_label"] != "":
                        call record_error(state, syntax, "float_exponent", "TypeError", "Float ^ requires an Int exponent")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "Float ^ requires an Int exponent", "use an Int exponent such as x ^ 3")
                end
                call expression(state, syntax["left"])
                call expression(state, syntax["right"])
                return
            end
            call expression(state, syntax["left"])
            call expression(state, syntax["right"])
            if operator == "+":
                value = None
            elif operator == "-":
                value = None
            elif operator == "*":
                value = None
            elif operator == "/":
                value = None
            else:
                call semantic.unsupported(state["path"], state["lines"], syntax, "unsupported Float operator " + operator, "use +, -, *, or /")
            end
            return
        elif operator == "+" and expression_type == "List":
            concat_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_list_concat"}, "arguments": [syntax["left"], syntax["right"]]}
            call expression(state, concat_call)
            return
        elif operator == "*" and expression_type == "String":
            left_type = semantic.infer_expression_type(syntax["left"], state["types"], state["function_returns"])
            if left_type == "String":
                repeat_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_str_repeat"}, "arguments": [syntax["left"], syntax["right"]]}
            else:
                repeat_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_str_repeat"}, "arguments": [syntax["right"], syntax["left"]]}
            end
            call expression(state, repeat_call)
            return
        elif operator == "+" and (expression_type == "String" or expression_type == "Any"):
            if expression_type == "Any" and not state["internal_abi"] and not state.get("current_internal_function", False):
                public_add_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_public_add"}, "arguments": [syntax["left"], syntax["right"]]}
                call expression(state, public_add_call)
                return
            end
            call expression(state, syntax["left"])
            call expression(state, syntax["right"])
            return
        elif (operator == "-" or operator == "*") and expression_type == "Any":
            if operator == "*" and not state["internal_abi"] and not state.get("current_internal_function", False):
                public_multiply_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_public_multiply"}, "arguments": [syntax["left"], syntax["right"]]}
                call expression(state, public_multiply_call)
                return
            end
            call expression(state, syntax["left"])
            call expression(state, syntax["right"])
            return
        elif operator == "^" and expression_type == "Any":
            any_exp_type = semantic.infer_expression_type(syntax["right"], state["types"], state["function_returns"])
            if any_exp_type != "Int" and any_exp_type != "Bool" and any_exp_type != "Any":
                if state["error_label"] != "":
                    call record_error(state, syntax, "int_exponent", "TypeError", "^ requires an Int exponent")
                    return
                end
                call semantic.unsupported(state["path"], state["lines"], syntax, "^ requires an Int exponent", "use an Int exponent such as x ^ 3")
            end
            call expression(state, syntax["left"])
            call expression(state, syntax["right"])
            return
        elif operator == "&" or operator == "|" or operator == "~" or operator == "<<" or operator == ">>":
            call bitwise(state, syntax)
            return
        elif operator == "and" or operator == "or":
            call expression(state, syntax["left"])
            call expression(state, syntax["right"])
            return
        end
        call expression(state, syntax["left"])
        call expression(state, syntax["right"])
        if operator not in ["+", "-", "*", "^", "//", "%", "and", "or"]:
            call semantic.unsupported(state["path"], state["lines"], syntax, "operator " + operator + " is not in the native scalar slice", "supported now: +, -, *, //, %, &, |, ~, <<, >>, comparisons, and/or")
        end
    elif kind == "call":
        target = syntax["target"]
        if target["kind"] == "name":
            if target["name"] == "help" or help_family(target["name"]):
                state["help_used"] = True
            end
            if lazy_runtime(target["name"]):
                state["lazy_used"][target["name"]] = True
            end
            if "argument_names" in syntax and target["name"] not in state["functions"] and target["name"] not in state["classes"]:
                if state["error_label"] != "":
                    call record_error(state, syntax, "call_keywords", "TypeError", "keyword arguments require a declared function or class")
                    return
                end
                call semantic.unsupported(state["path"], state["lines"], syntax, "keyword arguments require a declared function or class", "use positional arguments for builtins and Function values")
            end
            builtin_arity = state["builtin_arity"]
            if target["name"] == "help":
                if len(syntax["arguments"]) > 1:
                    if state["error_label"] != "":
                        call record_error(state, syntax, "help_arity", "TypeError", "builtin help expects zero or one argument")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "builtin help expects zero or one argument", "use help() or help(\"TOPIC\")")
                end
            elif target["name"] in builtin_arity:
                expected_builtin = builtin_arity[target["name"]]
                if len(syntax["arguments"]) != expected_builtin:
                    if state["error_label"] != "":
                        call record_error(state, syntax, "builtin_arity", "TypeError", "builtin " + target["name"] + " expects " + String(expected_builtin) + " argument(s), got " + String(len(syntax["arguments"])))
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "builtin " + target["name"] + " expects " + String(expected_builtin) + " argument(s), got " + String(len(syntax["arguments"])), "pass exactly " + String(expected_builtin) + " argument(s)")
                end
            elif target["name"] == "IntArray" or target["name"] == "FloatArray" or target["name"] == "ByteArray" or target["name"] == "set":
                if len(syntax["arguments"]) > 1:
                    if state["error_label"] != "":
                        call record_error(state, syntax, "array_arity", "TypeError", "builtin " + target["name"] + " expects zero or one argument")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "builtin " + target["name"] + " expects zero or one argument", "pass no argument for a new array or an existing array as a checked cast")
                end
            end
            if (target["name"].startswith("__lsl_qbe_") or target["name"].startswith("__lsl_raw_f") or target["name"] == "__lsl_symbol") and target["name"] in builtin_arity:
                for argument in syntax["arguments"]:
                    call expression(state, argument)
                end
                return
            end
            if target["name"].startswith("__lsl_declared_"):
                declared = target["name"][15:len(target["name"])]
                value = syntax["arguments"][0]
                actual = semantic.infer_expression_type(value, state["types"], state["function_returns"])
                if actual == declared:
                    call expression(state, value)
                    return
                end
                required = {"kind": "literal", "literal_kind": "string", "value": declared, "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
                check_call = {"kind": "call", "target": {"kind": "name", "name": "__lsl_require_declared"}, "arguments": [value, required], "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
                call expression(state, check_call)
                return
            elif target["name"] == "sorted" or target["name"] == "dedup" or target["name"] == "set":
                collection_arguments = syntax["arguments"]
                if len(collection_arguments) == 0:
                    collection_arguments = [{"kind": "list", "items": [], "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}]
                end
                collection_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_" + target["name"]}, "arguments": collection_arguments}
                call expression(state, collection_call)
                return
            elif target["name"] == "__lsl_new_set":
                return
            elif target["name"] == "__lsl_set_append" or target["name"] == "__lsl_set_store":
                call expression(state, syntax["arguments"][0])
                if target["name"] == "__lsl_set_store":
                    call expression(state, syntax["arguments"][1])
                end
                call expression(state, syntax["arguments"][len(syntax["arguments"]) - 1])
                return
            elif target["name"] == "IntArray" or target["name"] == "FloatArray" or target["name"] == "ByteArray":
                if len(syntax["arguments"]) == 0:
                    return
                end
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "float_zeros":
                if semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"]) != "Int":
                    if state["error_label"] != "":
                        call record_error(state, syntax["arguments"][0], "float_zeros", "TypeError", "float_zeros size must be an Int")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax["arguments"][0], "float_zeros size must be an Int", "convert the size with Int(...)")
                end
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_floatarray_bytes":
                if semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"]) != "FloatArray":
                    if state["error_label"] != "":
                        call record_error(state, syntax["arguments"][0], "floatarray_bytes", "TypeError", "__lsl_floatarray_bytes requires a FloatArray")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax["arguments"][0], "__lsl_floatarray_bytes requires a FloatArray", "pass a checked FloatArray value")
                end
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_text_byte_length":
                if semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"]) != "String":
                    if state["error_label"] != "":
                        call record_error(state, syntax["arguments"][0], "text_byte_length", "TypeError", "__lsl_text_byte_length requires a String")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax["arguments"][0], "__lsl_text_byte_length requires a String", "pass captured binary String data")
                end
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_floatarray_from_bytes":
                if semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"]) != "String":
                    if state["error_label"] != "":
                        call record_error(state, syntax["arguments"][0], "floatarray_from_bytes", "TypeError", "__lsl_floatarray_from_bytes requires a String")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax["arguments"][0], "__lsl_floatarray_from_bytes requires a String", "pass binary capture output")
                end
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_int_zeros":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_byte_zeros":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_raster_pack" or target["name"] == "__lsl_raster_copy" or target["name"] == "__lsl_byte_copy":
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                call expression(state, syntax["arguments"][2])
                call expression(state, syntax["arguments"][3])
                call expression(state, syntax["arguments"][4])
                return
            elif target["name"] == "__lsl_raster_fill":
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                call expression(state, syntax["arguments"][2])
                call expression(state, syntax["arguments"][3])
                return
            elif target["name"] == "float_fill":
                if semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"]) != "FloatArray" or semantic.infer_expression_type(syntax["arguments"][1], state["types"], state["function_returns"]) != "Float":
                    if state["error_label"] != "":
                        call record_error(state, syntax, "float_fill", "TypeError", "float_fill requires (FloatArray, Float)")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "float_fill requires (FloatArray, Float)", "cast the array and convert the value with Float(...)")
                end
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                return
            elif target["name"] == "float_sum":
                if semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"]) != "FloatArray":
                    if state["error_label"] != "":
                        call record_error(state, syntax["arguments"][0], "float_sum", "TypeError", "float_sum requires a FloatArray")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax["arguments"][0], "float_sum requires a FloatArray", "use FloatArray(value) for a checked cast")
                end
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "float_dot":
                if semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"]) != "FloatArray" or semantic.infer_expression_type(syntax["arguments"][1], state["types"], state["function_returns"]) != "FloatArray":
                    if state["error_label"] != "":
                        call record_error(state, syntax, "float_dot", "TypeError", "float_dot requires two FloatArrays")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "float_dot requires two FloatArrays", "use FloatArray(value) for checked casts")
                end
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                return
            elif target["name"] == "float_matmul":
                if semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"]) != "FloatArray" or semantic.infer_expression_type(syntax["arguments"][1], state["types"], state["function_returns"]) != "FloatArray" or semantic.infer_expression_type(syntax["arguments"][2], state["types"], state["function_returns"]) != "Int" or semantic.infer_expression_type(syntax["arguments"][3], state["types"], state["function_returns"]) != "Int" or semantic.infer_expression_type(syntax["arguments"][4], state["types"], state["function_returns"]) != "Int":
                    if state["error_label"] != "":
                        call record_error(state, syntax, "float_matmul", "TypeError", "float_matmul requires (FloatArray, FloatArray, Int, Int, Int)")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "float_matmul requires (FloatArray, FloatArray, Int, Int, Int)", "pass A, B, m, k, n")
                end
                for argument in syntax["arguments"]:
                    call expression(state, argument)
                end
                return
            elif target["name"] == "float_axpy":
                if semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"]) != "Float" or semantic.infer_expression_type(syntax["arguments"][1], state["types"], state["function_returns"]) != "FloatArray" or semantic.infer_expression_type(syntax["arguments"][2], state["types"], state["function_returns"]) != "FloatArray":
                    if state["error_label"] != "":
                        call record_error(state, syntax, "float_axpy", "TypeError", "float_axpy requires (Float, FloatArray, FloatArray)")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "float_axpy requires (Float, FloatArray, FloatArray)", "convert alpha with Float(...) and cast arrays with FloatArray(...)")
                end
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                call expression(state, syntax["arguments"][2])
                return
            elif target["name"] == "Bool":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "check":
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                return
            elif target["name"] == "List" or target["name"] == "Tuple" or target["name"] == "RealArray":
                conversion_target = "__lsl_list"
                if target["name"] == "RealArray":
                    conversion_target = "__lsl_real_array"
                end
                conversion_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": conversion_target}, "arguments": syntax["arguments"]}
                call expression(state, conversion_call)
                return
            elif target["name"] == "Dictionary":
                dictionary_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_dictionary"}, "arguments": syntax["arguments"]}
                call expression(state, dictionary_call)
                return
            elif target["name"] == "sum":
                sum_target = "__lsl_sum"
                if not state["internal_abi"] and not state.get("current_internal_function", False):
                    sum_target = "__lsl_public_sum"
                end
                sum_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": sum_target}, "arguments": syntax["arguments"]}
                call expression(state, sum_call)
                return
            elif target["name"] == "__lsl_float_accumulate":
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                return
            elif target["name"] == "__lsl_float_candidate_bits" or target["name"] == "__lsl_float_from_decimal" or target["name"] == "__lsl_decimal_compare" or target["name"] == "__lsl_float_nearer_upper" or target["name"] == "__lsl_decimal_digits_compare":
                for argument in syntax["arguments"]:
                    call expression(state, argument)
                end
                return
            elif target["name"] == "__lsl_float_string":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_float_from_int":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_float_to_int":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_float_bits":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_float_from_bits":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_raw_equal":
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                return
            elif target["name"] == "__lsl_is_heap":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_test_small_tables":
                return
            elif target["name"] == "__lsl_test_fd_fault":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_object_table_mask":
                return
            elif target["name"] == "__lsl_intern_table_mask":
                return
            elif target["name"] == "__lsl_address":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_raw_int":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_typed_int":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_checked_index":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_parse_literal_int":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_string_chars":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_type_code":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_box_bool":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_box_int":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_box_function":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_box_none":
                return
            elif target["name"] == "__lsl_unbox_bool":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_unbox_int":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_pop_last":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "len":
                length_type = semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"])
                if length_type != "Any" and not semantic.is_sized_type(length_type):
                    if state["error_label"] != "":
                        call record_error(state, syntax["arguments"][0], "length_target", "TypeError", "value of type " + length_type + " has no length")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax["arguments"][0], "value of type " + length_type + " has no length", "pass a String, collection, typed array, or Dictionary")
                end
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "Int":
                argument_type = semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"])
                if argument_type == "String":
                    parse_int_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_parse_int"}, "arguments": syntax["arguments"]}
                    call expression(state, parse_int_call)
                elif argument_type == "Any":
                    int_any_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_int_any"}, "arguments": syntax["arguments"]}
                    call expression(state, int_any_call)
                elif argument_type == "Float":
                    call expression(state, syntax["arguments"][0])
                else:
                    call expression(state, syntax["arguments"][0])
                end
                return
            elif target["name"] == "Float":
                argument_type = semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"])
                if argument_type == "String":
                    parse_float_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_parse_float"}, "arguments": syntax["arguments"]}
                    call expression(state, parse_float_call)
                elif argument_type == "Any":
                    float_any_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_float_any"}, "arguments": syntax["arguments"]}
                    call expression(state, float_any_call)
                else:
                    call expression(state, syntax["arguments"][0])
                end
                return
            elif target["name"] == "String":
                argument_type = semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"])
                if argument_type == "String":
                    call expression(state, syntax["arguments"][0])
                elif argument_type == "Float":
                    format_float_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_format_float"}, "arguments": syntax["arguments"]}
                    call expression(state, format_float_call)
                elif argument_type == "Int":
                    call expression(state, syntax["arguments"][0])
                elif argument_type == "Bool":
                    call expression(state, syntax["arguments"][0])
                elif argument_type == "None":
                    value = None
                else:
                    str_value_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_str_value"}, "arguments": syntax["arguments"]}
                    call expression(state, str_value_call)
                end
                return
            elif target["name"] == "chr":
                call checked_int(state, syntax["arguments"][0], "chr argument")
                return
            elif target["name"] == "ord":
                call expression(state, checked_string_node(state, syntax["arguments"][0]))
                return
            elif target["name"] == "arg":
                call checked_int(state, syntax["arguments"][0], "arg index")
                return
            elif target["name"] == "arg_count":
                return
            elif target["name"] == "gc":
                return
            elif target["name"] == "atomic_add" or target["name"] == "atomic_xchg":
                if semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"]) != "IntArray":
                    if state["error_label"] != "":
                        call record_error(state, syntax["arguments"][0], "atomic_target", "TypeError", "atomic RMW requires an IntArray target")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax["arguments"][0], "atomic RMW requires an IntArray target", "pass an IntArray as the first argument")
                end
                if semantic.infer_expression_type(syntax["arguments"][1], state["types"], state["function_returns"]) != "Int":
                    if state["error_label"] != "":
                        call record_error(state, syntax["arguments"][1], "atomic_index", "TypeError", "atomic RMW index requires an Int")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax["arguments"][1], "atomic RMW index requires an Int", "convert the index with Int(...) first")
                end
                if semantic.infer_expression_type(syntax["arguments"][2], state["types"], state["function_returns"]) != "Int":
                    if state["error_label"] != "":
                        call record_error(state, syntax["arguments"][2], "atomic_value", "TypeError", "atomic RMW value requires an Int")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax["arguments"][2], "atomic RMW value requires an Int", "convert the value with Int(...) first")
                end
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                call expression(state, syntax["arguments"][2])
                return
            elif target["name"] == "atomic_cas":
                if semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"]) != "IntArray":
                    if state["error_label"] != "":
                        call record_error(state, syntax["arguments"][0], "cas_target", "TypeError", "atomic_cas requires an IntArray target")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax["arguments"][0], "atomic_cas requires an IntArray target", "pass an IntArray as the first argument")
                end
                if semantic.infer_expression_type(syntax["arguments"][1], state["types"], state["function_returns"]) != "Int":
                    if state["error_label"] != "":
                        call record_error(state, syntax["arguments"][1], "cas_index", "TypeError", "atomic_cas index requires an Int")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax["arguments"][1], "atomic_cas index requires an Int", "convert the index with Int(...) first")
                end
                if semantic.infer_expression_type(syntax["arguments"][2], state["types"], state["function_returns"]) != "Int":
                    if state["error_label"] != "":
                        call record_error(state, syntax["arguments"][2], "cas_expected", "TypeError", "atomic_cas expected value requires an Int")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax["arguments"][2], "atomic_cas expected value requires an Int", "convert the value with Int(...) first")
                end
                if semantic.infer_expression_type(syntax["arguments"][3], state["types"], state["function_returns"]) != "Int":
                    if state["error_label"] != "":
                        call record_error(state, syntax["arguments"][3], "cas_desired", "TypeError", "atomic_cas desired value requires an Int")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax["arguments"][3], "atomic_cas desired value requires an Int", "convert the value with Int(...) first")
                end
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                call expression(state, syntax["arguments"][2])
                call expression(state, syntax["arguments"][3])
                return
            elif target["name"] == "atomic_pause":
                return
            elif target["name"] == "popcount" or target["name"] == "trailing_zeros":
                if semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"]) != "Int":
                    if state["error_label"] != "":
                        call record_error(state, syntax["arguments"][0], "integer_builtin", "TypeError", target["name"] + " requires an Int")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax["arguments"][0], target["name"] + " requires an Int", "convert the value with Int(...) first")
                end
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "cpu_count":
                return
            elif target["name"] == "thread_spawn":
                spawn_type = semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"])
                if spawn_type != "Function" and spawn_type != "Any":
                    if state["error_label"] != "":
                        call record_error(state, syntax["arguments"][0], "thread_function", "TypeError", "thread_spawn requires a Function")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax["arguments"][0], "thread_spawn requires a Function", "pass the name of a function with no parameters")
                end
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "thread_join":
                call checked_int(state, syntax["arguments"][0], "thread_join tid")
                return
            elif target["name"] == "__lsl_entry_source":
                return
            elif target["name"] == "executable_path":
                return
            elif target["name"] == "__lsl_getenv":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "run" or target["name"] == "__lsl_run" or target["name"] == "run_clean" or target["name"] == "__lsl_run_clean" or target["name"] == "capture" or target["name"] == "__lsl_capture" or target["name"] == "capture_clean" or target["name"] == "__lsl_capture_clean" or target["name"] == "capture_stream" or target["name"] == "capture_stream_clean" or target["name"] == "capture_input" or target["name"] == "capture_input_clean" or target["name"] == "capture_input_stream" or target["name"] == "capture_input_stream_clean":
                call expression(state, checked_string_node(state, syntax["arguments"][0]))
                call expression(state, checked_list_node(state, syntax["arguments"][1]))
                if target["name"] == "capture_input_stream" or target["name"] == "capture_input_stream_clean":
                    call expression(state, checked_string_node(state, syntax["arguments"][2]))
                    call expression(state, syntax["arguments"][3])
                elif target["name"] == "capture_stream" or target["name"] == "capture_stream_clean":
                    call expression(state, syntax["arguments"][2])
                elif target["name"] == "capture_input" or target["name"] == "capture_input_clean":
                    call expression(state, checked_string_node(state, syntax["arguments"][2]))
                else:
                    value = None
                end
                return
            elif target["name"] == "__lsl_run_timeout":
                # run_clean s časovým limitem v sekundách (knihovny).
                call expression(state, checked_string_node(state, syntax["arguments"][0]))
                call expression(state, checked_list_node(state, syntax["arguments"][1]))
                call expression(state, syntax["arguments"][2])
                return
            elif target["name"] == "__lsl_capture_input_timeout":
                # capture_input_clean s časovým limitem v sekundách (knihovny).
                call expression(state, checked_string_node(state, syntax["arguments"][0]))
                call expression(state, checked_list_node(state, syntax["arguments"][1]))
                call expression(state, checked_string_node(state, syntax["arguments"][2]))
                call expression(state, syntax["arguments"][3])
                return
            elif target["name"] == "native_open":
                call expression(state, checked_string_node(state, syntax["arguments"][0]))
                return
            elif target["name"] == "native_size":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "native_u64" or target["name"] == "native_function" or target["name"] == "native_call":
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                return
            elif target["name"] == "native_name_equal":
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                call expression(state, syntax["arguments"][2])
                return
            elif target["name"] == "native_close":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_fd_open":
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                return
            elif target["name"] == "__lsl_fd_socket":
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                return
            elif target["name"] == "__lsl_fd_read" or target["name"] == "__lsl_fd_write" or target["name"] == "__lsl_fd_connect" or target["name"] == "__lsl_fd_ioctl":
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                call expression(state, syntax["arguments"][2])
                return
            elif target["name"] == "__lsl_data_address":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_fd_mmap":
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                call expression(state, syntax["arguments"][2])
                return
            elif target["name"] == "__lsl_fd_snapshot":
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                call expression(state, syntax["arguments"][2])
                return
            elif target["name"] == "__lsl_mem_pack":
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                call expression(state, syntax["arguments"][2])
                call expression(state, syntax["arguments"][3])
                call expression(state, syntax["arguments"][4])
                return
            elif target["name"] == "__lsl_mem_unpack":
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                call expression(state, syntax["arguments"][2])
                call expression(state, syntax["arguments"][3])
                return
            elif target["name"] == "__lsl_text_byte":
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                return
            elif target["name"] == "__lsl_text_scan_digits" or target["name"] == "__lsl_text_split_byte":
                state["lazy_used"]["__lsl_text_helpers"] = True
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                return
            elif target["name"] == "__lsl_text_piece" or target["name"] == "__lsl_text_digits":
                state["lazy_used"]["__lsl_text_helpers"] = True
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                call expression(state, syntax["arguments"][2])
                return
            elif target["name"] == "__lsl_text_from_bytes":
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                call expression(state, syntax["arguments"][2])
                return
            elif target["name"] == "__lsl_syscall":
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                call expression(state, syntax["arguments"][2])
                call expression(state, syntax["arguments"][3])
                call expression(state, syntax["arguments"][4])
                return
            elif target["name"] == "__lsl_syscall6":
                syscall_index = 6
                while syscall_index >= 0:
                    call expression(state, syntax["arguments"][syscall_index])
                    syscall_index -= 1
                end
                syscall_index = 1
                while syscall_index < 6:
                    syscall_index += 1
                end
                return
            elif target["name"] == "__lsl_fd_seek":
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                return
            elif target["name"] == "__lsl_fd_close":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "capture_status":
                return
            elif target["name"] == "capture_stderr":
                return
            elif target["name"] == "input":
                state["lazy_used"]["input"] = True
                call expression(state, checked_string_node(state, syntax["arguments"][0]))
                return
            elif target["name"] == "clock":
                wall = {"kind": "call", "target": {"kind": "name", "name": "__lsl_wall_time"}, "arguments": [], "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
                formatted = {"kind": "call", "target": {"kind": "name", "name": "__lsl_clock_text"}, "arguments": [wall], "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
                call expression(state, formatted)
                return
            elif target["name"] == "monotonic" or target["name"] == "__lsl_monotonic" or target["name"] == "__lsl_wall_time":
                return
            elif target["name"] == "__lsl_sleep":
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_isatty":
                call checked_int(state, syntax["arguments"][0], "file descriptor")
                return
            elif target["name"] == "__lsl_stdin_eof":
                return
            elif target["name"] == "readfile" or target["name"] == "readbytes":
                call expression(state, checked_string_node(state, syntax["arguments"][0]))
                return
            elif target["name"] == "writefile" or target["name"] == "appendfile" or target["name"] == "writebytes":
                call expression(state, checked_string_node(state, syntax["arguments"][0]))
                if target["name"] == "writebytes":
                    call expression(state, checked_byte_sequence_node(state, syntax["arguments"][1]))
                else:
                    call expression(state, checked_string_node(state, syntax["arguments"][1]))
                end
                return
            elif target["name"] == "last_error":
                return
            elif target["name"] == "type":
                value_type = semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"])
                if value_type == "Any":
                    call expression(state, syntax["arguments"][0])
                    return
                end
                if value_type.startswith("Class:"):
                    value_type = "Class"
                elif value_type.startswith("Instance:"):
                    value_type = "Instance"
                end
                return
            elif target["name"] == "mkdir" or target["name"] == "__lsl_mkdir_private" or target["name"] == "unlink" or target["name"] == "rmdir":
                call expression(state, checked_string_node(state, syntax["arguments"][0]))
                return
            elif target["name"] == "exists":
                call expression(state, checked_string_node(state, syntax["arguments"][0]))
                return
            elif target["name"] == "min" or target["name"] == "max":
                if len(syntax["arguments"]) == 1:
                    reducer = "__lsl_min"
                    if target["name"] == "max":
                        reducer = "__lsl_max"
                    end
                    reduce_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": reducer}, "arguments": syntax["arguments"]}
                    call expression(state, reduce_call)
                    return
                end
                if len(syntax["arguments"]) != 2:
                    if state["error_label"] != "":
                        call record_error(state, syntax, "minmax_arity", "TypeError", "builtin " + target["name"] + " expects 1 iterable or 2 values")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "builtin " + target["name"] + " expects 1 iterable or 2 values", "pass min(iterable) or min(a, b)")
                end
                minmax_left_type = semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"])
                minmax_right_type = semantic.infer_expression_type(syntax["arguments"][1], state["types"], state["function_returns"])
                minmax_left_numeric = minmax_left_type == "Int" or minmax_left_type == "Bool" or minmax_left_type == "Float" or minmax_left_type == "Any"
                minmax_right_numeric = minmax_right_type == "Int" or minmax_right_type == "Bool" or minmax_right_type == "Float" or minmax_right_type == "Any"
                if not minmax_left_numeric or not minmax_right_numeric:
                    if state["error_label"] != "":
                        call record_error(state, syntax, "minmax_operands", "TypeError", "builtin " + target["name"] + " expects numeric values")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "builtin " + target["name"] + " expects numeric values", "pass Int, Bool, or Float values")
                end
                minmax_dynamic = minmax_left_type == "Float" or minmax_right_type == "Float" or minmax_left_type == "Any" or minmax_right_type == "Any"
                call expression(state, syntax["arguments"][0])
                call expression(state, syntax["arguments"][1])
                if minmax_dynamic:
                    return
                end
                return
            elif target["name"] == "help":
                help_arguments = syntax["arguments"]
                if len(help_arguments) == 0:
                    help_arguments = [{"kind": "literal", "literal_kind": "string", "value": "", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}]
                end
                help_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_help"}, "arguments": help_arguments}
                call expression(state, help_call)
                return
            elif target["name"] == "abs":
                abs_arg_type = semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"])
                if not semantic.is_numeric_type(abs_arg_type):
                    if state["error_label"] != "":
                        call record_error(state, syntax, "abs_operand", "TypeError", "abs requires a numeric operand")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "abs requires a numeric operand", "pass an Int, Bool, or Float value")
                end
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "sqrt":
                sqrt_arg_type = semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"])
                if not semantic.is_numeric_type(sqrt_arg_type):
                    if state["error_label"] != "":
                        call record_error(state, syntax, "sqrt_operand", "TypeError", "sqrt requires a numeric operand")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "sqrt requires a numeric operand", "pass an Int, Bool, or Float value")
                end
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "exit":
                call checked_int(state, syntax["arguments"][0], "exit status")
                return
            end
        elif target["kind"] == "member":
            origin_call = target["target"]["kind"] == "name" and target["target"]["name"] == "origin"
            if origin_call:
                current_class = state.get("current_class_name", "")
                if current_class == "":
                    call semantic.unsupported(state["path"], state["lines"], syntax, "origin can only be used inside a class method", "call origin.method() from a subclass method")
                end
                parent_class = semantic.class_parent_name(state["classes"], current_class)
                if parent_class == "":
                    call semantic.unsupported(state["path"], state["lines"], syntax, "class " + current_class + " has no parent", "remove origin or inherit from a parent class")
                end
                origin_method_name = semantic.resolve_method_name(state["classes"], state["functions"], parent_class, target["name"])
                if origin_method_name == "":
                    if state["error_label"] != "":
                        call record_error(state, syntax, "origin_method", "AttributeError", "unknown parent method: " + target["name"])
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "unknown parent method: " + target["name"], "declare the method in an ancestor of " + current_class)
                end
                origin_arguments = [{"kind": "name", "name": "self", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}]
                origin_arguments.extend(syntax["arguments"])
                origin_target = {"kind": "name", "name": origin_method_name, "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
                origin_expression = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": origin_target, "arguments": origin_arguments}
                if "argument_names" in syntax:
                    origin_names = [""]
                    origin_names.extend(syntax["argument_names"])
                    origin_expression["argument_names"] = origin_names
                end
                call expression(state, origin_expression)
                return
            end
            receiver_type = semantic.infer_expression_type(target["target"], state["types"], state["function_returns"])
            if "argument_names" in syntax and not receiver_type.startswith("Class:") and not receiver_type.startswith("Instance:"):
                if state["error_label"] != "":
                    call record_error(state, syntax, "method_keywords", "TypeError", "builtin methods do not accept keyword arguments")
                    return
                end
                call semantic.unsupported(state["path"], state["lines"], syntax, "builtin methods do not accept keyword arguments", "use positional arguments")
            end
            if not receiver_type.startswith("Class:") and not receiver_type.startswith("Instance:") and not semantic.method_supported(receiver_type, target["name"]):
                if state["error_label"] != "":
                    call record_error(state, syntax, "method_supported", "AttributeError", "type " + receiver_type + " has no method " + target["name"])
                    return
                end
                call semantic.unsupported(state["path"], state["lines"], syntax, "type " + receiver_type + " has no method " + target["name"], "use a method documented for " + receiver_type)
            end
            method_arity = {"strip": 0, "lstrip": 0, "rstrip": 0, "lower": 0, "upper": 0, "title": 0, "capitalize": 0, "sort": 0, "reverse": 0, "copy": 0, "keys": 0, "values": 0, "items": 0, "clear": 0, "append": 1, "startswith": 1, "endswith": 1, "find": 1, "count": 1, "join": 1, "extend": 1, "remove": 1, "index": 1, "update": 1, "replace": 2, "insert": 2}
            if semantic.set_method(target["name"]):
                method_arity[target["name"]] = 1
            end
            if target["name"] in method_arity and not receiver_type.startswith("Class:") and not receiver_type.startswith("Instance:"):
                expected_method = method_arity[target["name"]]
                if len(syntax["arguments"]) != expected_method:
                    if state["error_label"] != "":
                        call record_error(state, syntax, "method_arity", "TypeError", "method " + target["name"] + " expects " + String(expected_method) + " argument(s), got " + String(len(syntax["arguments"])))
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "method " + target["name"] + " expects " + String(expected_method) + " argument(s), got " + String(len(syntax["arguments"])), "pass exactly " + String(expected_method) + " argument(s)")
                end
            elif target["name"] == "split" and not receiver_type.startswith("Class:") and not receiver_type.startswith("Instance:"):
                # split() bez argumentu dělí podle mezery.
                if len(syntax["arguments"]) > 1:
                    if state["error_label"] != "":
                        call record_error(state, syntax, "method_arity", "TypeError", "method split expects zero or one argument, got " + String(len(syntax["arguments"])))
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "method split expects zero or one argument, got " + String(len(syntax["arguments"])), "use text.split() or text.split(separator)")
                end
            elif target["name"] == "get":
                if len(syntax["arguments"]) != 1 and len(syntax["arguments"]) != 2:
                    if state["error_label"] != "":
                        call record_error(state, syntax, "get_arity", "TypeError", "method get expects one or two arguments")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "method get expects one or two arguments", "use dictionary.get(key[, default])")
                end
            elif target["name"] == "setdefault":
                if len(syntax["arguments"]) != 2:
                    if state["error_label"] != "":
                        call record_error(state, syntax, "setdefault_arity", "TypeError", "method setdefault expects two arguments")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "method setdefault expects two arguments", "use dictionary.setdefault(key, default)")
                end
            elif target["name"] == "pop":
                pop_arity_valid = False
                if receiver_type == "Dictionary":
                    pop_arity_valid = len(syntax["arguments"]) == 1 or len(syntax["arguments"]) == 2
                elif receiver_type == "Set":
                    pop_arity_valid = len(syntax["arguments"]) == 0
                elif receiver_type == "Any":
                    pop_arity_valid = len(syntax["arguments"]) >= 0 and len(syntax["arguments"]) <= 2
                else:
                    pop_arity_valid = len(syntax["arguments"]) == 0 or len(syntax["arguments"]) == 1
                end
                if not pop_arity_valid:
                    if state["error_label"] != "":
                        call record_error(state, syntax, "pop_arity", "TypeError", "invalid pop argument count")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "invalid pop argument count", "use list.pop([index]) or dictionary.pop(key[, default])")
                end
            end
            if target["name"] == "insert" or (target["name"] == "pop" and receiver_type != "Dictionary" and receiver_type != "Any" and len(syntax["arguments"]) == 1):
                method_index_type = semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"])
                if method_index_type != "Int" and method_index_type != "Bool" and method_index_type != "Any":
                    if state["error_label"] != "":
                        call record_error(state, syntax["arguments"][0], "method_index", "TypeError", "sequence index must be Int, got " + shown_type(method_index_type))
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax["arguments"][0], "sequence index must be Int, got " + shown_type(method_index_type), "convert the index with Int(...)")
                end
            end
            if (receiver_type == "Set" and target["name"] != "clear") or ((receiver_type == "Any") and (semantic.set_method(target["name"]) or target["name"] == "remove" or target["name"] == "update")):
                set_target = "__lsl_set_" + target["name"]
                if target["name"] == "copy":
                    set_target = "__lsl_set"
                elif receiver_type == "Any" and (target["name"] == "remove" or target["name"] == "update"):
                    set_target = "__lsl_collection_" + target["name"]
                end
                set_arguments = [target["target"]]
                set_arguments.extend(syntax["arguments"])
                call expression(state, {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": set_target}, "arguments": set_arguments})
                return
            end
            if receiver_type.startswith("Class:") or receiver_type.startswith("Instance:"):
                if receiver_type.startswith("Class:"):
                    class_name = receiver_type[6:len(receiver_type)]
                else:
                    class_name = receiver_type[9:len(receiver_type)]
                end
                native_method_name = semantic.resolve_method_name(state["classes"], state["functions"], class_name, target["name"])
                if native_method_name == "":
                    if state["error_label"] != "":
                        call record_error(state, syntax, "class_method", "AttributeError", "unknown class method: " + target["name"])
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "unknown class method: " + target["name"], "declare the method inside class " + class_name)
                end
                declaration = state["functions"][native_method_name]
                combined_arguments = []
                if len(declaration["parameters"]) > 0:
                    if declaration["parameters"][0] == "self":
                        combined_arguments.append(target["target"])
                    end
                end
                combined_arguments.extend(syntax["arguments"])
                combined_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": native_method_name}, "arguments": combined_arguments}
                if "argument_names" in syntax:
                    combined_names = []
                    if len(combined_arguments) > len(syntax["arguments"]):
                        combined_names.append("")
                    end
                    combined_names.extend(syntax["argument_names"])
                    combined_call["argument_names"] = combined_names
                end
                call expression(state, combined_call)
                return
            elif (receiver_type == "IntArray" or receiver_type == "FloatArray" or receiver_type == "ByteArray") and target["name"] != "append" and target["name"] != "clear":
                if state["error_label"] != "":
                    call record_error(state, syntax, "typed_array_method", "TypeError", receiver_type + " method is not implemented: " + target["name"])
                    return
                end
                call semantic.unsupported(state["path"], state["lines"], syntax, receiver_type + " method is not implemented: " + target["name"], "use append, clear, indexed access, indexed assignment, len, or iteration")
            elif target["name"] == "append":
                if receiver_type == "Tuple" or receiver_type == "RealArray":
                    if state["error_label"] != "":
                        call record_error(state, syntax, "fixed_append", "TypeError", "fixed collection does not support append")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "fixed collection does not support append", "convert it with List(value) before appending")
                end
                if receiver_type == "IntArray":
                    if semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"]) != "Int":
                        if state["error_label"] != "":
                            call record_error(state, syntax["arguments"][0], "intarray_append", "TypeError", "IntArray append requires an Int")
                            return
                        end
                        call semantic.unsupported(state["path"], state["lines"], syntax["arguments"][0], "IntArray append requires an Int", "convert the value with Int(...) before appending")
                    end
                elif receiver_type == "FloatArray":
                    if semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"]) != "Float":
                        if state["error_label"] != "":
                            call record_error(state, syntax["arguments"][0], "floatarray_append", "TypeError", "FloatArray append requires a Float")
                            return
                        end
                        call semantic.unsupported(state["path"], state["lines"], syntax["arguments"][0], "FloatArray append requires a Float", "convert the value with Float(...) before appending")
                    end
                elif receiver_type == "ByteArray":
                    if semantic.infer_expression_type(syntax["arguments"][0], state["types"], state["function_returns"]) != "Int":
                        if state["error_label"] != "":
                            call record_error(state, syntax["arguments"][0], "bytearray_append", "TypeError", "ByteArray append requires an Int")
                            return
                        end
                        call semantic.unsupported(state["path"], state["lines"], syntax["arguments"][0], "ByteArray append requires an Int", "convert the value with Int(...) before appending")
                    end
                end
                call expression(state, target["target"])
                call expression(state, syntax["arguments"][0])
                return
            elif target["name"] == "clear":
                if receiver_type == "Tuple" or receiver_type == "RealArray":
                    if state["error_label"] != "":
                        call record_error(state, syntax, "fixed_clear", "TypeError", "fixed collection does not support clear")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "fixed collection does not support clear", "convert it with List(value) before changing its length")
                elif receiver_type == "Dictionary":
                    clear_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_dict_clear"}, "arguments": [target["target"]]}
                    call expression(state, clear_call)
                else:
                    call expression(state, target["target"])
                end
                return
            elif target["name"] == "pop":
                if receiver_type == "Tuple" or receiver_type == "RealArray":
                    if state["error_label"] != "":
                        call record_error(state, syntax, "fixed_pop", "TypeError", "fixed collection does not support pop")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "fixed collection does not support pop", "convert it with List(value) before changing its length")
                end
                pop_target = "__lsl_pop"
                pop_arguments = [target["target"]]
                if receiver_type == "Any" and not state["internal_abi"]:
                    pop_target = "__lsl_dynamic_pop" + String(len(syntax["arguments"]))
                    pop_arguments.extend(syntax["arguments"])
                elif receiver_type == "Dictionary":
                    if len(syntax["arguments"]) == 1:
                        pop_target = "__lsl_dict_pop"
                    else:
                        pop_target = "__lsl_dict_pop_default"
                    end
                    pop_arguments.extend(syntax["arguments"])
                elif len(syntax["arguments"]) == 1:
                    pop_target = "__lsl_pop_at"
                    pop_arguments.append(checked_index_node(state, syntax["arguments"][0]))
                end
                pop_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": pop_target}, "arguments": pop_arguments}
                call expression(state, pop_call)
                return
            elif target["name"] == "keys":
                call expression(state, target["target"])
                return
            else:
                method_target = semantic.method_function(target["name"])
                method_receiver = target["target"]
                if receiver_type == "Any" and not state["internal_abi"]:
                    receiver_guard = ""
                    if target["name"] == "count":
                        method_target = "__lsl_dynamic_count"
                    elif target["name"] == "index":
                        method_target = "__lsl_dynamic_index"
                    elif target["name"] == "find":
                        method_target = "__lsl_dynamic_find"
                    elif target["name"] == "copy":
                        method_target = "__lsl_dynamic_copy"
                    elif target["name"] == "extend" or target["name"] == "insert" or target["name"] == "remove" or target["name"] == "sort" or target["name"] == "reverse":
                        receiver_guard = "__lsl_require_list"
                    elif target["name"] == "get" or target["name"] == "setdefault" or target["name"] == "update" or target["name"] == "values" or target["name"] == "items":
                        receiver_guard = "__lsl_require_dictionary"
                    else:
                        receiver_guard = "__lsl_require_string"
                    end
                    if receiver_guard != "":
                        method_receiver = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": receiver_guard}, "arguments": [target["target"]]}
                    end
                end
                if receiver_type == "Tuple" or receiver_type == "RealArray":
                    if target["name"] == "insert" or target["name"] == "remove" or target["name"] == "extend" or target["name"] == "sort" or target["name"] == "clear" or target["name"] == "pop":
                        if state["error_label"] != "":
                            call record_error(state, syntax, "fixed_mutation", "TypeError", "fixed collection does not support " + target["name"])
                            return
                        end
                        call semantic.unsupported(state["path"], state["lines"], syntax, "fixed collection does not support " + target["name"], "convert it with List(value) before changing its length")
                    end
                end
                if receiver_type == "List" or receiver_type == "Tuple" or receiver_type == "RealArray" or receiver_type == "IntArray" or receiver_type == "FloatArray":
                    if target["name"] == "index":
                        method_target = "__lsl_list_index"
                    elif target["name"] == "count":
                        method_target = "__lsl_list_count"
                    elif target["name"] == "find":
                        method_target = "__lsl_list_find"
                    end
                elif receiver_type == "String" and target["name"] == "index":
                    method_target = "__lsl_string_index"
                elif receiver_type == "Dictionary" and target["name"] == "copy":
                    method_target = "__lsl_dict_copy"
                end
                if method_target != "":
                    combined_arguments = [method_receiver]
                    if target["name"] == "insert":
                        combined_arguments.append(checked_index_node(state, syntax["arguments"][0]))
                        combined_arguments.append(syntax["arguments"][1])
                    else:
                        combined_arguments.extend(syntax["arguments"])
                    end
                    if target["name"] == "get" and len(syntax["arguments"]) == 1:
                        combined_arguments.append({"kind": "literal", "literal_kind": "name", "value": "None", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]})
                    end
                    for argument in combined_arguments:
                        call expression(state, argument)
                    end
                    method_index = len(combined_arguments) - 1
                    while method_index >= 0:
                        method_index -= 1
                    end
                    if lazy_runtime(method_target):
                        state["lazy_used"][method_target] = True
                    end
                    return
                end
            end
        end
        if target["kind"] != "name":
            if state["error_label"] != "":
                call record_error(state, syntax, "call_target", "TypeError", "only direct Function calls are supported; unresolved target kind " + target["kind"] + " member " + target.get("name", "?"))
                return
            end
            call semantic.unsupported(state["path"], state["lines"], syntax, "only direct Function calls are supported; unresolved target kind " + target["kind"] + " member " + target.get("name", "?"), "call a declared function by name")
        end
        if target["name"] in state["classes"]:
            class_name = target["name"]
            arguments = syntax["arguments"]
            initializer_name = semantic.resolve_method_name(state["classes"], state["functions"], class_name, "init")
            if initializer_name == "" and "argument_names" in syntax:
                if state["error_label"] != "":
                    call record_error(state, syntax, "constructor_keywords", "TypeError", "class without init does not accept keyword arguments")
                    return
                end
                call semantic.unsupported(state["path"], state["lines"], syntax, "class without init does not accept keyword arguments", "declare an initializer or construct the class without arguments")
            end
            if initializer_name != "":
                initializer = state["functions"][initializer_name]
                arguments = bind_arguments(state, syntax, initializer, 1)
                if arguments == None:
                    return
                end
                if len(arguments) + 1 != len(initializer["parameters"]):
                    if state["error_label"] != "":
                        call record_error(state, syntax, "constructor_arity", "TypeError", "initializer argument count mismatch")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "initializer argument count mismatch", "pass exactly " + String(len(initializer["parameters"]) - 1) + " arguments")
                end
                index = len(arguments) - 1
                while index >= 0:
                    call expression(state, arguments[index])
                    index -= 1
                end
            end
            return
        end
        indirect_call = False
        if target["name"] not in state["functions"]:
            if target["name"] in state["variables"] or target["name"] in state["global_variables"]:
                indirect_call = True
            elif target["name"] == "rang" or target["name"] == "range":
                count = len(syntax["arguments"])
                if count < 1 or count > 3 or "argument_names" in syntax:
                    if state["error_label"] != "":
                        call record_error(state, syntax, "rang_value_arity", "TypeError", "rang expects 1 to 3 positional arguments")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], syntax, "rang expects 1 to 3 positional arguments", "use rang(STOP), rang(START, STOP) or rang(START, STOP, STEP)")
                end
                zero = {"kind": "literal", "literal_kind": "number", "value": "0", "integer_value": 0, "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
                one = {"kind": "literal", "literal_kind": "number", "value": "1", "integer_value": 1, "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
                range_arguments = [zero, syntax["arguments"][0], one]
                if count >= 2:
                    range_arguments = [syntax["arguments"][0], syntax["arguments"][1], one]
                end
                if count == 3:
                    range_arguments[2] = syntax["arguments"][2]
                end
                range_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_rang_list", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}, "arguments": range_arguments}
                call expression(state, range_call)
                return
            else:
                if state["error_label"] != "":
                    call record_error(state, syntax, "unknown_function", "NameError", "unknown native function: " + target["name"])
                    return
                end
                call semantic.unsupported(state["path"], state["lines"], syntax, "unknown native function: " + target["name"], "declare the function or assign a Function value before calling it")
            end
        end
        arguments = syntax["arguments"]
        if not indirect_call:
            arguments = bind_arguments(state, syntax, state["functions"][target["name"]], 0)
            if arguments == None:
                return
            end
            expected_arguments = len(state["functions"][target["name"]]["parameters"])
            if len(arguments) != expected_arguments:
                if state["error_label"] != "":
                    call record_error(state, syntax, "function_arity", "TypeError", "function argument count mismatch for " + target["name"])
                    return
                end
                call semantic.unsupported(state["path"], state["lines"], syntax, "function argument count mismatch for " + target["name"], "pass exactly " + String(expected_arguments) + " arguments")
            end
        elif "argument_names" in syntax:
            if state["error_label"] != "":
                call record_error(state, syntax, "indirect_keywords", "TypeError", "keyword arguments require a statically known function")
                return
            end
            call semantic.unsupported(state["path"], state["lines"], syntax, "keyword arguments require a statically known function", "call the declared function or pass positional arguments")
        end
        index = len(arguments) - 1
        while index >= 0:
            call expression(state, arguments[index])
            index -= 1
        end
    elif kind == "compare":
        if len(syntax["operators"]) > 1:
            chain_index = 0
            while chain_index < len(syntax["operators"]):
                pair = {"kind": "compare", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "operators": [syntax["operators"][chain_index]], "operands": [syntax["operands"][chain_index], syntax["operands"][chain_index + 1]]}
                call expression(state, pair)
                chain_index += 1
            end
            return
        end
        left = syntax["operands"][0]
        right = syntax["operands"][1]
        operator = syntax["operators"][0]
        if operator == "in" or operator == "not in":
            container_type = semantic.infer_expression_type(right, state["types"], state["function_returns"])
            member_type = semantic.infer_expression_type(left, state["types"], state["function_returns"])
            if container_type != "Any" and not semantic.is_sized_type(container_type):
                if state["error_label"] != "":
                    call record_error(state, right, "membership_target", "TypeError", "right operand of in has type " + container_type + ", not a collection")
                    return
                end
                call semantic.unsupported(state["path"], state["lines"], right, "right operand of in has type " + container_type + ", not a collection", "use a String, collection, typed array, or Dictionary")
            elif container_type == "String" and member_type != "String" and member_type != "Any":
                if state["error_label"] != "":
                    call record_error(state, left, "membership_value", "TypeError", "String membership requires a String value")
                    return
                end
                call semantic.unsupported(state["path"], state["lines"], left, "String membership requires a String value", "convert the searched value with String(...)")
            end
            if (container_type == "Any" and not state["internal_abi"]) or container_type == "Set" or container_type == "IntArray" or container_type == "FloatArray" or container_type == "ByteArray" or (container_type == "String" and member_type == "Any" and not state["internal_abi"]):
                contains_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_dynamic_contains"}, "arguments": [right, left]}
                call expression(state, contains_call)
            else:
                call expression(state, right)
                call expression(state, left)
                if container_type == "Dictionary":
                    call dictionary_key(state, left)
                end
            end
            return
        end
        valid_comparison = operator in ["==", "!=", "is", "is not", "<", "<=", ">", ">="]
        if not valid_comparison:
            if state["error_label"] != "":
                call record_error(state, syntax, "comparison_operator", "TypeError", "comparison " + operator + " is unavailable for current values")
                return
            end
            call semantic.unsupported(state["path"], state["lines"], syntax, "comparison " + operator + " is unavailable for current values", "use equality, membership, or an ordered Int comparison")
        end
        left_type = semantic.infer_expression_type(left, state["types"], state["function_returns"])
        right_type = semantic.infer_expression_type(right, state["types"], state["function_returns"])
        ordered_comparison = operator == "<" or operator == "<=" or operator == ">" or operator == ">="
        if ordered_comparison and (not semantic.is_numeric_type(left_type) or not semantic.is_numeric_type(right_type)):
            if state["error_label"] != "":
                call record_error(state, syntax, "ordered_operands", "TypeError", "ordered comparison requires numeric operands")
                return
            end
            call semantic.unsupported(state["path"], state["lines"], syntax, "ordered comparison requires numeric operands", "compare Int, Bool, or Float values")
        end
        call expression(state, left)
        call expression(state, right)
    else:
        call semantic.unsupported(state["path"], state["lines"], syntax, "expression kind " + kind + " is not in the native scalar slice", "this construct will be enabled with the dynamic runtime")
    end
end

# Volání funkce (vlastní i knihovní) jako samostatný příkaz vyžaduje `call`;
# metody objektů a vestavěné příkazy (Error, del, exit, check, writefile …)
# `call` nepotřebují. Syntetické příkazy bez klíče "discard" a interní kód
# překladače se nekontrolují.
function require_call_prefix(state, statement):
    if statement.get("discard", True) or state["current_internal_function"] or state["internal_abi"]:
        return None
    end
    syntax = statement["expression"]
    if syntax["kind"] != "call" or syntax["target"]["kind"] != "name":
        return None
    end
    name = syntax["target"]["name"]
    if name.startswith("__lsl_") or name not in state["functions"]:
        return None
    end
    # Název, jak je napsaný ve zdroji (u knihovny včetně modulu: json.decode).
    shown = name.split("@")[-1]
    details = semantic.context(state["path"], state["lines"], syntax)
    source_line = String(details["source"])
    start = syntax["column"] - 1
    if start >= 0 and start < len(source_line):
        written = source_line[start:len(source_line)]
        bracket = written.find("(")
        if bracket > 0:
            shown = written[0:bracket].strip()
        end
    end
    call semantic.unsupported(state["path"], state["lines"], syntax, "function call result is discarded without call: " + shown + "(...)", "write call " + shown + "(...) to call a function for its effect, or assign the result")
end

function statements(state, body, break_label, continue_label, return_label):
    for statement in body:
        kind = statement["kind"]
        if kind == "assign":
            target = statement["target"]
            if target["kind"] == "name":
                if statement["operator"] == "=":
                    value_syntax = statement["value"]
                    if value_syntax["kind"] == "call" and value_syntax["target"]["kind"] == "name" and value_syntax["target"]["name"].startswith("__lsl_declared_"):
                        inner = value_syntax["arguments"][0]
                        if semantic.infer_expression_type(inner, state["types"], state["function_returns"]) == state["types"].get(target["name"], "Any"):
                            value_syntax = inner
                        end
                    end
                else:
                    operator = statement["operator"][0:len(statement["operator"]) - 1]
                    value_syntax = {"kind": "binary", "line": statement["line"], "column": statement["column"], "end_column": statement["end_column"], "operator": operator, "left": target, "right": statement["value"]}
                end
                if statement["operator"] == "=":
                    call expression(state, value_syntax)
                else:
                    call expression(state, value_syntax)
                end
            elif target["kind"] == "index":
                target_type = semantic.infer_expression_type(target["target"], state["types"], state["function_returns"])
                index_type = semantic.infer_expression_type(target["index"], state["types"], state["function_returns"])
                if target_type != "Any" and not semantic.is_mutable_index_type(target_type):
                    if state["error_label"] != "":
                        call record_error(state, statement, "assignment_target", "TypeError", "value of type " + target_type + " does not support indexed assignment")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], statement, "value of type " + target_type + " does not support indexed assignment", "assign through a mutable collection or Dictionary")
                elif target_type != "Dictionary" and target_type != "Any" and index_type != "Int" and index_type != "Bool" and index_type != "Any":
                    if state["error_label"] != "":
                        call record_error(state, target["index"], "assignment_index", "TypeError", "sequence index must be Int, got " + shown_type(index_type))
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], target["index"], "sequence index must be Int, got " + shown_type(index_type), "convert the index with Int(...)")
                end
                fast_value = statement["value"]
                if statement["operator"] != "=":
                    fast_value = {"kind": "binary", "line": statement["line"], "column": statement["column"], "end_column": statement["end_column"], "operator": statement["operator"][0:len(statement["operator"]) - 1], "left": target, "right": statement["value"]}
                end
                if target_type == "IntArray" and state["unchecked_intarray"] and (semantic.fast_integer_index(state, target["index"]) or semantic.pure_integer_expression(state, target["index"])) and (semantic.fast_integer_value(state, fast_value) or semantic.pure_integer_expression(state, fast_value)):
                    if semantic.infer_expression_type(fast_value, state["types"], state["function_returns"]) != "Int":
                        if state["error_label"] != "":
                            call record_error(state, statement["value"], "fast_intarray_assignment", "TypeError", "IntArray assignment requires an Int result")
                            return
                        end
                        call semantic.unsupported(state["path"], state["lines"], statement["value"], "IntArray assignment requires an Int result", "use integer arithmetic for the assigned value")
                    end
                end
                call expression(state, target["target"])
                call expression(state, target["index"])
                if target_type == "Dictionary" or (target_type == "Any" and not state["internal_abi"]):
                    call dictionary_key(state, target["index"])
                elif index_type == "Any":
                    value = None
                end
                if statement["operator"] == "=":
                    assigned_type = semantic.infer_expression_type(statement["value"], state["types"], state["function_returns"])
                    if target_type == "IntArray" and assigned_type != "Int":
                        if state["error_label"] != "":
                            call record_error(state, statement["value"], "intarray_assignment", "TypeError", "IntArray assignment requires an Int")
                            return
                        end
                        call semantic.unsupported(state["path"], state["lines"], statement["value"], "IntArray assignment requires an Int", "convert the value with Int(...) before assignment")
                    elif target_type == "FloatArray" and assigned_type != "Float":
                        if state["error_label"] != "":
                            call record_error(state, statement["value"], "floatarray_assignment", "TypeError", "FloatArray assignment requires a Float")
                            return
                        end
                        call semantic.unsupported(state["path"], state["lines"], statement["value"], "FloatArray assignment requires a Float", "convert the value with Float(...) before assignment")
                    elif target_type == "ByteArray" and assigned_type != "Int":
                        if state["error_label"] != "":
                            call record_error(state, statement["value"], "bytearray_assignment", "TypeError", "ByteArray assignment requires an Int")
                            return
                        end
                        call semantic.unsupported(state["path"], state["lines"], statement["value"], "ByteArray assignment requires an Int", "convert the value with Int(...) before assignment")
                    end
                    call expression(state, statement["value"])
                else:
                    operator = statement["operator"][0:len(statement["operator"]) - 1]
                    combined = {"kind": "binary", "line": statement["line"], "column": statement["column"], "end_column": statement["end_column"], "operator": operator, "left": target, "right": statement["value"]}
                    combined_type = semantic.infer_expression_type(combined, state["types"], state["function_returns"])
                    if target_type == "IntArray" and combined_type != "Int":
                        if state["error_label"] != "":
                            call record_error(state, statement["value"], "intarray_augmented", "TypeError", "IntArray assignment requires an Int result")
                            return
                        end
                        call semantic.unsupported(state["path"], state["lines"], statement["value"], "IntArray assignment requires an Int result", "use integer arithmetic for augmented assignment")
                    elif target_type == "FloatArray" and combined_type != "Float":
                        if state["error_label"] != "":
                            call record_error(state, statement["value"], "floatarray_augmented", "TypeError", "FloatArray assignment requires a Float result")
                            return
                        end
                        call semantic.unsupported(state["path"], state["lines"], statement["value"], "FloatArray assignment requires a Float result", "use Float arithmetic for augmented assignment")
                    elif target_type == "ByteArray" and combined_type != "Int":
                        if state["error_label"] != "":
                            call record_error(state, statement["value"], "bytearray_augmented", "TypeError", "ByteArray assignment requires an Int result")
                            return
                        end
                        call semantic.unsupported(state["path"], state["lines"], statement["value"], "ByteArray assignment requires an Int result", "use integer arithmetic for augmented assignment")
                    end
                    call expression(state, combined)
                end
                if target_type == "Tuple":
                    if state["error_label"] != "":
                        call record_error(state, statement, "tuple_assignment", "TypeError", "Tuple items are immutable")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], statement, "Tuple items are immutable", "use List or RealArray for indexed mutation")
                elif target_type == "Dictionary":
                    value = None
                elif target_type == "List" or target_type == "RealArray" or target_type == "IntArray" or target_type == "FloatArray" or target_type == "ByteArray":
                    value = None
                else:
                    value = None
                end
            elif target["kind"] == "member":
                target_type = semantic.infer_expression_type(target["target"], state["types"], state["function_returns"])
                if not target_type.startswith("Class:") and not target_type.startswith("Instance:"):
                    if state["error_label"] != "":
                        call record_error(state, statement, "member_assignment", "TypeError", "member assignment requires a class instance")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], statement, "member assignment requires a class instance", "assign to self.field or an instance field")
                end
                call expression(state, target["target"])
                if statement["operator"] == "=":
                    call expression(state, statement["value"])
                else:
                    operator = statement["operator"][0:len(statement["operator"]) - 1]
                    combined = {"kind": "binary", "line": statement["line"], "column": statement["column"], "end_column": statement["end_column"], "operator": operator, "left": target, "right": statement["value"]}
                    call expression(state, combined)
                end
            else:
                call semantic.unsupported(state["path"], state["lines"], statement, "unsupported assignment target", "assign to a name, index, or instance field")
            end
        elif kind == "print":
            expressions = statement["expressions"]
            index = 0
            while index < len(expressions):
                call expression(state, expressions[index])
                index += 1
            end
        elif kind == "expression":
            call require_call_prefix(state, statement)
            call expression(state, statement["expression"])
        elif kind == "if":
            selected = semantic.constant_if_body(statement)
            if selected[0]:
                call statements(state, selected[1], break_label, continue_label, return_label)
            else:
                end_label = "if_end"
                branch_index = 0
                while branch_index < len(statement["branches"]):
                    branch = statement["branches"][branch_index]
                    if True:
                        call condition(state, branch[0])
                    end
                    call statements(state, branch[1], break_label, continue_label, return_label)
                    branch_index += 1
                end
                call statements(state, statement["otherwise"], break_label, continue_label, return_label)
            end
        elif kind == "while" or kind == "loop":
            constant_condition = [False, False]
            if kind == "while":
                constant_condition = semantic.constant_truth_expression(statement["condition"])
            end
            if kind == "while" and constant_condition[0] and not constant_condition[1]:
                continue
            end
            start_label = "loop_start"
            end_label = "loop_end"
            if kind == "while" and not constant_condition[0]:
                if True:
                    call condition(state, statement["condition"])
                end
            end
            call statements(state, statement["body"], end_label, start_label, return_label)
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
                call expression(state, iterable)
                iterable_type = semantic.infer_expression_type(iterable, state["types"], state["function_returns"])
                if iterable_type != "Any" and iterable_type != "Dictionary" and iterable_type != "Set" and not semantic.is_sequence_type(iterable_type):
                    if state["error_label"] != "":
                        call record_error(state, iterable, "iterable", "TypeError", "value of type " + iterable_type + " is not iterable")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], iterable, "value of type " + iterable_type + " is not iterable", "iterate a String, collection, typed array, or Dictionary")
                end
                start_label = "iter_start"
                continue_target = "iter_continue"
                end_label = "iter_end"
                call statements(state, statement["body"], end_label, continue_target, return_label)
                continue
            end
            arguments = iterable["arguments"]
            if "argument_names" in iterable:
                if state["error_label"] != "":
                    call record_error(state, iterable, "rang_keywords", "TypeError", "rang does not accept keyword arguments")
                    return
                end
                call semantic.unsupported(state["path"], state["lines"], iterable, "rang does not accept keyword arguments", "use positional arguments")
            end
            if len(arguments) < 1 or len(arguments) > 3:
                if state["error_label"] != "":
                    call record_error(state, statement, "rang_loop_arity", "TypeError", "rang expects one to three arguments")
                    return
                end
                call semantic.unsupported(state["path"], state["lines"], statement, "rang expects one to three arguments", "use rang(stop), rang(start, stop), or rang(start, stop, step)")
            end
            if len(arguments) == 1:
                start_expression = {"kind": "literal", "literal_kind": "number", "value": "0", "integer_value": 0, "line": statement["line"], "column": statement["column"], "end_column": statement["end_column"]}
                stop_expression = arguments[0]
            else:
                start_expression = arguments[0]
                stop_expression = arguments[1]
            end
            call checked_int(state, start_expression, "rang start")
            call checked_int(state, stop_expression, "rang stop")
            explicit_step = len(arguments) == 3
            if explicit_step:
                step_syntax = arguments[2]
                step_type = semantic.infer_expression_type(step_syntax, state["types"], state["function_returns"])
                if step_type != "Int" and step_type != "Any":
                    if state["error_label"] != "":
                        call record_error(state, step_syntax, "rang_step", "TypeError", "rang step must be an Int")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], step_syntax, "rang step must be an Int", "pass an Int expression with a non-zero value")
                end
                call expression(state, step_syntax)
            end
            start_label = "for_start"
            continue_target = "for_continue"
            end_label = "for_end"
            call statements(state, statement["body"], end_label, continue_target, return_label)
        elif kind == "break":
            if break_label == "":
                call semantic.unsupported(state["path"], state["lines"], statement, "break used outside a loop", "move break into while or loop")
            end
        elif kind == "continue":
            if continue_label == "":
                call semantic.unsupported(state["path"], state["lines"], statement, "continue used outside a loop", "move continue into while or loop")
            end
        elif kind == "unsafe":
            old_gc_unsafe = state.get("gc_unsafe", False)
            state["gc_unsafe"] = True
            call statements(state, statement["body"], break_label, continue_label, return_label)
            state["gc_unsafe"] = old_gc_unsafe
        elif kind == "safe":
            safe_failure = "safe_failure"
            old_error_label = state["error_label"]
            state["error_label"] = safe_failure
            call statements(state, statement["body"], break_label, continue_label, return_label)
            state["error_label"] = old_error_label
        elif kind == "try":
            try_failure = "try_failure"
            old_error_label = state["error_label"]
            state["error_label"] = try_failure
            call statements(state, statement["body"], break_label, continue_label, return_label)
            state["error_label"] = old_error_label
            call statements(state, statement["otherwise"], break_label, continue_label, return_label)
        elif kind == "error":
            error_message = statement["message"]
            if error_message["kind"] == "literal":
                if error_message["literal_kind"] == "string":
                    value = None
                else:
                    call expression(state, error_message)
                end
            elif error_message["kind"] == "name" and error_message["name"] not in state["variables"] and error_message["name"] not in state["global_variables"]:
                value = None
            else:
                call expression(state, error_message)
            end
        elif kind == "delete":
            target = statement["target"]
            if target["kind"] == "index":
                target_type = semantic.infer_expression_type(target["target"], state["types"], state["function_returns"])
                if target_type == "Tuple" or target_type == "RealArray":
                    if state["error_label"] != "":
                        call record_error(state, statement, "fixed_delete", "TypeError", "fixed collection does not support del")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], statement, "fixed collection does not support del", "convert it with List(value) before deleting")
                elif target_type == "ByteArray":
                    if state["error_label"] != "":
                        call record_error(state, statement, "bytearray_delete", "TypeError", "ByteArray deletion is not implemented")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], statement, "ByteArray deletion is not implemented", "use clear or overwrite indexed bytes")
                end
                if target_type == "List" or target_type == "IntArray" or target_type == "FloatArray":
                    delete_index = checked_index_node(state, target["index"])
                    delete_call = {"kind": "call", "line": statement["line"], "column": statement["column"], "end_column": statement["end_column"], "target": {"kind": "name", "name": "__lsl_delete_at"}, "arguments": [target["target"], delete_index]}
                    call expression(state, delete_call)
                elif target_type == "Dictionary" or target_type == "Any":
                    call expression(state, target["target"])
                    call expression(state, target["index"])
                    if target_type == "Any" and not state["internal_abi"]:
                        call dictionary_key(state, target["index"])
                    end
                else:
                    if state["error_label"] != "":
                        call record_error(state, statement, "delete_target", "TypeError", "value of type " + target_type + " does not support indexed deletion")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], statement, "value of type " + target_type + " does not support indexed deletion", "delete from a List, typed array, or Dictionary")
                end
            elif target["kind"] == "name":
                if target["name"] in state["variables"] or target["name"] in state["global_variables"]:
                    value = None
                else:
                    if state["error_label"] != "":
                        call record_error(state, statement, "delete_name", "NameError", "cannot delete unknown name " + target["name"])
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], statement, "cannot delete unknown name " + target["name"], "assign the name before deleting it")
                end
            elif target["kind"] == "member":
                target_type = semantic.infer_expression_type(target["target"], state["types"], state["function_returns"])
                if not target_type.startswith("Class:") and not target_type.startswith("Instance:"):
                    if state["error_label"] != "":
                        call record_error(state, statement, "delete_member", "TypeError", "member deletion requires a class instance")
                        return
                    end
                    call semantic.unsupported(state["path"], state["lines"], statement, "member deletion requires a class instance", "delete a field from an LSL class or instance")
                end
                call expression(state, target["target"])
            else:
                call semantic.unsupported(state["path"], state["lines"], statement, "unsupported del target", "delete a name, mutable index, Dictionary key, or instance field")
            end
        elif kind == "class":
            if statement["condition"] != None:
                call expression(state, statement["condition"])
            end
            for member in statement["body"]:
                if member["kind"] == "assign":
                    if member["target"]["kind"] != "name" or member["operator"] != "=":
                        call semantic.unsupported(state["path"], state["lines"], member, "class fields require simple assignment", "use name = value in the class body")
                    end
                    call expression(state, member["value"])
                elif member["kind"] != "function" and member["kind"] != "ctype":
                    call semantic.unsupported(state["path"], state["lines"], member, "unsupported class body statement", "use fields, ctype, and function methods")
                end
            end
        elif kind == "function" or kind == "global":
            value = None
        elif kind == "load":
            call semantic.unsupported(state["path"], state["lines"], statement, "load code generation reached the linked program", "check module linker lowering")
        elif kind == "return":
            if return_label == "":
                call semantic.unsupported(state["path"], state["lines"], statement, "return used outside a function", "move return into a function")
            end
            if statement["expression"] == None:
                value = None
            else:
                call expression(state, statement["expression"])
            end
        else:
            call semantic.unsupported(state["path"], state["lines"], statement, "statement kind " + kind + " is not implemented", "use scalar assignment, print, if, while, loop, break, or continue")
        end
        if kind == "return" or kind == "break" or kind == "continue" or kind == "error":
            break
        end
    end
end

# Pořadí odpovídá deklaracím a následnému hlavnímu tělu; konstantní mrtvé větve se nevalidují.
function check_function(state, unit, declaration):
    name = declaration["name"]
    scope = semantic.ensure_function_scope(unit, name)
    state["scope_name"] = name
    state["variables"] = scope["variables"]
    state["types"] = Dictionary(scope["types"])
    state["current_class_name"] = declaration.get("class_name", "")
    state["current_internal_function"] = declaration.get("internal_abi", False)
    state["internal_abi"] = unit["internal_abi"] and state["current_internal_function"]
    state["error_label"] = "function"
    call statements(state, declaration["body"], "", "", "function")
end

function prepare(unit):
    unit["validation_version"] = 1
    unit["validation_errors"] = {}
    unit["prepared_arguments"] = {}
    state = {"path": unit["path"], "lines": unit["source"], "scope_name": "", "global_variables": unit["variables"], "functions": unit["functions"], "classes": unit["classes"], "function_returns": unit["function_returns"], "function_parameters": unit["function_parameters"], "internal_abi": unit["internal_abi"], "unchecked_intarray": unit["unchecked_intarray"], "validation_errors": unit["validation_errors"], "prepared_arguments": unit["prepared_arguments"], "lazy_used": {}, "help_used": False}
    # Arity rules are immutable during one validation pass; constructing the
    # complete intrinsic catalog for every call dominated large-source builds.
    state["builtin_arity"] = builtin_arities()
    unit["validation_state"] = state
    unit["validation_checked"] = {}
    state["family_checked"] = {}
    lazy_functions = unit.get("lazy_functions", {})
    checked_functions = 0
    for statement in unit["program"]:
        if statement["kind"] == "function":
            if not help_family(statement["name"]) and not lazy_runtime(statement["name"]) and statement["name"] not in lazy_functions:
                call check_function(state, unit, statement)
                checked_functions += 1
            end
        elif statement["kind"] == "class":
            for member in statement["body"]:
                if member["kind"] == "function":
                    call check_function(state, unit, member)
                    checked_functions += 1
                end
            end
        end
        # Native functions/loops already poll the allocation budget. Retain a
        # sparse explicit checkpoint for bootstrap hosts, not a full-heap scan
        # after every small batch while the compiler AST remains live.
        if checked_functions >= 256:
            call gc()
            checked_functions = 0
        end
    end
    state["scope_name"] = ""
    state["variables"] = {}
    state["types"] = Dictionary(unit["types"])
    state["internal_abi"] = unit["internal_abi"]
    state["current_internal_function"] = False
    state["current_class_name"] = ""
    state["error_label"] = ""
    call statements(state, unit["program"], "", "", "")
    call check_families(state, unit)
    return unit
end

# Rodiny help a líného runtime: každá funkce nejvýš jednou, jakmile je použita.
function check_families(state, unit):
    checked = state["family_checked"]
    if state["help_used"]:
        for name in HELP_FAMILY:
            if name not in checked:
                checked[name] = True
                call check_function(state, unit, unit["functions"][name])
            end
        end
    end
    for name in LAZY_RUNTIME:
        if name in state["lazy_used"] and name not in checked:
            checked[name] = True
            call check_function(state, unit, unit["functions"][name])
        end
    end
end

# Validace funkce knihovny odložená v prepare: provede se při prvním použití
# generátorem kódu (stejně jako v prepare, jen později a jen pro použité).
function ensure_function_checked(unit, name):
    if name not in unit.get("lazy_functions", {}) or help_family(name) or lazy_runtime(name):
        return None
    end
    checked = unit["validation_checked"]
    if name in checked:
        return None
    end
    checked[name] = True
    state = unit["validation_state"]
    call check_function(state, unit, unit["functions"][name])
    call check_families(state, unit)
    return None
end
