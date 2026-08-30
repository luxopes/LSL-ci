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

function difference(actual, expected):
    limit = min(len(actual), len(expected))
    index = 0
    while index < limit and actual[index] == expected[index]:
        index += 1
    end
    if index < limit:
        return " at byte " + String(index) + " (actual " + String(ord(actual[index])) + ", expected " + String(ord(expected[index])) + "); actual length " + String(len(actual)) + ", expected length " + String(len(expected))
    end
    return " at byte " + String(index) + "; actual length " + String(len(actual)) + ", expected length " + String(len(expected))
end

function elf_integer(image, offset, width):
    if offset < 0 or width < 0 or offset + width > len(image):
        Error(TestFailure: "truncated ELF header")
    end
    value = 0
    scale = 1
    index = 0
    while index < width:
        value += image[offset + index] * scale
        scale *= 256
        index += 1
    end
    return value
end

function require_hardened_elf(path):
    image = readbytes(path)
    if len(image) < 176 or elf_integer(image, 16, 2) != 3 or elf_integer(image, 18, 2) != 62:
        Error(TestFailure: "generated executable is not Linux x86_64 static PIE")
    end
    program_offset = elf_integer(image, 32, 8)
    program_size = elf_integer(image, 54, 2)
    program_count = elf_integer(image, 56, 2)
    if program_size != 56 or program_count != 2 or program_offset + program_size * program_count > len(image):
        Error(TestFailure: "generated executable has an invalid program table")
    end
    load_header = program_offset
    stack = program_offset + program_size
    if elf_integer(image, load_header, 4) != 1 or elf_integer(image, load_header + 4, 4) != 5 or elf_integer(image, load_header + 8, 8) != 0 or elf_integer(image, load_header + 16, 8) != 0:
        Error(TestFailure: "generated executable does not have one zero-based RX segment")
    end
    if elf_integer(image, load_header + 32, 8) != len(image) or elf_integer(image, load_header + 40, 8) != len(image):
        Error(TestFailure: "generated executable load segment does not cover the image")
    end
    if elf_integer(image, stack, 4) != 1685382481 or elf_integer(image, stack + 4, 4) != 6:
        Error(TestFailure: "generated executable does not declare a non-executable stack")
    end
end

function require_output(program, arguments, expected_path, name):
    actual = capture(program, arguments)
    expected = readfile(expected_path)
    if actual != expected:
        Error(TestFailure: name + difference(actual, expected))
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

# Every invocation owns a fresh namespace. This prevents concurrent or aborted
# runs from reusing executables, installer prefixes and conformance fixtures.
test_pid = String(__lsl_syscall(39, 0, 0, 0, 0))
test_token = test_pid
test_root = "/tmp/lsl-test-" + test_token
test_suffix = 0
while exists(test_root):
    test_suffix += 1
    test_token = test_pid + "-" + String(test_suffix)
    test_root = "/tmp/lsl-test-" + test_token
end
if mkdir(test_root) != 0:
    Error(TestFailure: "cannot create isolated test root " + test_root)
end

function test_path(name):
    return test_root + "/" + name
end

function require_fixed_point_compiler():
    fixed_test = test_path("fixed-test")
    call require_success(run(compiler, ["compiler/pure/lslc_direct.lsl", fixed_test]), "compile fixed-point stage")
    call require_hardened_elf(fixed_test)
    if readfile(compiler) != readfile(fixed_test):
        Error(TestFailure: "compiler fixed point differs")
    end

    # A development compiler outside prefix/bin must use this checkout, not a
    # stale prefix/lib tree. This reproduces the path-dependent false fixed
    # point that was found during the 0.6.8 release audit.
    shadow_root = test_path("resource-shadow")
    call mkdir(shadow_root)
    call mkdir(shadow_root + "/dev")
    call mkdir(shadow_root + "/lib")
    call mkdir(shadow_root + "/lib/lsl")
    call mkdir(shadow_root + "/lib/lsl/compiler")
    call mkdir(shadow_root + "/lib/lsl/compiler/pure")
    shadow_compiler = shadow_root + "/dev/lslc"
    call writebytes(shadow_compiler, readbytes(compiler))
    call writefile(shadow_root + "/lib/lsl/compiler/pure/dynamic_stdlib.lsl", "print \"stale resource\"" + chr(10))
    shadow_fixed = test_path("shadow-fixed-test")
    call require_success(run(shadow_compiler, ["compiler/pure/lslc_direct.lsl", shadow_fixed]), "compile fixed point beside stale prefix resources")
    if readfile(compiler) != readfile(shadow_fixed):
        Error(TestFailure: "development compiler consumed stale prefix resources")
    end

    incomplete_root = test_path("incomplete-install")
    call mkdir(incomplete_root)
    call mkdir(incomplete_root + "/bin")
    incomplete_compiler = incomplete_root + "/bin/lslc"
    call writebytes(incomplete_compiler, readbytes(compiler))
    call capture(incomplete_compiler, ["compiler/pure/lslc_direct.lsl", test_path("incomplete-fixed")])
    if capture_status() == 0:
        Error(TestFailure: "installed compiler used cwd after trusted resources went missing")
    end

    builtin_root = test_path("missing-builtin-install")
    call mkdir(builtin_root)
    call mkdir(builtin_root + "/bin")
    call mkdir(builtin_root + "/lib")
    call mkdir(builtin_root + "/lib/lsl")
    call mkdir(builtin_root + "/lib/lsl/compiler")
    call mkdir(builtin_root + "/lib/lsl/compiler/pure")
    builtin_compiler = builtin_root + "/bin/lslc"
    call writebytes(builtin_compiler, readbytes(compiler))
    call writefile(builtin_root + "/lib/lsl/compiler/pure/dynamic_stdlib.lsl", readfile("compiler/pure/dynamic_stdlib.lsl"))
    builtin_source = test_path("missing-builtin.lsl")
    call writefile(builtin_source, "load json" + chr(10) + "print 1" + chr(10))
    call capture(builtin_compiler, [builtin_source, test_path("missing-builtin")])
    if capture_status() == 0:
        Error(TestFailure: "installed compiler loaded a missing built-in from cwd")
    end
