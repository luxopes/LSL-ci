# Pure-LSL regression runner. It invokes only LSL-generated syscall-only ELFs.

function require_success(status, name):
    if status != 0:
        Error(TestFailure: name)
    end
end

function require_failure(status, name):
    if status == 0:
        Error(TestFailure: name)
    end
end

compiler = "./compiler/pure/lslc-direct"

call require_success(run(compiler, ["compiler/pure/scalar_smoke.lsl", "/tmp/lsl-scalar-test"]), "compile scalar smoke")
call require_success(run("/tmp/lsl-scalar-test", []), "run scalar smoke")

call require_success(run(compiler, ["compiler/pure/float_smoke.lsl", "/tmp/lsl-float-test"]), "compile Float smoke")
call require_success(run("/tmp/lsl-float-test", []), "run Float smoke")

call require_success(run(compiler, ["tests/selfhost_conformance.lsl", "/tmp/lsl-selfhost-test"]), "compile selfhost conformance")
selfhost_output = capture("/tmp/lsl-selfhost-test", [])
if selfhost_output != readfile("tests/selfhost_conformance.out"):
    Error(TestFailure: "selfhost conformance output differs")
end

call require_success(run(compiler, ["tests/runtime_error_conformance.lsl", "/tmp/lsl-runtime-error-test"]), "compile runtime error conformance")
runtime_error_output = capture("/tmp/lsl-runtime-error-test", [])
if runtime_error_output != readfile("tests/runtime_error_conformance.out"):
    Error(TestFailure: "runtime error conformance output differs")
end

call require_success(run(compiler, ["tests/io_error_conformance.lsl", "/tmp/lsl-io-error-test"]), "compile I/O error conformance")
io_error_output = capture("/tmp/lsl-io-error-test", [])
if io_error_output != readfile("tests/io_error_conformance.out"):
    Error(TestFailure: "I/O error conformance output differs")
end

call require_success(run(compiler, ["tests/io_conformance.lsl", "/tmp/lsl-io-test"]), "compile I/O conformance")
io_output = capture("/tmp/lsl-io-test", [])
if io_output != readfile("tests/io_conformance.out"):
    Error(TestFailure: "I/O conformance output differs")
end

call require_success(run(compiler, ["tests/capture_large_server.lsl", "/tmp/lsl-capture-large-server"]), "compile large capture server")
call require_success(run(compiler, ["tests/capture_large_conformance.lsl", "/tmp/lsl-capture-large-test"]), "compile large capture conformance")
capture_large_output = capture("/tmp/lsl-capture-large-test", [])
if capture_large_output != readfile("tests/capture_large_conformance.out"):
    Error(TestFailure: "large capture conformance output differs")
end

call require_success(run(compiler, ["tests/magic_division_conformance.lsl", "/tmp/lsl-magic-division-test"]), "compile magic division conformance")
magic_division_output = capture("/tmp/lsl-magic-division-test", [])
if magic_division_output != readfile("tests/magic_division_conformance.out"):
    Error(TestFailure: "magic division conformance output differs")
end

call require_success(run(compiler, ["tests/equality_conformance.lsl", "/tmp/lsl-equality-test"]), "compile equality conformance")
equality_output = capture("/tmp/lsl-equality-test", [])
if equality_output != readfile("tests/equality_conformance.out"):
    Error(TestFailure: "equality conformance output differs")
end

call require_success(run(compiler, ["tests/dynamic_arith_conformance.lsl", "/tmp/lsl-dynamic-arith-test"]), "compile dynamic arith conformance")
dynamic_arith_output = capture("/tmp/lsl-dynamic-arith-test", [])
if dynamic_arith_output != readfile("tests/dynamic_arith_conformance.out"):
    Error(TestFailure: "dynamic arith conformance output differs")
end

call require_success(run(compiler, ["tests/dict_keys_conformance.lsl", "/tmp/lsl-dict-keys-test"]), "compile dict keys conformance")
dict_keys_output = capture("/tmp/lsl-dict-keys-test", [])
if dict_keys_output != readfile("tests/dict_keys_conformance.out"):
    Error(TestFailure: "dict keys conformance output differs")
end

call require_success(run(compiler, ["tests/unicode_case_conformance.lsl", "/tmp/lsl-unicode-case-test"]), "compile unicode case conformance")
unicode_case_output = capture("/tmp/lsl-unicode-case-test", [])
if unicode_case_output != readfile("tests/unicode_case_conformance.out"):
    Error(TestFailure: "unicode case conformance output differs")
end

call require_success(run(compiler, ["tests/slice_step_conformance.lsl", "/tmp/lsl-slice-step-test"]), "compile slice step conformance")
slice_step_output = capture("/tmp/lsl-slice-step-test", [])
if slice_step_output != readfile("tests/slice_step_conformance.out"):
    Error(TestFailure: "slice step conformance output differs")
