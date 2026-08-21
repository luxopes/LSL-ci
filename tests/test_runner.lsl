# Pure-LSL regression runner. It invokes only LSL-generated syscall-only ELFs.
# Positive conformance modules are linked into one program so parser/runtime
# generation is paid once while every original source span remains intact.

load env

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
call require_success(run(compiler, ["tests/compiler/scalar_smoke.lsl", "/tmp/lsl-scalar-test"]), "compile scalar smoke")
call require_success(run("/tmp/lsl-scalar-test", []), "run scalar smoke")
call require_success(run(compiler, ["tests/compiler/float_smoke.lsl", "/tmp/lsl-float-test"]), "compile Float smoke")
call require_success(run("/tmp/lsl-float-test", []), "run Float smoke")
call require_success(run(compiler, ["tests/codegen_optimization_conformance.lsl", "/tmp/lsl-codegen-optimization-test"]), "compile codegen optimization conformance")
call require_output("/tmp/lsl-codegen-optimization-test", [], "tests/codegen_optimization_conformance.out", "codegen optimization output differs")
if len(readbytes("/tmp/lsl-codegen-optimization-test")) > 64000:
    Error(TestFailure: "optimized standalone ELF exceeds 64000 bytes")
end
call require_success(run(compiler, ["compiler/pure/cli.lsl", "/tmp/lsl-stdin-cli-test"]), "compile stdin CLI")
help_output = capture("/tmp/lsl-stdin-cli-test", ["--help"])
expected_help = "Lux Simple Lang (LSL) 0.6.4" + chr(10)
expected_help += chr(10)
expected_help += "Usage:" + chr(10)
expected_help += "  lsl [SOURCE [ARG...]]" + chr(10)
expected_help += "  lsl compile SOURCE OUTPUT" + chr(10)
expected_help += "  lsl config ENTRY" + chr(10)
expected_help += "  lsl install NAME" + chr(10)
expected_help += "  lsl install --config FILE" + chr(10)
expected_help += "  lsl update NAME" + chr(10)
expected_help += "  lsl server" + chr(10)
expected_help += "  lsl version" + chr(10)
expected_help += chr(10)
expected_help += "Options:" + chr(10)
expected_help += "  -h, --help     Show this help" + chr(10)
expected_help += "  --version      Show version" + chr(10)
if capture_status() != 0 or help_output != expected_help:
    Error(TestFailure: "CLI --help output differs")
end
version_output = capture("/tmp/lsl-stdin-cli-test", ["version"])
if capture_status() != 0 or version_output != "0.6.4" + chr(10):
    Error(TestFailure: "CLI version output differs")
end
version_flag_output = capture("/tmp/lsl-stdin-cli-test", ["--version"])
if capture_status() != 0 or version_flag_output != "0.6.4" + chr(10):
    Error(TestFailure: "CLI --version output differs")
end
stdin_source = "value = 6 * 7" + chr(10) + "if value == 42:" + chr(10) + "    print \"stdin\", value" + chr(10) + "end" + chr(10) + "exit" + chr(10)
stdin_output = capture_input("/tmp/lsl-stdin-cli-test", [], stdin_source)
if capture_status() != 0 or stdin_output != "stdin 42" + chr(10):
    Error(TestFailure: "stdin CLI terminated source differs")
end
eof_output = capture_input("/tmp/lsl-stdin-cli-test", [], "print \"eof\", 9" + chr(10))
if capture_status() != 0 or eof_output != "eof 9" + chr(10):
    Error(TestFailure: "stdin CLI EOF source differs")
end
time_output = capture_input("/tmp/lsl-stdin-cli-test", [], "load time" + chr(10) + "print time.time() > 1577836800.0" + chr(10) + "exit" + chr(10))
if capture_status() != 0 or time_output != "True" + chr(10):
    Error(TestFailure: "stdin CLI module lookup differs")
end
exit_output = capture_input("/tmp/lsl-stdin-cli-test", [], "exit(7)" + chr(10) + "exit" + chr(10))
if capture_status() != 7 or exit_output != "":
    Error(TestFailure: "stdin CLI exact exit terminator differs")
end

