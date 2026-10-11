#!/usr/bin/env python3
"""Bootstrap the LSL frontend using the LuxIR C reference backend.

The backend is the separate LuxIR project (https://git.lux-ai.cz/LuxAI/LuxIR).
Its C reference build is used only for this initial bootstrap; ordinary
compiler invocations use the native LSL build of LuxIR and never fall back
to the C reference.
"""
import argparse
import pathlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
BUILD = ROOT / "build/qbe"


def run(*args):
    subprocess.run([str(a) for a in args], cwd=ROOT, check=True, timeout=600)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bootstrap", required=True,
                        help="existing native LSL compiler accepting SOURCE OUTPUT")
    parser.add_argument("--luxir", required=True,
                        help="LuxIR checkout (contains src/ and lsl/luxir.lsl)")
    args = parser.parse_args()
    bootstrap = pathlib.Path(args.bootstrap).resolve(strict=True)
    luxir = pathlib.Path(args.luxir).resolve(strict=True)
    BUILD.mkdir(parents=True, exist_ok=True)
    # C reference LuxIR: jen pro první stage, nikdy pro běžný překlad.
    subprocess.run(["make", "-C", str(luxir / "src"), "luxir"], check=True, timeout=600)
    reference = BUILD / "luxir-c"
    shutil.copy2(luxir / "src/luxir", reference)
    run(bootstrap, "compiler/pure/qbe_runtime_dump.lsl", BUILD / "runtime-dump")
    run(BUILD / "runtime-dump", BUILD / "runtime")
    run("python3", "tools/qbe/runtime_object.py", BUILD / "runtime")
    run(bootstrap, "compiler/pure/lslc_qbe.lsl", BUILD / "stage1")
    run(BUILD / "stage1", "compiler/pure/lslc_qbe.lsl", BUILD / "stage2", reference)
    # stage3 už je celý přeložený novým frontendem; vlastnosti starého
    # bootstrap compileru se tak nepřenesou do dalších kroků.
    run(BUILD / "stage2", "compiler/pure/lslc_qbe.lsl", BUILD / "stage3", reference)
    # Nativní LuxIR v LSL a frontend znovu přes něj.
    native = ROOT / "build/luxir/luxir"
    native.parent.mkdir(parents=True, exist_ok=True)
    run(BUILD / "stage3", luxir / "lsl/luxir.lsl", native, reference)
    run(BUILD / "stage3", "compiler/pure/lslc_qbe.lsl", BUILD / "stage4", native)
    print("bootstrap frontend:", BUILD / "stage4")
    print("native LuxIR backend:", native)


if __name__ == "__main__":
    main()
