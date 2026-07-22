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

call require_success(run(compiler, ["tests/collection_repr_conformance.lsl", "/tmp/lsl-collection-repr-test"]), "compile collection repr conformance")
collection_repr_output = capture("/tmp/lsl-collection-repr-test", [])
if collection_repr_output != readfile("tests/collection_repr_conformance.out"):
    Error(TestFailure: "collection repr conformance output differs")
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