# Per-user source libraries use a strict name/hash/compile/atomic-move path, and
# built-in modules retain precedence over the user directory.
call require_success(run(compiler, ["tests/compiler/package_command_server.lsl", "/tmp/lsl-package-command-server"]), "compile package command server")
call require_success(run(compiler, ["tests/compiler/package_install_conformance.lsl", "/tmp/lsl-package-install-test"]), "compile package install conformance")
call require_success(run(compiler, ["tests/compiler/package_update_config_conformance.lsl", "/tmp/lsl-package-update-config-test"]), "compile package update/config conformance")
call require_success(run(compiler, ["tests/compiler/package_config_negative.lsl", "/tmp/lsl-package-config-negative"]), "compile package config negative test")
package_home = "/tmp/lsl-package-home"
call mkdir(package_home)
call mkdir(package_home + "/.local")
call mkdir(package_home + "/.local/lib")
call mkdir(package_home + "/.local/lib/lsl")
call mkdir(package_home + "/.local/lib/lsl/stdlib")
package_destination = package_home + "/.local/lib/lsl/stdlib/registry_probe.lsl"
if exists(package_destination):
    call unlink(package_destination)
end
package_arguments = ["registry_probe", package_home, "http://127.0.0.1:8080/lsl", "/tmp/lsl-package-command-server", "/tmp/lsl-stdin-cli-test"]
call require_output("/tmp/lsl-package-install-test", package_arguments, "tests/compiler/package_install_conformance.out", "package install output differs")
if not exists(package_destination):
    Error(TestFailure: "package install did not create the user module")
end
call unlink(package_destination)
bad_hash_arguments = ["registry_probe", package_home, "http://127.0.0.1:8080/bad", "/tmp/lsl-package-command-server", "/tmp/lsl-stdin-cli-test"]
call require_failure(run("/tmp/lsl-package-install-test", bad_hash_arguments), "package hash mismatch unexpectedly installed")
if exists(package_destination):
    Error(TestFailure: "package hash failure left an installed module")
end
bad_name_arguments = ["Bad/Name", package_home, "http://127.0.0.1:8080/lsl", "/tmp/lsl-package-command-server", "/tmp/lsl-stdin-cli-test"]
call require_failure(run("/tmp/lsl-package-install-test", bad_name_arguments), "unsafe package name unexpectedly installed")
package_config = "/tmp/lsl-package-list.conf"
call writefile(package_config, "# libraries" + chr(10) + "config_probe" + chr(10) + "second_probe" + chr(10))
update_arguments = [package_home, "http://127.0.0.1:8080/lsl", "/tmp/lsl-package-command-server", "/tmp/lsl-stdin-cli-test", package_config]
call require_success(run("/tmp/lsl-package-update-config-test", update_arguments), "package update/config install failed")
call writefile(package_config, "duplicate" + chr(10) + "duplicate" + chr(10))
call require_failure(run("/tmp/lsl-package-config-negative", [package_config]), "duplicate config library unexpectedly accepted")
call writefile(package_config, "bad name" + chr(10))
call require_failure(run("/tmp/lsl-package-config-negative", [package_config]), "unsafe config library unexpectedly accepted")
call require_success(run(compiler, ["tests/compiler/user_module_path_conformance.lsl", "/tmp/lsl-user-module-path-test"]), "compile user module path conformance")
call require_output("/tmp/lsl-user-module-path-test", [], "tests/compiler/user_module_path_conformance.out", "user module path output differs")

call require_success(run(compiler, ["tests/selfhost_conformance.lsl", "/tmp/lsl-selfhost-test"]), "compile selfhost conformance")
call require_output("/tmp/lsl-selfhost-test", [], "tests/selfhost_conformance.out", "selfhost conformance output differs")
call require_success(run(compiler, ["tests/table_growth_conformance.lsl", "/tmp/lsl-table-growth-test"]), "compile table growth conformance")
call require_output("/tmp/lsl-table-growth-test", [], "tests/table_growth_conformance.out", "table growth conformance output differs")

