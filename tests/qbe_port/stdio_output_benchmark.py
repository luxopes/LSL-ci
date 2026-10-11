#!/usr/bin/env python3
"""Compile and byte-check the stdio output stress fixture, then report timing."""
import argparse
import statistics
import subprocess
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tests/qbe_port/stdio_output_conformance.lsl"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path,
                        default=ROOT / "build/qbe-port-tools/native-selfhost/frontend-stage3")
    parser.add_argument("--qbe", type=Path, default=ROOT / "build/qbe/qbe")
    parser.add_argument("--runs", type=int, default=5)
    args = parser.parse_args()
    if args.runs < 1:
        parser.error("--runs must be positive")
    expected = "".join(f"{value:+08d}/0x{value:x}/{value}\n"
                       for value in range(1, 10001)).encode("ascii")
    expected += "|     é|abc     |-42|\n".encode("utf-8")
    expected += b"4294967295|BEEF|-42||     005\n"
    expected += ("|     é|abc     |é|-0000042|-00007|4294967295|1FF|777|\n"
                 .encode("utf-8"))
    with tempfile.TemporaryDirectory(prefix="qbe-stdio-output-") as temp:
        temp = Path(temp)
        source = SOURCE.read_text()
        marker = 'mem.literal("%+08d/0x%x/%u\\n")'
        if source.count(marker) != 1:
            raise SystemExit("could not locate benchmark format literal")
        dynamic_source = SOURCE.parent / f".stdio-output-dynamic-{time.time_ns()}.lsl"
        dynamic_source.write_text(source.replace(marker, 'mem.cstr("%+08d/0x%x/%u\\n")'))
        variants = {
            "literal plan": SOURCE,
            "dynamic format": dynamic_source,
        }
        timings = {}
        try:
            for label, source_path in variants.items():
                executable = temp / ("stdio-output-" + ("literal" if label == "literal plan" else "dynamic"))
                subprocess.run([str(args.compiler), str(source_path), str(executable), str(args.qbe)],
                               cwd=ROOT, check=True)
                elapsed = []
                for _ in range(args.runs):
                    start = time.perf_counter()
                    result = subprocess.run([str(executable)], stdout=subprocess.PIPE,
                                            stderr=subprocess.PIPE, check=False)
                    elapsed.append(time.perf_counter() - start)
                    if result.returncode != 0 or result.stderr or result.stdout != expected:
                        raise SystemExit(
                            f"{label} output mismatch: status={result.returncode}, "
                            f"stdout={len(result.stdout)}/{len(expected)} bytes, "
                            f"stderr={result.stderr[:200]!r}"
                        )
                timings[label] = statistics.median(elapsed)
        finally:
            dynamic_source.unlink(missing_ok=True)
    print(f"exact output: {len(expected)} bytes; medians over {args.runs} runs: "
          f"literal-plan={timings['literal plan']:.4f}s, "
          f"dynamic-format={timings['dynamic format']:.4f}s")


if __name__ == "__main__":
    main()
