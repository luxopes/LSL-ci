#!/usr/bin/env python3
"""Exercise public Any-to-Int boundaries with deliberate heap-address collisions.

The baseline is optional and must fail the deterministic collision fixture.
The candidate must also match an independent integer recurrence across repeated
processes, including enough allocations for automatic GC. No runtime is rebuilt.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def memory_limit():
    resource.setrlimit(resource.RLIMIT_AS, (4 * 1024**3, 4 * 1024**3))


def run(command, timeout=60):
    start = time.monotonic()
    process = subprocess.Popen([str(arg) for arg in command], cwd=ROOT,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               start_new_session=True, preexec_fn=memory_limit)
    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate()
    return {"command": [str(arg) for arg in command],
            "seconds": time.monotonic() - start,
            "returncode": process.returncode, "timed_out": timed_out,
            "stdout": stdout.decode(errors="replace"),
            "stderr": stderr.decode(errors="replace")}


def recurrence(count):
    # Python integers and modulus supply an oracle independent of LSL boxing,
    # machine overflow and the compiler's bitwise operator lowering.
    value = 1
    for _ in range(count):
        value = (value * 1664525 + 1013904223) % 2147483648
    return str(value) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--backend", type=Path, required=True)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--build-directory", type=Path,
                        default=ROOT / "build/qbe-public-int")
    parser.add_argument("--repeats", type=int, default=5)
    args = parser.parse_args()
    if args.repeats < 1:
        parser.error("--repeats must be positive")
    build = args.build_directory.resolve()
    build.mkdir(parents=True, exist_ok=True)
    compiler, backend = args.compiler.resolve(), args.backend.resolve()
    report = {"complete": False, "compiler_sha256": digest(compiler),
              "backend_sha256": digest(backend),
              "runtime_sha256": digest(ROOT / "build/qbe/runtime.o"),
              "emitter_sha256": digest(ROOT / "compiler/pure/qbe_emit.lsl"),
              "builds": [], "checks": []}
    report_path = build / "verification.json"

    def save():
        report_path.write_text(json.dumps(report, indent=2) + "\n")

    def compile_case(frontend, name, suffix, native=False):
        source = ROOT / "tests/qbe" / (name + ".lsl")
        output = build / (name + "-" + suffix)
        # The installed baseline predates the native --unsafe option.
        sample = run([frontend] + (["--unsafe"] if native else []) + [source, output, backend])
        sample["source_sha256"] = digest(source)
        report["builds"].append(sample)
        save()
        if sample["returncode"]:
            raise RuntimeError("compilation failed: " + str(source))
        sample["binary_sha256"] = digest(output)
        return output

    try:
        expected = (ROOT / "tests/qbe/public_int_collision.out").read_text()
        if args.baseline:
            baseline = args.baseline.resolve()
            report["baseline_sha256"] = digest(baseline)
            output = compile_case(baseline, "public_int_collision", "before")
            sample = run([output])
            sample["expected_failure"] = (sample["returncode"] != 0 or
                                          sample["stdout"] != expected)
            report["baseline_collision"] = sample
            save()
            if not sample["expected_failure"]:
                raise RuntimeError("baseline did not reproduce the collision")

        output = compile_case(compiler, "public_int_collision", "fixed", native=True)
        for repeat in range(args.repeats):
            sample = run([output])
            sample.update(case="collision", repeat=repeat,
                          matches=sample["returncode"] == 0 and
                          sample["stdout"] == expected)
            report["checks"].append(sample)
            save()
            if not sample["matches"]:
                raise RuntimeError("heap-address collision regression")

        output = compile_case(compiler, "public_int_recurrence", "fixed", native=True)
        for count in (0, 1, 100, 200000, 1000000):
            expected = recurrence(count)
            for repeat in range(args.repeats):
                sample = run([output, count])
                sample.update(case="recurrence", iterations=count,
                              repeat=repeat, expected=expected,
                              matches=sample["returncode"] == 0 and
                              sample["stdout"] == expected)
                report["checks"].append(sample)
                save()
                if not sample["matches"]:
                    raise RuntimeError("public-call recurrence regression")
        report["complete"] = True
    except Exception as error:
        report["error"] = str(error)
    save()
    print(("PASS" if report["complete"] else "FAIL") + ": " + str(report_path))
    return 0 if report["complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