# Process clients in the aggregate require independently executable children.
servers = [
    ["tests/capture_large_server.lsl", "/tmp/lsl-capture-large-server"],
    ["tests/capture_stream_server.lsl", "/tmp/lsl-capture-stream-server"],
    ["tests/capture_result_server.lsl", "/tmp/lsl-capture-result-server"],
    ["tests/input_conformance.lsl", "/tmp/lsl-input-server"],
    ["tests/input_bare_server.lsl", "/tmp/lsl-input-bare-server"],
    ["tests/process_status_server.lsl", "/tmp/lsl-process-status-server"],
    ["tests/plugin_process_server.lsl", "/tmp/lsl-plugin-process-server"],
    ["tests/cuda_worker.lsl", "/tmp/lsl-cuda-worker"],
    ["tests/os_command_server.lsl", "/tmp/lsl-os-command-server"],
    ["tests/system_package_server.lsl", "/tmp/lsl-system-package-server"],
    ["tests/system_command_server.lsl", "/tmp/lsl-system-command-apt"],
    ["tests/system_command_server.lsl", "/tmp/lsl-system-command-systemctl"],
    ["tests/system_command_server.lsl", "/tmp/lsl-system-command-account"],
    ["tests/system_command_server.lsl", "/tmp/lsl-system-command-file-tool"],
    ["tests/system_command_server.lsl", "/tmp/lsl-system-command-mount-tool"],
    ["tests/system_command_server.lsl", "/tmp/lsl-system-command-lux"]
]
for server in servers:
    call require_success(run(compiler, server), "compile process conformance server")
end

if env.get("LSL_CUDA_HARDWARE_TEST", "0") == "1":
    call require_success(run(compiler, ["tests/cuda_hardware_conformance.lsl", "/tmp/lsl-cuda-hardware-test"]), "compile CUDA hardware conformance")
    call require_success(run("/tmp/lsl-cuda-hardware-test", []), "run CUDA hardware conformance")
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

call require_success(run(compiler, ["tests/json_fuzz_conformance.lsl", "/tmp/lsl-json-fuzz-test"]), "compile JSON fuzz conformance")
call require_output("/tmp/lsl-json-fuzz-test", [], "tests/json_fuzz_conformance.out", "JSON fuzz conformance output differs")
call require_success(run(compiler, ["tests/gc_stress_conformance.lsl", "/tmp/lsl-gc-stress-test"]), "compile GC stress conformance")
call require_output("/tmp/lsl-gc-stress-test", [], "tests/gc_stress_conformance.out", "GC stress conformance output differs")
call require_success(run(compiler, ["tests/compiler/frontend_fuzz.lsl", "/tmp/lsl-frontend-fuzz-test"]), "compile frontend fuzz conformance")
call require_output("/tmp/lsl-frontend-fuzz-test", [], "tests/frontend_fuzz.out", "frontend fuzz conformance output differs")
call require_success(run(compiler, ["tests/process_fault_conformance.lsl", "/tmp/lsl-process-fault-test"]), "compile process fault conformance")
call require_output("/tmp/lsl-process-fault-test", ["0"], "tests/process_fault_pipe.out", "pipe fault conformance output differs")
call require_output("/tmp/lsl-process-fault-test", ["2"], "tests/process_fault_memfd.out", "memfd fault conformance output differs")