end

call require_success(run(compiler, ["tests/string_conversion_conformance.lsl", "/tmp/lsl-string-conversion-test"]), "compile string conversion conformance")
string_conversion_output = capture("/tmp/lsl-string-conversion-test", [])
if string_conversion_output != readfile("tests/string_conversion_conformance.out"):
    Error(TestFailure: "string conversion conformance output differs")
end

call require_success(run(compiler, ["tests/abs_conformance.lsl", "/tmp/lsl-abs-test"]), "compile abs conformance")
abs_output = capture("/tmp/lsl-abs-test", [])
if abs_output != readfile("tests/abs_conformance.out"):
    Error(TestFailure: "abs conformance output differs")
end

call require_success(run(compiler, ["tests/numeric_builtins_conformance.lsl", "/tmp/lsl-numeric-builtins-test"]), "compile numeric builtins conformance")
numeric_builtins_output = capture("/tmp/lsl-numeric-builtins-test", [])
if numeric_builtins_output != readfile("tests/numeric_builtins_conformance.out"):
    Error(TestFailure: "numeric builtins conformance output differs")
end

call require_success(run(compiler, ["tests/float_floordiv_conformance.lsl", "/tmp/lsl-float-floordiv-test"]), "compile float floordiv conformance")
float_floordiv_output = capture("/tmp/lsl-float-floordiv-test", [])
if float_floordiv_output != readfile("tests/float_floordiv_conformance.out"):
    Error(TestFailure: "float floordiv conformance output differs")
end

call require_success(run(compiler, ["tests/recursive_return_conformance.lsl", "/tmp/lsl-recursive-return-test"]), "compile recursive return conformance")
recursive_return_output = capture("/tmp/lsl-recursive-return-test", [])
if recursive_return_output != readfile("tests/recursive_return_conformance.out"):
    Error(TestFailure: "recursive return conformance output differs")
end

call require_success(run(compiler, ["tests/float_exponent_conformance.lsl", "/tmp/lsl-float-exponent-test"]), "compile Float exponent conformance")
float_exponent_output = capture("/tmp/lsl-float-exponent-test", [])
if float_exponent_output != readfile("tests/float_exponent_conformance.out"):
    Error(TestFailure: "Float exponent conformance output differs")
end

call require_success(run(compiler, ["tests/float_special_conformance.lsl", "/tmp/lsl-float-special-test"]), "compile Float special conformance")
float_special_output = capture("/tmp/lsl-float-special-test", [])
if float_special_output != readfile("tests/float_special_conformance.out"):
    Error(TestFailure: "Float special conformance output differs")
end

call require_success(run(compiler, ["tests/float_format_conformance.lsl", "/tmp/lsl-float-format-test"]), "compile Float format conformance")
float_format_output = capture("/tmp/lsl-float-format-test", [])
if float_format_output != readfile("tests/float_format_conformance.out"):
    Error(TestFailure: "Float format conformance output differs")
end

call require_success(run(compiler, ["tests/float_power_conformance.lsl", "/tmp/lsl-float-power-test"]), "compile Float power conformance")
float_power_output = capture("/tmp/lsl-float-power-test", [])
if float_power_output != readfile("tests/float_power_conformance.out"):
    Error(TestFailure: "Float power conformance output differs")
end

call require_success(run(compiler, ["tests/float_conversion_conformance.lsl", "/tmp/lsl-float-conversion-test"]), "compile Float conversion conformance")
float_conversion_output = capture("/tmp/lsl-float-conversion-test", [])
if float_conversion_output != readfile("tests/float_conversion_conformance.out"):
    Error(TestFailure: "Float conversion conformance output differs")
end

call require_success(run(compiler, ["tests/minmax_help_conformance.lsl", "/tmp/lsl-minmax-help-test"]), "compile minmax/help conformance")
minmax_help_output = capture("/tmp/lsl-minmax-help-test", [])
if minmax_help_output != readfile("tests/minmax_help_conformance.out"):
    Error(TestFailure: "minmax/help conformance output differs")
end

call require_success(run(compiler, ["tests/truthiness_conformance.lsl", "/tmp/lsl-truthiness-test"]), "compile truthiness conformance")
truthiness_output = capture("/tmp/lsl-truthiness-test", [])
if truthiness_output != readfile("tests/truthiness_conformance.out"):
    Error(TestFailure: "truthiness conformance output differs")
end

call require_success(run(compiler, ["tests/del_conformance.lsl", "/tmp/lsl-del-test"]), "compile del conformance")
del_output = capture("/tmp/lsl-del-test", [])
if del_output != readfile("tests/del_conformance.out"):
    Error(TestFailure: "del conformance output differs")