end

if mode == "fixed-point":
    call require_fixed_point_compiler()
    print "pure LSL fixed point passed"
    exit(0)
end

# Standalone smoke/fixed-table programs cannot safely share aggregate state.
scalar_test = test_path("scalar-test")
float_test = test_path("float-test")
optimization_test = test_path("codegen-optimization-test")
cli_test = test_path("stdin-cli-test")
syscall6_test = test_path("syscall6-test")
httpserver_test = test_path("httpserver-test")
call require_success(run(compiler, ["tests/compiler/scalar_smoke.lsl", scalar_test]), "compile scalar smoke")
call require_success(run(scalar_test, []), "run scalar smoke")
call require_success(run(compiler, ["tests/compiler/float_smoke.lsl", float_test]), "compile Float smoke")
call require_success(run(float_test, []), "run Float smoke")
call require_success(run(compiler, ["tests/syscall6_conformance.lsl", syscall6_test]), "compile six-argument syscall conformance")
call require_output(syscall6_test, [], "tests/syscall6_conformance.out", "six-argument syscall output differs")
gc_bigheap_test = test_path("gc-bigheap-test")
call require_success(run(compiler, ["tests/gc_bigheap_threads_conformance.lsl", gc_bigheap_test]), "compile gc bigheap threads conformance")
call require_output(gc_bigheap_test, [], "tests/gc_bigheap_threads_conformance.out", "gc bigheap threads output differs")
string_split_test = test_path("string-split-test")
call require_success(run(compiler, ["tests/string_split_conformance.lsl", string_split_test]), "compile String split conformance")
call require_output(string_split_test, [], "tests/string_split_conformance.out", "String split output differs")
call require_success(run(compiler, ["tests/httpserver_conformance.lsl", httpserver_test]), "compile HTTP server conformance")
httpserver_root = test_path("httpserver-root")
call mkdir(httpserver_root)
call writefile(httpserver_root + "/index.html", "hello-http" + chr(10))
call writefile(httpserver_root + "/large.txt", "x" * 1048576)
call require_output(httpserver_test, [httpserver_root], "tests/httpserver_conformance.out", "HTTP server conformance output differs")
call require_success(run(compiler, ["tests/codegen_optimization_conformance.lsl", optimization_test]), "compile codegen optimization conformance")
call require_hardened_elf(optimization_test)
call require_output(optimization_test, [], "tests/codegen_optimization_conformance.out", "codegen optimization output differs")
# Checked public Any collection and numeric dispatchers added in 0.6.9 are
# linked into standalone programs so callbacks cannot bypass validation. Keep
# a tight ceiling around that intentional runtime growth.
if len(readbytes(optimization_test)) > 98000:
    Error(TestFailure: "optimized standalone ELF exceeds 98000 bytes")
end
call require_success(run(compiler, ["compiler/pure/cli.lsl", cli_test]), "compile stdin CLI")
call require_hardened_elf(cli_test)
help_output = capture(cli_test, ["--help"])
expected_help = "Lux Simple Lang (LSL) 0.7.6" + chr(10)
expected_help += chr(10)
expected_help += "Usage:" + chr(10)
expected_help += "  lsl [SOURCE [ARG...]]" + chr(10)
expected_help += "  lsl compile [--unsafe] SOURCE OUTPUT" + chr(10)
expected_help += "  lsl config ENTRY" + chr(10)
expected_help += "  lsl install NAME" + chr(10)
expected_help += "  lsl install --config FILE" + chr(10)
expected_help += "  lsl update NAME" + chr(10)
expected_help += "  lsl origin [NAME]" + chr(10)
expected_help += "  lsl server [OPTIONS]" + chr(10)
expected_help += "  lsl sandbox [OPTIONS] SOURCE [ARG...]" + chr(10)
expected_help += "  lsl version" + chr(10)
expected_help += chr(10)
expected_help += "Options:" + chr(10)
expected_help += "  -h, --help     Show this help" + chr(10)
expected_help += "  --version      Show version" + chr(10)
if capture_status() != 0 or help_output != expected_help:
    Error(TestFailure: "CLI --help output differs")
end
version_output = capture(cli_test, ["version"])
if capture_status() != 0 or version_output != "0.7.6" + chr(10):
    Error(TestFailure: "CLI version output differs")
end
version_flag_output = capture(cli_test, ["--version"])
if capture_status() != 0 or version_flag_output != "0.7.6" + chr(10):
    Error(TestFailure: "CLI --version output differs")
end
config_output = capture(cli_test, ["config", "examples/config/system.lsl"])
if capture_status() != 0 or config_output != readfile("tests/config_expected.json"):
    Error(TestFailure: "CLI trusted config wrapper output differs")
end
origin_output = capture(cli_test, ["origin"])
if capture_status() != 0 or origin_output != "https://luxos-registry-temp-2026.netlify.app/lsl" + chr(10):
    Error(TestFailure: "CLI registry origin output differs")
end
server_help = capture(cli_test, ["server", "--help"])
if capture_status() != 0 or server_help.find("--tls-cert FILE") < 0 or server_help.find("--max-requests N") < 0:
    Error(TestFailure: "CLI server help differs")
end
sandbox_help = capture(cli_test, ["sandbox", "--help"])
if capture_status() != 0 or sandbox_help.find("--profile NAME") < 0 or sandbox_help.find("--read PATH") < 0:
    Error(TestFailure: "CLI sandbox help differs")
end
call capture(cli_test, ["server", "--tls-cert", "missing.pem"])
if capture_status() == 0 or capture_stderr().find("--tls-cert and --tls-key must be supplied together") < 0:
    Error(TestFailure: "CLI accepted an incomplete TLS key pair")
