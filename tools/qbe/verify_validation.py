#!/usr/bin/env python3
"""Check public error, callback, range and builtin boundaries against 0.8.9."""
import argparse
import json
from pathlib import Path

from verify_classes import ROOT, digest, execute

CASES = ["qbe/minimal", "qbe/validation_flow", "safe_recovery_conformance",
         "tagged_function_conformance", "rang_dynamic_conformance",
         "last_error_conformance", "dynamic_builtin_boundary_conformance",
         "minmax_help_conformance", "comprehension_conformance",
         "rang_value_conformance"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--backend", type=Path, required=True)
    parser.add_argument("--old", type=Path, default=Path.home()/".local/bin/lslc")
    parser.add_argument("--build-directory", type=Path, required=True)
    parser.add_argument("--self-host", action="store_true")
    args = parser.parse_args()
    build = args.build_directory.resolve()
    build.mkdir(parents=True, exist_ok=True)
    compilers = {"v089": args.old.resolve(), "candidate": args.compiler.resolve()}
    backend = args.backend.resolve()
    report = {"complete": False, "cases": [], "self_host": [],
              "inputs": {str(p): digest(p) for p in
                         [*compilers.values(), backend, ROOT/"build/qbe/runtime.o",
                          ROOT/"compiler/pure/qbe_emit.lsl",
                          ROOT/"compiler/pure/semantic.lsl"]}}
    path = build/"verification.json"

    def save():
        path.write_text(json.dumps(report, indent=2)+"\n")

    if args.self_host:
        for generation in (1, 2):
            output = build/f"frontend-generation-{generation}"
            result = execute([compilers["candidate"], "compiler/pure/lslc_qbe.lsl",
                              output, backend])
            report["self_host"].append(result)
            save()
            if result["returncode"] != 0 or result["timed_out"]:
                return 1
            result["binary_sha256"] = digest(output)
            compilers["candidate"] = output
            print("frontend generation", generation, result["seconds"], flush=True)
        report["fixed_point"] = (report["self_host"][0]["binary_sha256"] ==
                                 report["self_host"][1]["binary_sha256"])
    for name in CASES:
        source = ROOT/"tests"/(name+".lsl")
        expected = source.with_suffix(".out").read_text()
        row = {"source": str(source.relative_to(ROOT)), "source_sha256": digest(source),
               "expected": expected, "expected_sha256": digest(source.with_suffix(".out")),
               "runs": {}}
        report["cases"].append(row)
        for kind, compiler in compilers.items():
            output = build/(name.replace("/", "-")+"-"+kind)
            command = [compiler, source.relative_to(ROOT), output]
            if kind != "v089":
                command.append(backend)
            result = {"build": execute(command)}
            row["runs"][kind] = result
            if result["build"]["returncode"] == 0:
                result["binary_sha256"] = digest(output)
                result["execution"] = execute([output])
            execution = result.get("execution", {})
            result["passed"] = (execution.get("returncode") == 0 and
                                 execution.get("stdout") == expected)
            print(name, kind, "PASS" if result["passed"] else "FAIL", flush=True)
            save()
    report["inputs_unchanged"] = all(digest(Path(p)) == h for p, h in report["inputs"].items())
    report["complete"] = (report["inputs_unchanged"] and report.get("fixed_point", True)
                          and all(r["passed"] for c in report["cases"] for r in c["runs"].values()))
    save()
    return 0 if report["complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