end

call require_success(run(compiler, ["tests/sequence_ops_conformance.lsl", "/tmp/lsl-sequence-ops-test"]), "compile sequence ops conformance")
sequence_ops_output = capture("/tmp/lsl-sequence-ops-test", [])
if sequence_ops_output != readfile("tests/sequence_ops_conformance.out"):
    Error(TestFailure: "sequence ops conformance output differs")
end

call require_success(run(compiler, ["tests/indexed_augmented_conformance.lsl", "/tmp/lsl-indexed-augmented-test"]), "compile indexed augmented conformance")
indexed_augmented_output = capture("/tmp/lsl-indexed-augmented-test", [])
if indexed_augmented_output != readfile("tests/indexed_augmented_conformance.out"):
    Error(TestFailure: "indexed augmented conformance output differs")
end

call require_success(run(compiler, ["tests/rang_dynamic_conformance.lsl", "/tmp/lsl-rang-dynamic-test"]), "compile dynamic rang conformance")
rang_dynamic_output = capture("/tmp/lsl-rang-dynamic-test", [])
if rang_dynamic_output != readfile("tests/rang_dynamic_conformance.out"):
    Error(TestFailure: "dynamic rang conformance output differs")
end

call require_success(run(compiler, ["tests/collection_repr_conformance.lsl", "/tmp/lsl-collection-repr-test"]), "compile collection repr conformance")
collection_repr_output = capture("/tmp/lsl-collection-repr-test", [])
if collection_repr_output != readfile("tests/collection_repr_conformance.out"):
    Error(TestFailure: "collection repr conformance output differs")
end

call require_success(run(compiler, ["tests/collection_methods_conformance.lsl", "/tmp/lsl-collection-methods-test"]), "compile collection methods conformance")
collection_methods_output = capture("/tmp/lsl-collection-methods-test", [])
if collection_methods_output != readfile("tests/collection_methods_conformance.out"):
    Error(TestFailure: "collection methods conformance output differs")
end

call require_success(run(compiler, ["tests/int_conversion_conformance.lsl", "/tmp/lsl-int-conversion-test"]), "compile Int conversion conformance")
int_conversion_output = capture("/tmp/lsl-int-conversion-test", [])
if int_conversion_output != readfile("tests/int_conversion_conformance.out"):
    Error(TestFailure: "Int conversion conformance output differs")
end

call require_success(run(compiler, ["tests/dynamic_value_conformance.lsl", "/tmp/lsl-dynamic-value-test"]), "compile dynamic value conformance")
dynamic_value_output = capture("/tmp/lsl-dynamic-value-test", [])
if dynamic_value_output != readfile("tests/dynamic_value_conformance.out"):
    Error(TestFailure: "dynamic value conformance output differs")
end

call require_success(run(compiler, ["tests/realarray_conformance.lsl", "/tmp/lsl-realarray-test"]), "compile RealArray conformance")
realarray_output = capture("/tmp/lsl-realarray-test", [])
if realarray_output != readfile("tests/realarray_conformance.out"):
    Error(TestFailure: "RealArray conformance output differs")
end

call require_failure(run(compiler, ["tests/builtin_arity_negative.lsl", "/tmp/lsl-arity-negative"]), "builtin arity mismatch unexpectedly compiled")
call require_failure(run(compiler, ["tests/method_arity_negative.lsl", "/tmp/lsl-method-negative"]), "method arity mismatch unexpectedly compiled")
call require_failure(run(compiler, ["tests/fixed_collection_negative.lsl", "/tmp/lsl-fixed-negative"]), "fixed collection mutation unexpectedly compiled")
call require_failure(run(compiler, ["tests/private_class_negative.lsl", "/tmp/lsl-private-negative"]), "private module class unexpectedly compiled")

call require_success(run(compiler, ["tests/plugin_process_server.lsl", "/tmp/lsl-plugin-process-server"]), "compile process plugin server")
call require_success(run(compiler, ["tests/plugin_process_conformance.lsl", "/tmp/lsl-plugin-process-test"]), "compile process plugin conformance")
plugin_process_output = capture("/tmp/lsl-plugin-process-test", [])
if plugin_process_output != readfile("tests/plugin_process_conformance.out"):
    Error(TestFailure: "process plugin conformance output differs")
end

call require_success(run(compiler, ["compiler/pure/lslc_direct.lsl", "/tmp/lsl-fixed-test"]), "compile fixed-point stage")
if readfile(compiler) != readfile("/tmp/lsl-fixed-test"):
    Error(TestFailure: "compiler fixed point differs")
end

print "pure LSL tests passed"