end
stdin_source = "value = 6 * 7" + chr(10) + "if value == 42:" + chr(10) + "    print \"stdin\", value" + chr(10) + "end" + chr(10) + "exit" + chr(10)
stdin_output = capture_input(cli_test, [], stdin_source)
if capture_status() != 0 or stdin_output != "stdin 42" + chr(10):
    Error(TestFailure: "stdin CLI terminated source differs")
end
eof_output = capture_input(cli_test, [], "print \"eof\", 9" + chr(10))
if capture_status() != 0 or eof_output != "eof 9" + chr(10):
    Error(TestFailure: "stdin CLI EOF source differs")
end
time_output = capture_input(cli_test, [], "load time" + chr(10) + "print time.time() > 1577836800.0" + chr(10) + "exit" + chr(10))
if capture_status() != 0 or time_output != "True" + chr(10):
    Error(TestFailure: "stdin CLI module lookup differs")
end
exit_output = capture_input(cli_test, [], "exit(7)" + chr(10) + "exit" + chr(10))
if capture_status() != 7 or exit_output != "":
    Error(TestFailure: "stdin CLI exact exit terminator differs")
end

# The ordinary CLI is memory-safe by default. Raw runtime/native/thread doors
# require a lexical unsafe block; sandbox compilation rejects unsafe entirely.
unsafe_block_test = test_path("unsafe-block-test")
call require_success(run(cli_test, ["compile", "tests/unsafe_block_conformance.lsl", unsafe_block_test]), "compile explicit unsafe block")
unsafe_block_output = capture(unsafe_block_test, [])
if capture_status() != 0 or not unsafe_block_output.endswith("unsafe block explicit" + chr(10)):
    Error(TestFailure: "explicit unsafe block output differs")
end
call capture(cli_test, ["compile", "tests/unsafe_outside_negative.lsl", test_path("unsafe-outside-negative")])
if capture_status() == 0 or capture_stderr().find("unsafe operation outside an unsafe block") < 0:
    Error(TestFailure: "raw operation outside unsafe unexpectedly compiled")
end
call capture(cli_test, ["compile", "tests/unsafe_import_negative.lsl", test_path("unsafe-import-negative")])
if capture_status() == 0 or capture_stderr().find("unsafe operation outside an unsafe block") < 0:
    Error(TestFailure: "raw operation in an imported user module unexpectedly compiled")
end
call capture(cli_test, ["compile", "tests/unsafe_slice_step_negative.lsl", test_path("unsafe-slice-step-negative")])
if capture_status() == 0 or capture_stderr().find("unsafe operation outside an unsafe block") < 0:
    Error(TestFailure: "raw operation in a slice step unexpectedly compiled")
end
call require_success(run(cli_test, ["compile", "--unsafe", "tests/unsafe_outside_negative.lsl", test_path("unsafe-cli-override")]), "explicit --unsafe CLI override failed")
call capture(cli_test, ["compile", "tests/unchecked_intarray_cli_negative.lsl", test_path("unchecked-cli-negative")])
if capture_status() == 0 or capture_stderr().find("unchecked-intarray requires lsl compile --unsafe") < 0:
    Error(TestFailure: "unchecked IntArray optimization bypassed safe CLI")
end

# Compiler tools use a compact raw ABI internally, while linked public modules
# use tagged Any values. A literal zero must remain Int(0) across that boundary
# rather than being mistaken for None.
internal_directory = test_path("compiler")
call mkdir(internal_directory)
internal_directory += "/pure"
call mkdir(internal_directory)
internal_boundary_source = internal_directory + "/public-boundary.lsl"
internal_boundary_program = test_path("internal-public-boundary")
call writefile(internal_boundary_source, "# lsl: internal-abi" + chr(10) + "load sandbox" + chr(10) + "print sandbox.input_path(0)" + chr(10) + "print sandbox.output_path(0)" + chr(10))
call require_success(run(compiler, [internal_boundary_source, internal_boundary_program]), "compile internal/public ABI boundary")
internal_boundary_output = capture(internal_boundary_program, [])
if capture_status() != 0 or internal_boundary_output != "/input/0" + chr(10) + "/output/0" + chr(10):
    Error(TestFailure: "internal/public ABI zero boundary differs")
end

sandbox_supported = (exists("/usr/bin/bwrap") or exists("/bin/bwrap")) and (exists("/usr/bin/systemd-run") or exists("/bin/systemd-run")) and env.get("XDG_RUNTIME_DIR", "") != "" and env.get("DBUS_SESSION_BUS_ADDRESS", "") != ""
if sandbox_supported:
    sandbox_output_directory = test_path("sandbox-output")
    call mkdir(sandbox_output_directory)
    sandbox_output = capture(cli_test, [
        "sandbox", "--timeout", "5",
        "--read", "tests/sandbox_fixture.txt",
        "--write", sandbox_output_directory,
        "tests/sandbox_child.lsl", "argument"
    ])
    if capture_status() != 0 or sandbox_output != readfile("tests/sandbox_child.out"):
        Error(TestFailure: "capability sandbox output differs")
    end
    if readfile(sandbox_output_directory + "/sandbox-result.txt") != "sandbox-write" + chr(10):
        Error(TestFailure: "sandbox writable capability differs")
    end
    call capture(cli_test, ["sandbox", "--timeout", "5", "tests/unsafe_block_conformance.lsl"])
    if capture_status() == 0 or capture_stderr().find("unsafe block is forbidden in sandbox compilation") < 0:
        Error(TestFailure: "sandbox compilation accepted an unsafe block")
    end
end

