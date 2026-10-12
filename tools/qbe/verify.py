#!/usr/bin/env python3
"""Verify frontend fixed points and language regressions with a chosen backend.

The historical default is build/qbe/qbe, the external C-reference bootstrap
tool. Pass --backend /path/to/lsl-qbe for native LSL backend verification.
Use tools/qbe_port/verify_selfhost.py to prove both frontend and backend fixed
points in a complete all-LSL generation.
"""
import argparse
import hashlib
import json
import os
import pathlib
import platform
import resource
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
BUILD = ROOT / "build/qbe"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def limit_memory():
    resource.setrlimit(resource.RLIMIT_AS, (4 * 1024**3, 4 * 1024**3))


def run(command, timeout=60):
    start = time.monotonic()
    result = subprocess.run([str(x) for x in command], cwd=ROOT,
                            capture_output=True, timeout=timeout,
                            preexec_fn=limit_memory)
    elapsed = time.monotonic() - start
    if result.returncode:
        raise RuntimeError(f"{command}: exit {result.returncode}\n"
                           + result.stdout.decode(errors="replace")
                           + result.stderr.decode(errors="replace"))
    return result, elapsed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", default=str(BUILD / "stage2"))
    parser.add_argument("--backend", type=pathlib.Path,
                        help="backend for every compile; historical default build/qbe/qbe is C QBE, so pass the native LSL backend explicitly for native verification")
    parser.add_argument("--build-directory", type=pathlib.Path, default=BUILD)
    parser.add_argument("--runtime", type=pathlib.Path, default=None,
                        help="runtime object; default build/qbe/runtime.o, else the release compiler/qbe/runtime.o")
    parser.add_argument("--tests-only", action="store_true",
                        help="run language regressions with an already verified compiler")
    args = parser.parse_args()
    compiler = pathlib.Path(args.compiler).resolve()
    backend = args.backend.resolve() if args.backend else BUILD / "qbe"
    build = args.build_directory.resolve()
    build.mkdir(parents=True, exist_ok=True)
    report = {"platform": platform.platform(), "cpu_count": os.cpu_count(),
              "qbe_version": "1.3", "selfhost": [], "tests": [],
              "tests_only": args.tests_only, "backend": str(backend)}
    images = [compiler]
    for generation in (() if args.tests_only else (3, 4)):
        output = build / f"stage{generation}"
        _, elapsed = run([images[-1], "compiler/pure/lslc_qbe.lsl", output, backend])
        assert elapsed < 60, elapsed
        images.append(output)
        report["selfhost"].append({"compiler": str(images[-2]),
                                   "output": str(output), "seconds": elapsed,
                                   "sha256": digest(output)})
        print(f"Self-host generation {generation}: {elapsed:.3f}s", flush=True)
    if not args.tests_only:
        report["fixed_point"] = images[-2].read_bytes() == images[-1].read_bytes()
        assert report["fixed_point"], "self-host binary generations differ"
        # A trusted bootstrap may predate the source changes being verified.
        report["bootstrap_matches_current_source"] = images[0].read_bytes() == images[1].read_bytes()
    cases = [ROOT / "tests/qbe/minimal.lsl", ROOT / "tests/qbe/core.lsl",
             ROOT / "tests/qbe/native_global_initialization.lsl",
             ROOT / "tests/qbe/native_builtin_return_types.lsl",
             ROOT / "tests/qbe/return_dependency_inference.lsl",
             ROOT / "tests/qbe/public_int_collision.lsl",
             ROOT / "tests/qbe/public_gc_roots.lsl",
             ROOT / "tests/qbe/intarray_store.lsl",
             ROOT / "tests/qbe/checked_collection_casts.lsl",
             ROOT / "tests/qbe/collection_codegen.lsl",
             ROOT / "tests/qbe/dynamic_sequence_load.lsl",
             ROOT / "tests/qbe/atomic_native.lsl",
             ROOT / "tests/qbe/startup_tables.lsl",
             ROOT / "tests/qbe/string_contiguous_slice.lsl",
             ROOT / "tests/qbe/native_float_arithmetic.lsl",
             ROOT / "tests/qbe/native_float_boundaries.lsl",
             ROOT / "tests/qbe/native_float_effects.lsl",
             ROOT / "tests/qbe/native_float_literals.lsl",
             ROOT / "tests/qbe/public_any_arithmetic.lsl",
             ROOT / "tests/qbe/public_call_inference.lsl",
             ROOT / "tests/qbe/public_default_call_flow.lsl",
             ROOT / "tests/qbe/classes.lsl",
             ROOT / "tests/qbe/class_default_call_flow.lsl",
             ROOT / "tests/class_method_return_conformance.lsl",
             ROOT / "tests/wide_class_abi_conformance.lsl",
             ROOT / "tests/inheritance_conformance.lsl",
             ROOT / "tests/class_module_smoke.lsl",
             ROOT / "tests/origin_function_conformance.lsl"]
    cases += [ROOT / f"tests/{name}_conformance.lsl" for name in
              ("abs", "dynamic_arith", "dynamic_numeric_boundary", "float_power", "float_floordiv", "boxed_int_infrastructure", "parameter_inference", "bitwise", "unicode_case", "integer_wrap",
               "truthiness", "recursive_return", "string_conversion",
               "boxed_collection", "float_conversion")]
    for index, source in enumerate(cases):
        output = build / f"verify-case-{index}"
        _, elapsed = run([images[-1], "--unsafe", source.relative_to(ROOT), output, backend])
        result, _ = run([output], timeout=10)
        expected = source.with_suffix(".out").read_bytes()
        assert result.stdout == expected, f"output differs: {source}\n{result.stdout!r}"
        report["tests"].append({"source": str(source.relative_to(ROOT)),
                                 "status": "PASS", "compile_seconds": elapsed})
        print("PASS", source.name, flush=True)
    report["maxrss_kib"] = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
    report["source_sha256"] = {str(p.relative_to(ROOT)): digest(p) for p in
                              sorted((ROOT / "compiler/pure").glob("*.lsl"))}
    runtime = args.runtime or (BUILD / "runtime.o" if (BUILD / "runtime.o").exists() else ROOT / "compiler/qbe/runtime.o")
    report["runtime_sha256"] = digest(runtime)
    report["qbe_sha256"] = digest(backend)
    (build / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    if args.tests_only:
        print("PASS: language regressions; self-host was not repeated")
    else:
        print("PASS: native self-host below 60s, identical generations; verification.json saved")


if __name__ == "__main__":
    main()
