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