# Compiler limits are byte budgets, not Unicode code-point budgets. Four-byte
# UTF-8 input must be rejected at 4 MiB before character/token materialization.
oversized_utf8_path = test_path("oversized-utf8-source.lsl")
oversized_utf8_output = test_path("oversized-utf8-program")
oversized_utf8_source = chr(1114111) * 1048577
call writefile(oversized_utf8_path, oversized_utf8_source)
oversized_utf8_source = ""
call gc()
call capture(compiler, [oversized_utf8_path, oversized_utf8_output])
if capture_status() == 0 or capture_stderr().find("source exceeds the 4 MiB compiler limit") < 0:
    Error(TestFailure: "compiler source limit counted characters instead of UTF-8 bytes")
end
call unlink(oversized_utf8_path)
call unlink(oversized_utf8_output)

# Exercise the real bundled foreign worker without requiring CUDA hardware.
# Empty kernels return before driver initialization; malformed requests must
# fail at the protocol boundary rather than reaching CUDA or allocating data.
cuda_worker = "./cuda/lsl-cuda-worker"
if not exists(cuda_worker):
    Error(TestFailure: "bundled CUDA worker is missing")
end

function require_cuda_json(request, expected, name):
    output = capture_input_clean(cuda_worker, [], request)
    if capture_status() != 0 or output != expected + chr(10):
        Error(TestFailure: name)
    end
end

call require_cuda_json("{\"abi\":1,\"operation\":\"cuda.sum\",\"payload\":{\"values\":[]}}", "{\"abi\":1,\"ok\":true,\"value\":0}", "CUDA JSON payload routing differs")
call require_cuda_json("{\"abi\":2,\"operation\":\"cuda.probe\",\"payload\":{}}", "{\"abi\":1,\"ok\":false,\"error\":\"CUDA request ABI version mismatch\"}", "CUDA ABI mismatch was not rejected")
call require_cuda_json("{\"abi\":1,\"abi\":1,\"operation\":\"cuda.probe\",\"payload\":{}}", "{\"abi\":1,\"ok\":false,\"error\":\"request contains duplicate key abi\"}", "CUDA duplicate ABI key was not rejected")
call require_cuda_json("{\"abi\":1,\"operation\":\"cuda.sum\",\"payload\":{\"values\":[],\"values\":[]}}", "{\"abi\":1,\"ok\":false,\"error\":\"request contains duplicate key values\"}", "CUDA duplicate payload key was not rejected")
call require_cuda_json("{\"abi\":1,\"operation\":\"cuda.probe\",\"payload\":[]}trailing", "{\"abi\":1,\"ok\":false,\"error\":\"unexpected data after JSON request\"}", "CUDA trailing JSON data was not rejected")
call require_cuda_json("{\"abi\":1,\"operation\":\"cuda.probe\",\"payload\":[]}", "{\"abi\":1,\"ok\":false,\"error\":\"request key payload must be an Object\"}", "CUDA non-Object payload was not rejected")

deep_cuda_request = "{\"abi\":1,\"operation\":\"cuda.probe\",\"payload\":{\"extra\":"
deep_cuda_level = 0
while deep_cuda_level < 65:
    deep_cuda_request += "["
    deep_cuda_level += 1
end
deep_cuda_request += "0"
while deep_cuda_level > 0:
    deep_cuda_request += "]"
    deep_cuda_level -= 1
end
deep_cuda_request += "}}"
call require_cuda_json(deep_cuda_request, "{\"abi\":1,\"ok\":false,\"error\":\"JSON nesting exceeds 64 levels\"}", "CUDA JSON nesting limit differs")

cuda_binary_output = capture_input_clean(cuda_worker, ["--binary", "sum", "2000001"], "")
if capture_status() != 2 or cuda_binary_output != "" or capture_stderr() != "invalid binary sum count" + chr(10):
    Error(TestFailure: "CUDA binary element limit differs")
end

# The installed self-host source set must contain every module imported by
# lslc_direct/codegen, not only the bootstrapping binary.
install_test = test_path("install-tool-test")
call require_success(run(compiler, ["compiler/pure/install.lsl", install_test]), "compile installer conformance")
install_test_prefix = test_path("install-prefix-test")
call require_success(run(install_test, [install_test_prefix]), "run installer conformance")
installed_thread_runtime = install_test_prefix + "/lib/lsl/compiler/pure/thread_runtime.lsl"
if readfile(installed_thread_runtime) != readfile("compiler/pure/thread_runtime.lsl"):
    Error(TestFailure: "installed compiler source set is incomplete")
end
if readfile(install_test_prefix + "/lib/lsl/stdlib/httpserver.lsl") != readfile("stdlib/httpserver.lsl") or readfile(install_test_prefix + "/lib/lsl/stdlib/sandbox.lsl") != readfile("stdlib/sandbox.lsl"):
    Error(TestFailure: "installed 0.7 standard library set is incomplete")
end

# Per-user source libraries use a strict name/hash/compile/atomic-move path, and
# built-in modules retain precedence over the user directory.
package_server = test_path("package-command-server")
package_install = test_path("package-install-test")
package_update = test_path("package-update-config-test")
package_negative = test_path("package-config-negative")
call require_success(run(compiler, ["tests/compiler/package_command_server.lsl", package_server]), "compile package command server")
call require_success(run(compiler, ["tests/compiler/package_install_conformance.lsl", package_install]), "compile package install conformance")
call require_success(run(compiler, ["tests/compiler/package_update_config_conformance.lsl", package_update]), "compile package update/config conformance")
call require_success(run(compiler, ["tests/compiler/package_config_negative.lsl", package_negative]), "compile package config negative test")
package_home = test_path("package-home")
call mkdir(package_home)
call mkdir(package_home + "/.local")
call mkdir(package_home + "/.local/lib")
call mkdir(package_home + "/.local/lib/lsl")
call mkdir(package_home + "/.local/lib/lsl/stdlib")
package_destination = package_home + "/.local/lib/lsl/stdlib/registry_probe.lsl"
package_origin = package_destination + ".origin"
if exists(package_destination):
    call unlink(package_destination)
end
if exists(package_origin):
    call unlink(package_origin)
