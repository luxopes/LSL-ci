#!/usr/bin/env python3
"""Testy cíle na skutečném stroji (CI): build přeloží každý tests/X.lsl
s tests/X.out pro cíl a pro hostitele; do balíku dá jen testy, které na
hostiteli bez argumentů dají X.out. run je spustí na cílovém stroji
(z kořene repozitáře) a porovná výstup a kód ukončení.

native přeloží tytéž testy nativním překladačem z balíku (PACKAGE/bin) přímo
na cílovém stroji, spustí je a ověří fixed point překladače (stupeň 2 =
stupeň 3, oba přeložené nativně).

Použití:
  target_tests.py build --compiler LSLC --target windows-x86_64 --output DIR
  target_tests.py run DIR
  target_tests.py native PACKAGE DIR
"""
import argparse, concurrent.futures, json, os, pathlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests'))
from cross_targets import skip_reason  # noqa: E402


def run(command, timeout):
    try:
        r = subprocess.run(command, capture_output=True, timeout=timeout, cwd=ROOT, stdin=subprocess.DEVNULL)
        return r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        return 'timeout', b'', b''


def build_one(compiler, target, source, output):
    if skip_reason(target, source.name):
        return None
    expected = source.with_suffix('.out').read_bytes()
    if source.parent.name != 'gnu':
        # Hostitelský (statický) překlad ověří, že test na stroji sestavení
        # platí; testy tests/gnu jsou jen pro cíl linux-x86_64-gnu.
        host = output / 'host' / source.stem
        status, _, _ = run([str(compiler), '--unsafe', str(source), str(host)], 600)
        if status != 0:
            return None
        status, out, _ = run([str(host)], 300)
        host.unlink()
        if status != 0 or out != expected:
            return None
    name = source.stem + ('.exe' if target.startswith('windows-') else '.wasm' if target.startswith('wasm32-') else '')
    status, _, error = run([str(compiler), '--unsafe', '--target', target, str(source), str(output / name)], 600)
    if status != 0:
        raise SystemExit(f'{source.name}: cross compile failed: {error.decode(errors="replace")[:400]}')
    (output / (source.stem + '.out')).write_bytes(expected)
    return {'name': source.name, 'binary': name, 'expected': source.stem + '.out'}


def build(a):
    output = a.output.resolve()
    (output / 'host').mkdir(parents=True, exist_ok=True)
    sources = sorted(p for p in (ROOT / 'tests').glob('*.lsl') if p.with_suffix('.out').exists())
    if a.target == 'linux-x86_64-gnu':
        # Moduly glib, gio a gtk jsou jen pro dynamicky linkovaný cíl.
        sources += sorted(p for p in (ROOT / 'tests/gnu').glob('*.lsl') if p.with_suffix('.out').exists())
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
        command = [str(binary)]
        if manifest['target'].startswith('wasm32-') and os.environ.get('LSL_WASM_RUNNER') == 'wasmtime':
            # wasmtime s wasi-threads; nativní zásobník wasm 8 MiB jako
            # zásobník nativního programu.
            command = ['wasmtime', 'run', '-W', 'threads=y', '-S', 'threads=y', '-S', 'inherit-env=y',
                       '-W', 'max-wasm-stack=8388608', '--dir', '/', '--dir', '.', str(binary)]
        elif manifest['target'].startswith('wasm32-'):
            command = ['node', '--no-warnings', str(ROOT / 'tools/wasi_run.mjs'), str(binary)]
        elif manifest['target'].startswith('baremetal-'):
            command = [sys.executable, str(ROOT / 'tools/baremetal_run.py'), str(binary)]
        elif manifest['target'].startswith('windows-') and os.environ.get('LSL_WINDOWS_RUNNER'):
            # Program pro Windows na jiném hostiteli (např. wine na Linuxu).
            command = [os.environ['LSL_WINDOWS_RUNNER'], str(binary)]
        status, out, error = run(command, a.timeout)
        expected = (directory / test['expected']).read_bytes()
        if status == 0 and out.startswith(b'SKIP: '):
            # Test sám zjistil, že mu na stroji chybí prostředí (Xvfb, D-Bus).
            print(f'skip    {test["name"]}: {out[6:].decode(errors="replace").strip()}', flush=True)
        elif status == 0 and out == expected:
            print(f'ok      {test["name"]}', flush=True)
        else:
            failures += 1
            print(f'FAIL    {test["name"]}: status {status}; stderr: {error.decode(errors="replace").strip()[:300]}', flush=True)
            if out != expected:
                print(f'        stdout: {out[:300]!r}', flush=True)
                print(f'        expected: {expected[:300]!r}', flush=True)
                # První lišící se řádek (dlouhé výstupy se liší až za ořezem).
                got_lines, want_lines = out.split(b'\n'), expected.split(b'\n')
                for number, (got, want) in enumerate(zip(got_lines, want_lines), 1):
                    if got != want:
                        print(f'        line {number}: {got[:300]!r} != {want[:300]!r}', flush=True)
                        break
                else:
                    print(f'        lines: {len(got_lines)} != {len(want_lines)}', flush=True)
    print(f'{manifest["target"]}: {len(manifest["tests"]) - failures} of {len(manifest["tests"])} passed')
    return 1 if failures else 0


