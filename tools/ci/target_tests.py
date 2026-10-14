#!/usr/bin/env python3
"""Testy cíle na skutečném stroji (CI): build přeloží každý tests/X.lsl
s tests/X.out pro cíl a pro hostitele; do balíku dá jen testy, které na
hostiteli bez argumentů dají X.out. run je spustí na cílovém stroji
(z kořene repozitáře) a porovná výstup a kód ukončení.

Použití:
  target_tests.py build --compiler LSLC --target windows-x86_64 --output DIR
  target_tests.py run DIR
"""
import argparse, concurrent.futures, json, os, pathlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests'))
from cross_targets import WINDOWS_SKIP  # noqa: E402


def run(command, timeout):
    try:
        r = subprocess.run(command, capture_output=True, timeout=timeout, cwd=ROOT, stdin=subprocess.DEVNULL)
        return r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        return 'timeout', b'', b''


def build_one(compiler, target, source, output):
    if target.startswith('windows-') and source.name in WINDOWS_SKIP:
        return None
    expected = source.with_suffix('.out').read_bytes()
    host = output / 'host' / source.stem
    status, _, _ = run([str(compiler), '--unsafe', str(source), str(host)], 600)
    if status != 0:
        return None
    status, out, _ = run([str(host)], 300)
    host.unlink()
    if status != 0 or out != expected:
        return None
    name = source.stem + ('.exe' if target.startswith('windows-') else '')
    status, _, error = run([str(compiler), '--unsafe', '--target', target, str(source), str(output / name)], 600)
    if status != 0:
        raise SystemExit(f'{source.name}: cross compile failed: {error.decode(errors="replace")[:400]}')
    (output / (source.stem + '.out')).write_bytes(expected)
    return {'name': source.name, 'binary': name, 'expected': source.stem + '.out'}


def build(a):
    output = a.output.resolve()
    (output / 'host').mkdir(parents=True, exist_ok=True)
    sources = sorted(p for p in (ROOT / 'tests').glob('*.lsl') if p.with_suffix('.out').exists())
    with concurrent.futures.ThreadPoolExecutor(a.j) as pool:
        tests = [t for t in pool.map(lambda s: build_one(a.compiler.resolve(), a.target, s, output), sources) if t]
    (output / 'host').rmdir()
    (output / 'tests.json').write_text(json.dumps({'target': a.target, 'tests': tests}, indent=1))
    print(f'{a.target}: {len(tests)} tests packed into {output}')


def run_tests(a):
    directory = a.directory.resolve()
    manifest = json.loads((directory / 'tests.json').read_text())
    failures = 0
    for test in manifest['tests']:
        binary = directory / test['binary']
        if os.name != 'nt':
            binary.chmod(0o755)
        status, out, error = run([str(binary)], a.timeout)
        expected = (directory / test['expected']).read_bytes()
        if status == 0 and out == expected:
            print(f'ok      {test["name"]}', flush=True)
        else:
            failures += 1
            print(f'FAIL    {test["name"]}: status {status}; stderr: {error.decode(errors="replace").strip()[:300]}', flush=True)
            if out != expected:
                print(f'        stdout: {out[:300]!r}', flush=True)
                print(f'        expected: {expected[:300]!r}', flush=True)
    print(f'{manifest["target"]}: {len(manifest["tests"]) - failures} of {len(manifest["tests"])} passed')
    return 1 if failures else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='command', required=True)
    b = sub.add_parser('build')
    b.add_argument('--compiler', type=pathlib.Path, required=True)
    b.add_argument('--target', required=True)
    b.add_argument('--output', type=pathlib.Path, required=True)
    b.add_argument('-j', type=int, default=os.cpu_count())
    r = sub.add_parser('run')
    r.add_argument('directory', type=pathlib.Path)
    r.add_argument('--timeout', type=int, default=300)
    a = ap.parse_args()
    if a.command == 'build':
        return build(a)
    return run_tests(a)


if __name__ == '__main__':
    sys.exit(main())