end
package_arguments = ["registry_probe", package_home, "http://127.0.0.1:8080/lsl", package_server, cli_test]
package_output = capture(package_install, package_arguments)
expected_package_output = readfile("tests/compiler/package_install_conformance.out").replace("/tmp/lsl-package-home", package_home)
if package_output != expected_package_output:
    Error(TestFailure: "package install output differs" + difference(package_output, expected_package_output))
end
if not exists(package_destination):
    Error(TestFailure: "package install did not create the user module")
end
if not exists(package_origin):
    Error(TestFailure: "package install did not record provenance")
end
named_origin_output = capture_clean("/usr/bin/env", ["-i", "HOME=" + package_home, cli_test, "origin", "registry_probe"])
expected_named_origin = "name registry_probe" + chr(10)
expected_named_origin += "origin http://127.0.0.1:8080/lsl" + chr(10)
expected_named_origin += "source http://127.0.0.1:8080/lsl/registry_probe.lsl" + chr(10)
expected_named_origin += "sha256 " + readfile(package_origin).split("sha256=")[1].strip() + chr(10)
if capture_status() != 0 or named_origin_output != expected_named_origin:
    Error(TestFailure: "CLI named package origin output differs")
end
call unlink(package_destination)
call unlink(package_origin)
bad_hash_arguments = ["registry_probe", package_home, "http://127.0.0.1:8080/bad", package_server, cli_test]
call require_failure(run(package_install, bad_hash_arguments), "package hash mismatch unexpectedly installed")
if exists(package_destination):
    Error(TestFailure: "package hash failure left an installed module")
end
bad_name_arguments = ["Bad/Name", package_home, "http://127.0.0.1:8080/lsl", package_server, cli_test]
call require_failure(run(package_install, bad_name_arguments), "unsafe package name unexpectedly installed")
package_config = test_path("package-list.conf")
call writefile(package_config, "# libraries" + chr(10) + "config_probe" + chr(10) + "second_probe" + chr(10))
update_arguments = [package_home, "http://127.0.0.1:8080/lsl", package_server, cli_test, package_config]
call require_success(run(package_update, update_arguments), "package update/config install failed")
call writefile(package_config, "duplicate" + chr(10) + "duplicate" + chr(10))
call require_failure(run(package_negative, [package_config]), "duplicate config library unexpectedly accepted")
call writefile(package_config, "bad name" + chr(10))
call require_failure(run(package_negative, [package_config]), "unsafe config library unexpectedly accepted")
user_module_test = test_path("user-module-path-test")
call require_success(run(compiler, ["tests/compiler/user_module_path_conformance.lsl", user_module_test]), "compile user module path conformance")
call require_output(user_module_test, [test_root], "tests/compiler/user_module_path_conformance.out", "user module path output differs")

selfhost_test = test_path("selfhost-test")
table_test = test_path("table-growth-test")
float_allocation_test = test_path("float-format-allocation-test")
call require_success(run(compiler, ["tests/selfhost_conformance.lsl", selfhost_test]), "compile selfhost conformance")
call require_output(selfhost_test, [], "tests/selfhost_conformance.out", "selfhost conformance output differs")
call require_success(run(compiler, ["tests/table_growth_conformance.lsl", table_test]), "compile table growth conformance")
call require_output(table_test, [], "tests/table_growth_conformance.out", "table growth conformance output differs")
call require_success(run(compiler, ["tests/float_format_allocation_conformance.lsl", float_allocation_test]), "compile Float format allocation conformance")
call require_output(float_allocation_test, [], "tests/float_format_allocation_conformance.out", "Float format allocation growth differs")

# Process clients in the aggregate require independently executable children.
servers = [
    ["tests/capture_large_server.lsl", test_path("capture-large-server")],
    ["tests/capture_stream_server.lsl", test_path("capture-stream-server")],
    ["tests/capture_result_server.lsl", test_path("capture-result-server")],
    ["tests/input_conformance.lsl", test_path("input-server")],
    ["tests/input_bare_server.lsl", test_path("input-bare-server")],
    ["tests/process_status_server.lsl", test_path("process-status-server")],
    ["tests/plugin_process_server.lsl", test_path("plugin-process-server")],
    ["tests/fd_inherit_server.lsl", test_path("fd-inherit-server")],
    ["tests/http_transport_server.lsl", test_path("http-transport-server")],
    ["tests/cuda_worker.lsl", test_path("cuda-worker")],
    ["tests/os_command_server.lsl", test_path("os-command-server")],
    ["tests/system_package_server.lsl", test_path("system-package-server")],
    ["tests/system_command_server.lsl", test_path("system-command-apt")],
    ["tests/system_command_server.lsl", test_path("system-command-systemctl")],
    ["tests/system_command_server.lsl", test_path("system-command-account")],
    ["tests/system_command_server.lsl", test_path("system-command-file-tool")],
    ["tests/system_command_server.lsl", test_path("system-command-mount-tool")],
    ["tests/system_command_server.lsl", test_path("system-command-lux")]
]
for server in servers:
    call require_success(run(compiler, server), "compile process conformance server")
end

capture_cloexec_test = test_path("capture-cloexec-test")
call require_success(run(compiler, ["tests/capture_cloexec_conformance.lsl", capture_cloexec_test]), "compile capture CLOEXEC conformance")
call require_success(run(capture_cloexec_test, [test_path("capture-stream-server")]), "capture endpoints disappeared across execve")

if env.get("LSL_CUDA_HARDWARE_TEST", "0") == "1":
    cuda_hardware_test = test_path("cuda-hardware-test")
    call require_success(run(compiler, ["tests/cuda_hardware_conformance.lsl", cuda_hardware_test]), "compile CUDA hardware conformance")
    call require_success(run(cuda_hardware_test, []), "run CUDA hardware conformance")
end