def native(a):
    package = a.package.resolve()
    suffix = '.exe' if os.name == 'nt' else ''
    compiler = package / 'bin' / ('lslc' + suffix)
    status, out, error = run([str(package / 'bin' / ('lsl' + suffix)), 'version'], 60)
    print('lsl version:', status, out.decode(errors='replace').strip(), error.decode(errors='replace').strip()[:300], flush=True)
    if status != 0:
        return 1
    lsl = str(package / 'bin' / ('lsl' + suffix))
    commands = [['about'], ['help'], ['list'], ['about', 'json']]
    if (package / 'lib/lsl/docs/developer_guides/18-platforms.md').exists():
        # Balík vydání s manuálem (CI ho bez zdroje webu nemá).
        commands.append(['man', '--plain', '18-platforms'])
    for command in commands:
        status, out, error = run([lsl, *command], 120)
        print('lsl', ' '.join(command) + ':', status, len(out), 'bytes', error.decode(errors='replace').strip()[:200], flush=True)
        if status != 0 or len(out) == 0:
            return 1
    manifest = json.loads((a.directory.resolve() / 'tests.json').read_text())
    work = a.directory.resolve() / 'native'
    work.mkdir(exist_ok=True)
    failures = 0

    extensions = {path.stem for path in (ROOT / 'extensions').glob('*.lsl')}

    def one(test):
        source = ROOT / 'tests' / test['name']
        loads = {line.split()[1] for line in source.read_text(encoding='utf-8').splitlines()
                 if line.startswith('load ') and len(line.split()) > 1}
        if loads & extensions:
            # Nainstalovaný překladač rozšíření z extensions/ repozitáře nehledá.
            return test['name'], 'skip', b'needs repository extensions/'
        binary = work / (source.stem + suffix)
        status, _, error = run([str(compiler), '--unsafe', str(source), str(binary)], 900)
        if status != 0:
            return test['name'], 'compile', error
        status, out, error = run([str(binary)], a.timeout)
        # Očekávaný výstup z balíku (checkout na Windows mívá CRLF).
        expected = (a.directory.resolve() / test['expected']).read_bytes()
        if status == 0 and out == expected:
            return test['name'], 'ok', b''
        return test['name'], f'status {status}', error + b' stdout: ' + out[:300]

    with concurrent.futures.ThreadPoolExecutor(max(1, (os.cpu_count() or 2) // 2)) as pool:
        for name, result, detail in pool.map(one, manifest['tests']):
            if result == 'ok':
                print(f'ok      {name}', flush=True)
            elif result == 'skip':
                print(f'skip    {name}: {detail.decode()}', flush=True)
            else:
                failures += 1
                print(f'FAIL    {name}: {result}: {detail.decode(errors="replace").strip()[:400]}', flush=True)
    print(f'native {manifest["target"]}: {failures} failed of {len(manifest["tests"])}', flush=True)
    # Fixed point: lslc z balíku -> stupeň 2 -> stupeň 3 (z lib/lsl, relativní cesta).
    library = package / 'lib' / 'lsl'
    # Stupně leží v bin/ balíku, aby našly sousední luxir.
    stage2 = package / 'bin' / ('lslc-stage2' + suffix)
    stage3 = package / 'bin' / ('lslc-stage3' + suffix)
    for compiler_path, output in ((compiler, stage2), (stage2, stage3)):
        r = subprocess.run([str(compiler_path), 'compiler/pure/lslc_qbe.lsl', str(output)], cwd=library, capture_output=True, timeout=1800)
        if r.returncode != 0:
            print('FAIL    self-host:', r.stderr.decode(errors='replace')[:600], flush=True)
            return 1
    if stage2.read_bytes() != stage3.read_bytes():
        print('FAIL    native fixed point: stage 2 and stage 3 differ', flush=True)
        return 1
    print(f'native fixed point: stage 2 == stage 3 ({stage2.stat().st_size} bytes)', flush=True)
    # Instalace do prefixu a překlad z ní.
    prefix = work / 'prefix'
    status, out, error = run([str(package / 'bin' / ('lsl-install' + suffix)), str(prefix)], 600)
    print('lsl-install:', status, out.decode(errors='replace').strip()[:300], error.decode(errors='replace').strip()[:300], flush=True)
    if status != 0:
        print('FAIL    lsl-install', flush=True)
        return 1
    hello = work / 'hello.lsl'
    hello.write_text('x = [3, 1, 2]\nx.sort()\nprint "installed", x\n')
    program = work / ('hello' + suffix)
    status, out, error = run([str(prefix / 'bin' / ('lsl' + suffix)), 'compile', str(hello), str(program)], 600)
    if status == 0:
        status, out, error = run([str(program)], 60)
    if status != 0 or out.replace(b'\r', b'') != b'installed [1, 2, 3]\n':
        print('FAIL    installed compiler:', status, out[:200], error.decode(errors='replace')[:400], flush=True)
        return 1
    print('installed compiler: ok', flush=True)
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
    n = sub.add_parser('native')
    n.add_argument('package', type=pathlib.Path)
    n.add_argument('directory', type=pathlib.Path)
    n.add_argument('--timeout', type=int, default=300)
    a = ap.parse_args()
    if a.command == 'build':
        return build(a)
    if a.command == 'native':
        return native(a)
    return run_tests(a)


if __name__ == '__main__':
    sys.exit(main())