# Compile-time diagnostics must remain failures and retain original source spans.
call require_failure(run(compiler, ["tests/builtin_arity_negative.lsl", "/tmp/lsl-arity-negative"]), "builtin arity mismatch unexpectedly compiled")
call require_failure(run(compiler, ["tests/method_arity_negative.lsl", "/tmp/lsl-method-negative"]), "method arity mismatch unexpectedly compiled")
call require_failure(run(compiler, ["tests/inheritance_cycle_negative.lsl", "/tmp/lsl-inheritance-cycle-negative"]), "cyclic inheritance unexpectedly compiled")
call require_failure(run(compiler, ["tests/origin_without_parent_negative.lsl", "/tmp/lsl-origin-negative"]), "origin without parent unexpectedly compiled")
call require_failure(run(compiler, ["tests/fixed_collection_negative.lsl", "/tmp/lsl-fixed-negative"]), "fixed collection mutation unexpectedly compiled")
call require_failure(run(compiler, ["tests/private_class_negative.lsl", "/tmp/lsl-private-negative"]), "private module class unexpectedly compiled")
call require_failure(run(compiler, ["tests/dictionary_key_negative.lsl", "/tmp/lsl-dictionary-key-negative"]), "collection Dictionary key unexpectedly compiled")
call require_failure(run(compiler, ["tests/intarray_type_negative.lsl", "/tmp/lsl-intarray-type-negative"]), "non-Int IntArray append unexpectedly compiled")
call require_failure(run(compiler, ["tests/floatarray_type_negative.lsl", "/tmp/lsl-floatarray-type-negative"]), "non-Float FloatArray append unexpectedly compiled")
call require_failure(run(compiler, ["tests/bytearray_type_negative.lsl", "/tmp/lsl-bytearray-type-negative"]), "non-Int ByteArray append unexpectedly compiled")
call require_failure(run(compiler, ["tests/legacy_power_negative.lsl", "/tmp/lsl-legacy-power-negative"]), "legacy ** power syntax unexpectedly compiled")
call require_failure(run(compiler, ["tests/bitwise_float_negative.lsl", "/tmp/lsl-bitwise-float-negative"]), "Float bitwise operand unexpectedly compiled")
call require_failure(run(compiler, ["tests/bitwise_shift_negative.lsl", "/tmp/lsl-bitwise-shift-negative"]), "constant negative shift unexpectedly compiled")
call require_failure(run(compiler, ["tests/base_literal_negative.lsl", "/tmp/lsl-base-literal-negative"]), "base prefix without digits unexpectedly compiled")
call require_success(run(compiler, ["tests/bitwise_dynamic_negative.lsl", "/tmp/lsl-bitwise-dynamic-negative"]), "compile dynamic bitwise negative test")
call require_failure(run("/tmp/lsl-bitwise-dynamic-negative", []), "dynamic Float bitwise operand unexpectedly succeeded")

configure = "/tmp/lsl-configure-test"
call require_success(run(compiler, ["stdlib/configure.lsl", configure]), "compile config generator")
time_impure_output = capture(configure, ["tests/config/time_impure.lsl", "/tmp/lsl-time-impure-evaluator.lsl"])
if time_impure_output != readfile("tests/config/time_impure.out") or exists("/tmp/lsl-time-impure-evaluator.lsl"):
    Error(TestFailure: "config time purity diagnostic differs")
end
os_impure_output = capture(configure, ["tests/config/os_impure.lsl", "/tmp/lsl-os-impure-evaluator.lsl"])
if os_impure_output != readfile("tests/config/os_impure.out") or exists("/tmp/lsl-os-impure-evaluator.lsl"):
    Error(TestFailure: "config os purity diagnostic differs")
end
system_impure_output = capture(configure, ["tests/config/system_impure.lsl", "/tmp/lsl-system-impure-evaluator.lsl"])
if system_impure_output != readfile("tests/config/system_impure.out") or exists("/tmp/lsl-system-impure-evaluator.lsl"):
    Error(TestFailure: "config system purity diagnostic differs")
end
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

generated_wrapper = "tests/config/.generated-test-evaluator.lsl"
call require_success(run(configure, ["tests/config/generated.lsl", generated_wrapper]), "generate config fuzz evaluator")
call require_success(run(compiler, [generated_wrapper, "/tmp/lsl-config-generated-test"]), "compile config fuzz evaluator")
call unlink(generated_wrapper)
generated_config_output = capture("/tmp/lsl-config-generated-test", [])
call require_success(run(compiler, ["tests/config_generated_check.lsl", "/tmp/lsl-config-generated-check"]), "compile config fuzz checker")
call require_output("/tmp/lsl-config-generated-check", [generated_config_output], "tests/config_generated_check.out", "config fuzz output differs")

config_cycle_output = capture(configure, ["tests/config/cycle_a.lsl", "/tmp/lsl-cycle-evaluator.lsl"])
if config_cycle_output != readfile("tests/config/cycle.out"):
    Error(TestFailure: "config cycle diagnostic differs")
end

call require_success(run(compiler, ["compiler/pure/lslc_direct.lsl", "/tmp/lsl-fixed-test"]), "compile fixed-point stage")
if readfile(compiler) != readfile("/tmp/lsl-fixed-test"):
    Error(TestFailure: "compiler fixed point differs")
end

print "pure LSL tests passed"