thread_test = test_path("thread-reuse-test")
aggregate_test = test_path("full-conformance-test")
call require_success(run(compiler, ["tests/thread_reuse_conformance.lsl", thread_test]), "compile thread slot reuse conformance")
call require_output(thread_test, [], "tests/thread_reuse_conformance.out", "thread slot reuse output differs")

# A raw non-CLOEXEC descriptor simulates a socket or secret memfd supplied by a
# service manager. Process helpers must close it before execve.
fd_leak_fixture = test_path("fd-leak-fixture")
call writefile(fd_leak_fixture, "secret")
fd_leak = __lsl_fd_open(fd_leak_fixture, 0)
if fd_leak < 0:
    Error(TestFailure: "cannot create descriptor inheritance fixture")
end
if __lsl_syscall(72, fd_leak, 2, 0, 0) < 0:
    Error(TestFailure: "cannot clear CLOEXEC on inheritance fixture")
end
fd_inherit_output = capture(test_path("fd-inherit-server"), [String(fd_leak)])
call __lsl_fd_close(fd_leak)
if capture_status() != 0 or fd_inherit_output != "-9" + chr(10):
    Error(TestFailure: "capture child inherited an unrelated descriptor")
end

allocation_overflow_test = test_path("allocation-overflow-test")
call require_success(run(compiler, ["tests/allocation_overflow_conformance.lsl", allocation_overflow_test]), "compile allocation overflow conformance")
if run(allocation_overflow_test, []) != 70:
    Error(TestFailure: "oversized container allocation was not rejected safely")
end

# Public Any boundary tests intentionally retain escaped callbacks and several
# typed collections. Run them in short-lived processes so their globals do not
# consume the shared aggregate's object-table budget during later BigInt stress.
boundary_tests = [
    "bytearray_slice_conformance",
    "dynamic_builtin_boundary_conformance",
    "dynamic_collection_boundary_conformance",
    "dynamic_method_boundary_conformance",
    "dynamic_numeric_boundary_conformance"
]
for boundary_name in boundary_tests:
    boundary_test = test_path(boundary_name)
    call require_success(run(compiler, ["tests/" + boundary_name + ".lsl", boundary_test]), "compile " + boundary_name)
    call require_output(boundary_test, [], "tests/" + boundary_name + ".out", boundary_name + " output differs")
end

call require_success(run(compiler, ["tests/full_conformance.lsl", aggregate_test]), "compile aggregated conformance")
call require_hardened_elf(aggregate_test)
aggregate_output = capture(aggregate_test, [test_root])
expected_aggregate_output = aggregate_expected()
if aggregate_output != expected_aggregate_output:
    call writefile(test_path("aggregate.actual"), aggregate_output)
    call writefile(test_path("aggregate.expected"), expected_aggregate_output)
    Error(TestFailure: "aggregated conformance output differs" + difference(aggregate_output, expected_aggregate_output) + "; artifacts: " + test_root)
end

if mode == "fast":
    print "pure LSL fast tests passed"
    exit(0)
end

json_fuzz_test = test_path("json-fuzz-test")
gc_stress_test = test_path("gc-stress-test")
frontend_fuzz_test = test_path("frontend-fuzz-test")
process_fault_test = test_path("process-fault-test")
call require_success(run(compiler, ["tests/json_fuzz_conformance.lsl", json_fuzz_test]), "compile JSON fuzz conformance")
call require_output(json_fuzz_test, [], "tests/json_fuzz_conformance.out", "JSON fuzz conformance output differs")
call require_success(run(compiler, ["tests/gc_stress_conformance.lsl", gc_stress_test]), "compile GC stress conformance")
call require_output(gc_stress_test, [], "tests/gc_stress_conformance.out", "GC stress conformance output differs")
call require_success(run(compiler, ["tests/compiler/frontend_fuzz.lsl", frontend_fuzz_test]), "compile frontend fuzz conformance")
call require_output(frontend_fuzz_test, [], "tests/frontend_fuzz.out", "frontend fuzz conformance output differs")
call require_success(run(compiler, ["tests/process_fault_conformance.lsl", process_fault_test]), "compile process fault conformance")
call require_output(process_fault_test, ["0", test_root], "tests/process_fault_pipe.out", "pipe fault conformance output differs")
call require_output(process_fault_test, ["2", test_root], "tests/process_fault_memfd.out", "memfd fault conformance output differs")

