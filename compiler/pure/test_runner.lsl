# Pure-LSL regression runner. It invokes only LSL-generated syscall-only ELFs.
# Positive conformance modules are linked into one program so parser/runtime
# generation is paid once while every original source span remains intact.

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

function require_output(program, arguments, expected_path, name):
    actual = capture(program, arguments)
    if actual != readfile(expected_path):
        Error(TestFailure: name)
    end
end

function aggregate_expected():
    result = ""
    for line in readfile("tests/full_conformance.lsl").split(chr(10)):
        if line.startswith("load "):
            result += readfile("tests/" + line[5:len(line)] + ".out")
        end
    end
    return result
end

mode = arg(1)
compiler = arg(2)
if mode == None:
    mode = "full"
elif mode != "fast" and mode != "full" and mode != "fixed-point":
    # Backward-compatible developer override: lsl-test /tmp/candidate-lslc
    compiler = mode
    mode = "full"
end
if compiler == None:
    compiler = "./compiler/pure/lslc-direct"
end

if mode == "fixed-point":
    call require_success(run(compiler, ["compiler/pure/lslc_direct.lsl", "/tmp/lsl-fixed-test"]), "compile fixed-point stage")
    if readfile(compiler) != readfile("/tmp/lsl-fixed-test"):
        Error(TestFailure: "compiler fixed point differs")
    end
    print "pure LSL fixed point passed"
    exit(0)
end

# Standalone smoke/fixed-table programs cannot safely share aggregate state.
call require_success(run(compiler, ["compiler/pure/scalar_smoke.lsl", "/tmp/lsl-scalar-test"]), "compile scalar smoke")
call require_success(run("/tmp/lsl-scalar-test", []), "run scalar smoke")
call require_success(run(compiler, ["compiler/pure/float_smoke.lsl", "/tmp/lsl-float-test"]), "compile Float smoke")
call require_success(run("/tmp/lsl-float-test", []), "run Float smoke")
call require_success(run(compiler, ["tests/selfhost_conformance.lsl", "/tmp/lsl-selfhost-test"]), "compile selfhost conformance")
call require_output("/tmp/lsl-selfhost-test", [], "tests/selfhost_conformance.out", "selfhost conformance output differs")
call require_success(run(compiler, ["tests/table_growth_conformance.lsl", "/tmp/lsl-table-growth-test"]), "compile table growth conformance")
call require_output("/tmp/lsl-table-growth-test", [], "tests/table_growth_conformance.out", "table growth conformance output differs")

# Process clients in the aggregate require independently executable children.
servers = [
    ["tests/capture_large_server.lsl", "/tmp/lsl-capture-large-server"],
    ["tests/capture_stream_server.lsl", "/tmp/lsl-capture-stream-server"],
    ["tests/capture_result_server.lsl", "/tmp/lsl-capture-result-server"],
    ["tests/process_status_server.lsl", "/tmp/lsl-process-status-server"],
    ["tests/plugin_process_server.lsl", "/tmp/lsl-plugin-process-server"]
]
for server in servers:
    call require_success(run(compiler, server), "compile process conformance server")
end

call require_success(run(compiler, ["tests/full_conformance.lsl", "/tmp/lsl-full-conformance-test"]), "compile aggregated conformance")
aggregate_output = capture("/tmp/lsl-full-conformance-test", [])
if aggregate_output != aggregate_expected():
    Error(TestFailure: "aggregated conformance output differs")
end

if mode == "fast":
    print "pure LSL fast tests passed"
    exit(0)
end

# Compile-time diagnostics must remain failures and retain original source spans.
call require_failure(run(compiler, ["tests/builtin_arity_negative.lsl", "/tmp/lsl-arity-negative"]), "builtin arity mismatch unexpectedly compiled")
call require_failure(run(compiler, ["tests/method_arity_negative.lsl", "/tmp/lsl-method-negative"]), "method arity mismatch unexpectedly compiled")
call require_failure(run(compiler, ["tests/fixed_collection_negative.lsl", "/tmp/lsl-fixed-negative"]), "fixed collection mutation unexpectedly compiled")
call require_failure(run(compiler, ["tests/private_class_negative.lsl", "/tmp/lsl-private-negative"]), "private module class unexpectedly compiled")
call require_failure(run(compiler, ["tests/dictionary_key_negative.lsl", "/tmp/lsl-dictionary-key-negative"]), "collection Dictionary key unexpectedly compiled")

configure = "./compiler/pure/lsl-configure"
config_wrapper = "tests/config/.defaults-test-evaluator.lsl"
call require_success(run(configure, ["tests/config/defaults.lsl", config_wrapper]), "generate config defaults evaluator")
call require_success(run(compiler, [config_wrapper, "/tmp/lsl-config-defaults-test"]), "compile config defaults evaluator")
call unlink(config_wrapper)
call require_output("/tmp/lsl-config-defaults-test", [], "tests/config/defaults.out", "config defaults output differs")

lazy_wrapper = "tests/config/.lazy-test-evaluator.lsl"
call require_success(run(configure, ["tests/config/lazy.lsl", lazy_wrapper]), "generate lazy config evaluator")
call require_success(run(compiler, [lazy_wrapper, "/tmp/lsl-config-lazy-test"]), "compile lazy config evaluator")
call unlink(lazy_wrapper)
call require_output("/tmp/lsl-config-lazy-test", [], "tests/config/lazy.out", "lazy config output differs")

type_error_wrapper = "tests/config/.type-error-test-evaluator.lsl"
call require_success(run(configure, ["tests/config/type_error.lsl", type_error_wrapper]), "generate config type-error evaluator")
call require_success(run(compiler, [type_error_wrapper, "/tmp/lsl-config-type-error-test"]), "compile config type-error evaluator")
call unlink(type_error_wrapper)
call require_output("/tmp/lsl-config-type-error-test", [], "tests/config/type_error.out", "config type-error provenance differs")

config_cycle_output = capture(configure, ["tests/config/cycle_a.lsl", "/tmp/lsl-cycle-evaluator.lsl"])
if config_cycle_output != readfile("tests/config/cycle.out"):
    Error(TestFailure: "config cycle diagnostic differs")
end

call require_success(run(compiler, ["compiler/pure/lslc_direct.lsl", "/tmp/lsl-fixed-test"]), "compile fixed-point stage")
if readfile(compiler) != readfile("/tmp/lsl-fixed-test"):
    Error(TestFailure: "compiler fixed point differs")
end

print "pure LSL tests passed"
