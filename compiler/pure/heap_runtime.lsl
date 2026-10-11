# Kompatibilní vstup; strojová implementace je explicitně Linux x86_64.

load heap_runtime_linux_x86_64 as implementation

function emit_pending_error_data(output, label, message):
    return implementation.emit_pending_error_data(output, label, message)
end

function emit_pending_error_return(output, label, data_label, message):
    return implementation.emit_pending_error_return(output, label, data_label, message)
end

function emit_allocator(output):
    return implementation.emit_allocator(output)
end

function emit_object_table_growth(output):
    return implementation.emit_object_table_growth(output)
end

function emit_object_checks(output):
    return implementation.emit_object_checks(output)
end

function emit_parse_literal_int(output):
    return implementation.emit_parse_literal_int(output)
end

function emit_int_power(output):
    return implementation.emit_int_power(output)
end

function emit_float_power(output):
    return implementation.emit_float_power(output)
end

function emit_string_concat(output):
    return implementation.emit_string_concat(output)
end

function emit_intern_table_growth(output):
    return implementation.emit_intern_table_growth(output)
end

function emit_string_clone(output):
    return implementation.emit_string_clone(output)
end

function emit_float_binary(output, name, operation):
    return implementation.emit_float_binary(output, name, operation)
end

function emit_float_candidate_byte(output, value):
    return implementation.emit_float_candidate_byte(output, value)
end

function emit_float_runtime(output):
    return implementation.emit_float_runtime(output)
end

function emit_boxed_scalars(output):
    return implementation.emit_boxed_scalars(output)
end

function emit_gc(output):
    return implementation.emit_gc(output)
end

function emit_byte_array(output):
    return implementation.emit_byte_array(output)
end

function emit_list_new(output):
    return implementation.emit_list_new(output)
end

function emit_list_append(output):
    return implementation.emit_list_append(output)
end

function emit_list_pop_last(output):
    return implementation.emit_list_pop_last(output)
end

function emit_list_clear(output):
    return implementation.emit_list_clear(output)
end

function emit_set(output):
    return implementation.emit_set(output)
end

function emit_list_set(output):
    return implementation.emit_list_set(output)
end

function emit_list_get(output):
    return implementation.emit_list_get(output)
end

function emit_length(output):
    return implementation.emit_length(output)
end

function emit_get(output):
    return implementation.emit_get(output)
end

function emit_dynamic_collections(output):
    return implementation.emit_dynamic_collections(output)
end

function emit_string_byte_offset(output):
    return implementation.emit_string_byte_offset(output)
end

function emit_slice(output):
    return implementation.emit_slice(output)
end

function emit_string_equal(output):
    return implementation.emit_string_equal(output)
end

function emit_string_contains(output):
    return implementation.emit_string_contains(output)
end

function emit_equal_any(output):
    return implementation.emit_equal_any(output)
end

function emit_is_float(output):
    return implementation.emit_is_float(output)
end

function emit_coerce_float(output):
    return implementation.emit_coerce_float(output)
end

function emit_numeric_value_guard(output):
    return implementation.emit_numeric_value_guard(output)
end

function emit_checked_index(output):
    return implementation.emit_checked_index(output)
end

function emit_numeric_pair_guard(output):
    return implementation.emit_numeric_pair_guard(output)
end

function emit_abs_any(output):
    return implementation.emit_abs_any(output)
end

function emit_compare_any(output):
    return implementation.emit_compare_any(output)
end

function emit_neg_any(output):
    return implementation.emit_neg_any(output)
end

function emit_pow_any(output):
    return implementation.emit_pow_any(output)
end

function emit_num_any(output, name, float_routine, is_add):
    return implementation.emit_num_any(output, name, float_routine, is_add)
end

function emit_dynamic_raw_wrapper(output, name):
    return implementation.emit_dynamic_raw_wrapper(output, name)
end

function emit_contains(output):
    return implementation.emit_contains(output)
end

function emit_dict_hash(output):
    return implementation.emit_dict_hash(output)
end

function emit_dict_probe(output):
    return implementation.emit_dict_probe(output)
end

function emit_dict_index_insert(output):
    return implementation.emit_dict_index_insert(output)
end

function emit_dict_reindex(output):
    return implementation.emit_dict_reindex(output)
end

function emit_dict_new(output):
    return implementation.emit_dict_new(output)
end

function emit_dict_get(output):
    return implementation.emit_dict_get(output)
end

function emit_dict_keys(output):
    return implementation.emit_dict_keys(output)
end

function emit_dict_delete(output):
    return implementation.emit_dict_delete(output)
end

function emit_dict_grow(output):
    return implementation.emit_dict_grow(output)
end

function emit_dict_set(output):
    return implementation.emit_dict_set(output)
end

function emit_string_chars(output):
    return implementation.emit_string_chars(output)
end

function emit_float_array_kernels(output):
    return implementation.emit_float_array_kernels(output)
end

function emit_all(output):
    return implementation.emit_all(output)
end