# Compile-time diagnostics must remain failures and retain original source spans.
call require_failure(run(compiler, ["tests/builtin_arity_negative.lsl", test_path("arity-negative")]), "builtin arity mismatch unexpectedly compiled")
call require_failure(run(compiler, ["tests/arg_arity_negative.lsl", test_path("arg-arity-negative")]), "arg arity mismatch unexpectedly compiled")
call require_failure(run(compiler, ["tests/internal_builtin_arity_negative.lsl", test_path("internal-arity-negative")]), "internal builtin arity mismatch unexpectedly compiled")
call require_failure(run(compiler, ["tests/method_arity_negative.lsl", test_path("method-negative")]), "method arity mismatch unexpectedly compiled")
call require_failure(run(compiler, ["tests/dictionary_method_arity_negative.lsl", test_path("dictionary-method-negative")]), "Dictionary method arity mismatch unexpectedly compiled")
call require_failure(run(compiler, ["tests/method_receiver_negative.lsl", test_path("method-receiver-negative")]), "invalid method receiver unexpectedly compiled")
call require_failure(run(compiler, ["tests/scalar_length_negative.lsl", test_path("scalar-length-negative")]), "scalar len unexpectedly compiled")
call require_failure(run(compiler, ["tests/sequence_index_type_negative.lsl", test_path("sequence-index-type-negative")]), "non-Int sequence index unexpectedly compiled")
call require_failure(run(compiler, ["tests/arithmetic_operand_negative.lsl", test_path("arithmetic-operand-negative")]), "invalid arithmetic operand unexpectedly compiled")
call require_failure(run(compiler, ["tests/unary_numeric_negative.lsl", test_path("unary-numeric-negative")]), "invalid unary numeric operand unexpectedly compiled")
call require_failure(run(compiler, ["tests/ordered_comparison_negative.lsl", test_path("ordered-comparison-negative")]), "invalid ordered comparison unexpectedly compiled")
call require_failure(run(compiler, ["tests/numeric_builtin_negative.lsl", test_path("numeric-builtin-negative")]), "invalid numeric builtin operand unexpectedly compiled")
call require_failure(run(compiler, ["tests/inheritance_cycle_negative.lsl", test_path("inheritance-cycle-negative")]), "cyclic inheritance unexpectedly compiled")
call require_failure(run(compiler, ["tests/origin_without_parent_negative.lsl", test_path("origin-negative")]), "origin without parent unexpectedly compiled")
call require_failure(run(compiler, ["tests/fixed_collection_negative.lsl", test_path("fixed-negative")]), "fixed collection mutation unexpectedly compiled")
call require_failure(run(compiler, ["tests/private_class_negative.lsl", test_path("private-negative")]), "private module class unexpectedly compiled")
call require_failure(run(compiler, ["tests/dictionary_key_negative.lsl", test_path("dictionary-key-negative")]), "collection Dictionary key unexpectedly compiled")
call require_failure(run(compiler, ["tests/intarray_type_negative.lsl", test_path("intarray-type-negative")]), "non-Int IntArray append unexpectedly compiled")
call require_failure(run(compiler, ["tests/floatarray_type_negative.lsl", test_path("floatarray-type-negative")]), "non-Float FloatArray append unexpectedly compiled")
call require_failure(run(compiler, ["tests/bytearray_type_negative.lsl", test_path("bytearray-type-negative")]), "non-Int ByteArray append unexpectedly compiled")
call require_failure(run(compiler, ["tests/legacy_power_negative.lsl", test_path("legacy-power-negative")]), "legacy ** power syntax unexpectedly compiled")
call require_failure(run(compiler, ["tests/bitwise_float_negative.lsl", test_path("bitwise-float-negative")]), "Float bitwise operand unexpectedly compiled")
call require_failure(run(compiler, ["tests/bitwise_shift_negative.lsl", test_path("bitwise-shift-negative")]), "constant negative shift unexpectedly compiled")
call require_failure(run(compiler, ["tests/base_literal_negative.lsl", test_path("base-literal-negative")]), "base prefix without digits unexpectedly compiled")
symlink_test = test_path("write-symlink-test")
symlink_target = test_path("write-symlink-target")
symlink_path = test_path("write-symlink-link")
call require_success(run(compiler, ["tests/write_symlink_conformance.lsl", symlink_test]), "compile symlink write conformance")
call writefile(symlink_target, "safe")
call require_success(run("/bin/ln", ["-s", symlink_target, symlink_path]), "create symlink write conformance fixture")
call require_output(symlink_test, [symlink_path, symlink_target], "tests/write_symlink_conformance.out", "symlink write protection differs")
bitwise_dynamic_test = test_path("bitwise-dynamic-negative")
call require_success(run(compiler, ["tests/bitwise_dynamic_negative.lsl", bitwise_dynamic_test]), "compile dynamic bitwise negative test")
call require_failure(run(bitwise_dynamic_test, []), "dynamic Float bitwise operand unexpectedly succeeded")

configure = test_path("configure-test")
call require_success(run(compiler, ["stdlib/configure.lsl", configure]), "compile config generator")

# The per-file ceiling is not enough for a wide import graph. Build sixteen
# individually valid 1 MiB modules; the root bytes make the aggregate cross the
# 16 MiB graph budget before a wrapper can be emitted.
config_budget_directory = test_path("config-budget")
call mkdir(config_budget_directory)
config_budget_imports = []
config_budget_source = " " * 1048576
config_budget_index = 0
while config_budget_index < 16:
    config_budget_name = "part" + String(config_budget_index) + ".lsl"
    call writefile(config_budget_directory + "/" + config_budget_name, config_budget_source)
    config_budget_imports.append("\"" + config_budget_name + "\"")
    config_budget_index += 1
end
config_budget_entry = config_budget_directory + "/entry.lsl"
call writefile(config_budget_entry, "load config\nimports = [" + ",".join(config_budget_imports) + "]\nconfig = {}\n")
config_budget_output = capture(configure, [config_budget_entry, test_path("config-budget-wrapper.lsl")])
if capture_status() == 0 or config_budget_output.find("Configuration graph exceeds 16 MiB") < 0:
    Error(TestFailure: "configuration aggregate source budget was not enforced")
end
config_budget_source = ""
config_budget_index = 0
while config_budget_index < 16:
    call unlink(config_budget_directory + "/part" + String(config_budget_index) + ".lsl")
    config_budget_index += 1
end
call unlink(config_budget_entry)
call rmdir(config_budget_directory)
call gc()

time_impure_evaluator = test_path("time-impure-evaluator.lsl")
time_impure_output = capture(configure, ["tests/config/time_impure.lsl", time_impure_evaluator])
if time_impure_output != readfile("tests/config/time_impure.out") or exists(time_impure_evaluator):
    Error(TestFailure: "config time purity diagnostic differs")
end
os_impure_evaluator = test_path("os-impure-evaluator.lsl")
os_impure_output = capture(configure, ["tests/config/os_impure.lsl", os_impure_evaluator])
if os_impure_output != readfile("tests/config/os_impure.out") or exists(os_impure_evaluator):
    Error(TestFailure: "config os purity diagnostic differs")
end
system_impure_evaluator = test_path("system-impure-evaluator.lsl")
system_impure_output = capture(configure, ["tests/config/system_impure.lsl", system_impure_evaluator])
if system_impure_output != readfile("tests/config/system_impure.out") or exists(system_impure_evaluator):
    Error(TestFailure: "config system purity diagnostic differs")
