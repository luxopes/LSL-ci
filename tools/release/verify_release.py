#!/usr/bin/env python3
"""Run the maintained Linux x86_64 LuxIR release gates on staged binaries.

Run after staging the complete release and freezing its sources. This does not
build a release, publish it, or replace the user's installation. Managed install
tests create their own private prefix below --managed-parent. Elapsed times are
correctness diagnostics, not isolated performance measurements.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import resource
import signal
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def memory_limit():
    resource.setrlimit(resource.RLIMIT_AS, (4 * 1024**3, 4 * 1024**3))


def source_manifest(root):
    result = {}
    for directory in ("compiler/pure", "stdlib", "tests", "tools/qbe", "tools/release"):
        for path in sorted((root / directory).rglob("*")):
            if path.is_file() and path.suffix in (".lsl", ".out", ".err", ".py"):
                result[str(path.relative_to(root))] = digest(path)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luxir-source", type=Path,
                        default=ROOT / "build/dependencies/LuxIR/lsl/luxir.lsl",
                        help="actual separate LuxIR entry source; required for its fixed-point gate")
    parser.add_argument("--report", type=Path,
                        default=ROOT / "build/release-preflight/verification.json")
    parser.add_argument("--build-directory", type=Path,
                        default=ROOT / "build/release-preflight")
    parser.add_argument("--managed-parent", type=Path, default=Path.home(),
                        help="secure parent for isolated installation; /tmp is not suitable")
    parser.add_argument("--old-installer", type=Path,
                        default=Path.home() / ".local/bin/lsl-install")
    parser.add_argument("--expected-version", default="0.9.1",
                        help="canonical machine version; BETA is a separate display label")
    parser.add_argument("--timeout", type=int, default=3600,
                        help="complete original corpus timeout, at least 1800 seconds")
    args = parser.parse_args()
    if args.timeout < 1800:
        parser.error("--timeout must be at least 1800 seconds for the complete corpus")
    build, report_path = args.build_directory.resolve(), args.report.resolve()
    build.mkdir(parents=True, exist_ok=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    frontend = ROOT / "compiler/pure/lslc-qbe"
    backend = ROOT / "build/luxir/luxir"
    cli = ROOT / "compiler/pure/lsl-cli"
    installer = ROOT / "compiler/pure/lsl-install"
    old_installer = args.old_installer.resolve()
    luxir_source = args.luxir_source.resolve()
    artifacts = {
        "frontend": frontend, "compiler_alias": ROOT / "compiler/lslc",
        "backend": backend, "cli": cli, "installer": installer,
        "configure": ROOT / "compiler/pure/lsl-configure",
        "test_runner": ROOT / "tests/lsl-test",
        "runtime": ROOT / "compiler/qbe/runtime.o",
        "runtime_compatibility": ROOT / "build/qbe/runtime.o",
        "old_installer": old_installer,
    }
    report = {
        "scope": "Linux x86_64 staged 0.9.1 release through native LuxIR",
        "correctness_only": True, "expected_version": args.expected_version,
        "root": str(ROOT), "platform": platform.platform(),
        "luxir_source": str(luxir_source), "commands": [],
        "complete": False, "all_pass": False,
        "optional_checks": {
            "cuda_hardware_requested": os.getenv("LSL_CUDA_HARDWARE_TEST") == "1",
            "signed_archive_install": "separate gate after signing the final archive",
            "stable_online_update": "not run; prerelease does not publish the stable channel",
        },
    }
    initial_sources, initial_artifacts, initial_installed = {}, {}, {}

    def save():
        temporary = report_path.with_name(report_path.name + ".tmp")
        temporary.write_text(json.dumps(report, indent=2) + "\n")
        temporary.replace(report_path)

    def checked(name, command, timeout=180, expected_stdout=None, gate_report=None):
        command = [str(item) for item in command]
        start = time.monotonic()
        row = {"name": name, "command": command, "timeout_seconds": timeout,
               "returncode": None, "timed_out": False, "stdout": "", "stderr": ""}
        report["commands"].append(row)
        save()
        environment = os.environ.copy()
        environment["LUXIR_SOURCE"] = (str(luxir_source.relative_to(ROOT))
                                       if luxir_source.is_relative_to(ROOT) else str(luxir_source))
        environment["LSL_BACKEND"] = str(backend)
        try:
            process = subprocess.Popen(command, cwd=ROOT, env=environment,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                       start_new_session=True, preexec_fn=memory_limit)
            try:
                stdout, stderr = process.communicate(timeout=timeout)
            except subprocess.TimeoutExpired:
                row["timed_out"] = True
                os.killpg(process.pid, signal.SIGKILL)
                stdout, stderr = process.communicate()
            row["returncode"] = process.returncode
            row["stdout"] = stdout.decode(errors="replace")
            row["stderr"] = stderr.decode(errors="replace")
            number = len(report["commands"])
            for stream_name, contents in (("stdout", stdout), ("stderr", stderr)):
                path = build / f"{number:02d}-{stream_name}.log"
                path.write_bytes(contents)
                row[stream_name + "_log"] = str(path)
                row[stream_name + "_sha256"] = digest(path)
        except OSError as error:
            row["launch_error"] = str(error)
        finally:
            row["seconds"] = time.monotonic() - start
            save()
        if row["returncode"] != 0 or row["timed_out"]:
            raise RuntimeError(f"{name} failed: status={row['returncode']}, timeout={row['timed_out']}")
        if expected_stdout is not None and row["stdout"] != expected_stdout:
            raise RuntimeError(f"{name}: unexpected output")
        if gate_report is not None:
            data = json.loads(gate_report.read_text())
            row["gate_report"] = str(gate_report)
            row["gate_report_sha256"] = digest(gate_report)
            for field in ("all_pass", "complete", "binaries_unchanged", "sources_unchanged", "compiler_unchanged"):
                if field in data and data[field] is not True:
                    raise RuntimeError(f"{name}: gate report {field} is not true")
            if name == "registered native regressions":
                tests = data.get("tests", [])
                if len(tests) < 43 or any(case.get("status") != "PASS" for case in tests):
                    raise RuntimeError("registered native regression report is incomplete")
                row["passed_cases"] = len(tests)
        row["passed"] = True
        save()
        print("PASS", name, flush=True)

    save()
    try:
        if platform.system() != "Linux" or platform.machine() not in ("x86_64", "amd64"):
            raise RuntimeError("this release preflight requires Linux x86_64")
        if not luxir_source.is_file():
            raise RuntimeError(f"LuxIR source required for backend self-host: {luxir_source}")
        for name, path in artifacts.items():
            if not path.is_file() or path.stat().st_size == 0:
                raise RuntimeError(f"missing staged artifact {name}: {path}")
            if name not in ("runtime", "runtime_compatibility") and not os.access(path, os.X_OK):
                raise RuntimeError(f"artifact is not executable: {path}")
            initial_artifacts[name] = {"path": str(path), "sha256": digest(path)}
        if initial_artifacts["runtime"]["sha256"] != initial_artifacts["runtime_compatibility"]["sha256"]:
            raise RuntimeError("canonical and compatibility runtime objects differ")
        if initial_artifacts["frontend"]["sha256"] != initial_artifacts["compiler_alias"]["sha256"]:
            raise RuntimeError("compiler/lslc differs from staged native frontend")
        initial_sources = source_manifest(ROOT)
        initial_installed = {str(path): digest(path) for path in sorted(old_installer.parent.glob("lsl*"))
                             if path.is_file()}
        luxir_sources = {str(path): digest(path) for path in sorted(luxir_source.parent.rglob("*.lsl"))}
        report.update(artifacts=initial_artifacts, source_manifest=initial_sources,
                      source_manifest_sha256=hashlib.sha256(json.dumps(initial_sources, sort_keys=True).encode()).hexdigest(),
                      luxir_source_manifest=luxir_sources, installed_tools_before=initial_installed)
        save()
        checked("release machine version", [cli, "version"], expected_stdout=args.expected_version + "\n")
        checked("release machine version flag", [cli, "--version"], expected_stdout=args.expected_version + "\n")
        checked("complete original corpus and both compiler fixed points", [
            sys.executable, ROOT / "tools/qbe/verify_integration.py", "--compiler", frontend,
            "--build-directory", build / "original-runner", "--report", build / "original-runner.json",
            "--mode", "qbe", "--timeout", args.timeout], timeout=args.timeout + 180,
            gate_report=build / "original-runner.json")
        managed = build / "install-managed-integration"
        checked("compile managed installation gate", [frontend, "--unsafe",
                ROOT / "tests/compiler/install_managed_integration.lsl", managed, backend])
        checked("isolated legacy migration, two reinstalls and two rollbacks", [
            managed, args.managed_parent.resolve(), old_installer, installer, cli], timeout=600,
            expected_stdout="Legacy migration, managed reinstall and rollback passed.\n")
        checked("native image hardening and cleanup", [sys.executable,
            ROOT / "tools/qbe/verify_image.py", "--compiler", frontend, "--backend", backend,
            "--build-directory", build / "image", "--report", build / "image.json"],
            gate_report=build / "image.json")
        checked("public CLI safety, compile, run and config", [sys.executable,
            ROOT / "tools/qbe/verify_cli_pipeline.py", "--compiler", frontend, "--cli", cli,
            "--build-directory", build / "public-cli"], timeout=300,
            gate_report=build / "public-cli/verification.json")
        checked("registered native regressions", [sys.executable, ROOT / "tools/qbe/verify.py",
            "--tests-only", "--compiler", frontend, "--backend", backend,
            "--build-directory", build / "registered"], timeout=600,
            gate_report=build / "registered/verification.json")
        report["luxir_sources_unchanged"] = all(Path(path).is_file() and digest(Path(path)) == value
                                                 for path, value in luxir_sources.items())
        report["complete"] = True
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
        print("FAIL", error, file=sys.stderr, flush=True)
    finally:
        report["artifacts_unchanged"] = bool(initial_artifacts) and all(
            Path(value["path"]).is_file() and digest(Path(value["path"])) == value["sha256"]
            for value in initial_artifacts.values())
        report["sources_unchanged"] = bool(initial_sources) and source_manifest(ROOT) == initial_sources
        report["installed_tools_unchanged"] = bool(initial_installed) and all(
            Path(path).is_file() and digest(Path(path)) == value for path, value in initial_installed.items())
        report["all_pass"] = report["complete"] and all(report.get(field) is True for field in (
            "artifacts_unchanged", "sources_unchanged", "installed_tools_unchanged", "luxir_sources_unchanged"))
        save()
    print("PASS release preflight" if report["all_pass"] else "FAIL release preflight", flush=True)
    return 0 if report["all_pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