end
whitespace_impure_output = capture(configure, ["tests/config/whitespace_impure.lsl", test_path("whitespace-impure-evaluator.lsl")])
if whitespace_impure_output != readfile("tests/config/whitespace_impure.out"):
    Error(TestFailure: "config whitespace purity diagnostic differs")
end
raw_impure_output = capture(configure, ["tests/config/raw_impure.lsl", test_path("raw-impure-evaluator.lsl")])
if raw_impure_output != readfile("tests/config/raw_impure.out"):
    Error(TestFailure: "config raw purity diagnostic differs")
end
check_impure_output = capture(configure, ["tests/config/check_impure.lsl", test_path("check-impure-evaluator.lsl")])
if check_impure_output != readfile("tests/config/check_impure.out"):
    Error(TestFailure: "config process-check purity diagnostic differs")
end
printl_impure_output = capture(configure, ["tests/config/printl_impure.lsl", test_path("printl-impure-evaluator.lsl")])
if printl_impure_output != readfile("tests/config/printl_impure.out"):
    Error(TestFailure: "config formatted-print purity diagnostic differs")
end
lux_impure_output = capture(configure, ["tests/config/lux_impure.lsl", test_path("lux-impure-evaluator.lsl")])
if lux_impure_output != readfile("tests/config/lux_impure.out"):
    Error(TestFailure: "config Lux-string purity diagnostic differs")
end
snapshot_source_directory = test_path("config-snapshot-source")
snapshot_directory = test_path("config-snapshot")
call mkdir(snapshot_source_directory)
call mkdir(snapshot_directory)
snapshot_source = snapshot_source_directory + "/entry.lsl"
call writefile(snapshot_source, "load config\nconfig = {\"value\": 1}\n")
snapshot_wrapper_source = capture(configure, [snapshot_source, "-", snapshot_directory])
if capture_status() != 0:
    Error(TestFailure: "config snapshot generation failed")
end
# Changing the original after validation must not change what gets compiled.
call writefile(snapshot_source, "load config\nconfig = {\"value\": 2}\n")
snapshot_wrapper = snapshot_directory + "/wrapper.lsl"
call writefile(snapshot_wrapper, snapshot_wrapper_source)
snapshot_evaluator = test_path("config-snapshot-evaluator")
call require_success(run(compiler, [snapshot_wrapper, snapshot_evaluator]), "compile snapshotted config evaluator")
snapshot_output = capture(snapshot_evaluator, [])
if capture_status() != 0 or snapshot_output != "{\"value\":1}" + chr(10):
    Error(TestFailure: "config snapshot changed after validation")
end
config_wrapper = "tests/config/.defaults-test-" + test_token + "-evaluator.lsl"
call require_success(run(configure, ["tests/config/defaults.lsl", config_wrapper]), "generate config defaults evaluator")
config_defaults_test = test_path("config-defaults-test")
call require_success(run(compiler, [config_wrapper, config_defaults_test]), "compile config defaults evaluator")
call unlink(config_wrapper)
call require_output(config_defaults_test, [], "tests/config/defaults.out", "config defaults output differs")

lazy_wrapper = "tests/config/.lazy-test-" + test_token + "-evaluator.lsl"
call require_success(run(configure, ["tests/config/lazy.lsl", lazy_wrapper]), "generate lazy config evaluator")
config_lazy_test = test_path("config-lazy-test")
call require_success(run(compiler, [lazy_wrapper, config_lazy_test]), "compile lazy config evaluator")
call unlink(lazy_wrapper)
call require_output(config_lazy_test, [], "tests/config/lazy.out", "lazy config output differs")

value_cycle_wrapper = "tests/config/.value-cycle-test-" + test_token + "-evaluator.lsl"
call require_success(run(configure, ["tests/config/value_cycle.lsl", value_cycle_wrapper]), "generate cyclic-value config evaluator")
config_value_cycle_test = test_path("config-value-cycle-test")
call require_success(run(compiler, [value_cycle_wrapper, config_value_cycle_test]), "compile cyclic-value config evaluator")
call unlink(value_cycle_wrapper)
value_cycle_output = capture(config_value_cycle_test, [])
if capture_status() == 0 or value_cycle_output != "" or capture_stderr() != readfile("tests/config/value_cycle.err"):
    Error(TestFailure: "cyclic configuration value was not rejected")
end

type_error_wrapper = "tests/config/.type-error-test-" + test_token + "-evaluator.lsl"
call require_success(run(configure, ["tests/config/type_error.lsl", type_error_wrapper]), "generate config type-error evaluator")
config_type_error_test = test_path("config-type-error-test")
call require_success(run(compiler, [type_error_wrapper, config_type_error_test]), "compile config type-error evaluator")
call unlink(type_error_wrapper)
call require_output(config_type_error_test, [], "tests/config/type_error.out", "config type-error provenance differs")

generated_wrapper = "tests/config/.generated-test-" + test_token + "-evaluator.lsl"
call require_success(run(configure, ["tests/config/generated.lsl", generated_wrapper]), "generate config fuzz evaluator")
config_generated_test = test_path("config-generated-test")
call require_success(run(compiler, [generated_wrapper, config_generated_test]), "compile config fuzz evaluator")
call unlink(generated_wrapper)
generated_config_output = capture(config_generated_test, [])
config_generated_check = test_path("config-generated-check")
call require_success(run(compiler, ["tests/config_generated_check.lsl", config_generated_check]), "compile config fuzz checker")
call require_output(config_generated_check, [generated_config_output], "tests/config_generated_check.out", "config fuzz output differs")

config_cycle_output = capture(configure, ["tests/config/cycle_a.lsl", test_path("cycle-evaluator.lsl")])
if config_cycle_output != readfile("tests/config/cycle.out"):
    Error(TestFailure: "config cycle diagnostic differs")
end

call require_fixed_point_compiler()

print "pure LSL tests passed"
