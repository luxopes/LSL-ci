#!/usr/bin/env python3
"""Konformní testy na dalších cílech: každý tests/X.lsl s tests/X.out se
přeloží pro cíl i pro hostitele, spustí (cizí architektura přes qemu-user
binfmt) a výstup se porovná s výstupem hostitele a s X.out.

Test, který bez argumentů neprojde ani na hostiteli (potřebuje argumenty,
vstup nebo prostředí test_runneru), se hlásí zvlášť jako "host-only".

Použití: cross_targets.py --compiler LSLC --target linux-arm64 [-j N] [TEST...]
"""
import argparse, concurrent.futures, os, pathlib, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]


def run(command, timeout):
    try:
        r = subprocess.run(command, capture_output=True, timeout=timeout, cwd=ROOT, stdin=subprocess.DEVNULL)
        return r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        return 'timeout', b'', b''


def check(compiler, target, source, scratch, timeout):
    expected = source.with_suffix('.out').read_bytes()
    results = {}
    # Jako test_runner v režimu qbe: korpus používá i surové služby runtime.
    for name, extra in (('host', ['--unsafe']), (target, ['--unsafe', '--target', target])):
        binary = scratch / f'{source.stem}-{name}'
        status, _, error = run([str(compiler), *extra, str(source), str(binary)], 600)
        if status != 0:
            results[name] = ('compile', error.decode(errors='replace').strip().splitlines()[:3])
            continue
        status, out, error = run([str(binary)], timeout)
        results[name] = (status, out, error)
    host, cross = results['host'], results[target]
    if host[0] == 'compile' or host[1] != expected:
        return 'host-only', source.name, ''
    if cross[0] == 'compile':
        return 'FAIL', source.name, 'compile: ' + ' | '.join(cross[1])
    if cross[:2] != host[:2]:
        detail = f'status {cross[0]} vs {host[0]}; stderr: ' + cross[2].decode(errors='replace').strip()[:200]
        return 'FAIL', source.name, detail
    return 'ok', source.name, ''


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--compiler', type=pathlib.Path, required=True)
    ap.add_argument('--target', required=True)
    ap.add_argument('-j', type=int, default=os.cpu_count())
    ap.add_argument('--timeout', type=int, default=300)
    ap.add_argument('tests', nargs='*')
    a = ap.parse_args()
    sources = [ROOT / t for t in a.tests] if a.tests else sorted(p for p in (ROOT / 'tests').glob('*.lsl') if p.with_suffix('.out').exists())
    counts = {}
    with tempfile.TemporaryDirectory(prefix='lsl-cross-') as scratch:
        with concurrent.futures.ThreadPoolExecutor(a.j) as pool:
            jobs = [pool.submit(check, a.compiler.resolve(), a.target, s, pathlib.Path(scratch), a.timeout) for s in sources]
            for job in jobs:
                verdict, name, detail = job.result()
                counts[verdict] = counts.get(verdict, 0) + 1
                if verdict != 'ok':
                    print(f'{verdict:9} {name} {detail}', flush=True)
    print(a.target, counts)
    return 1 if counts.get('FAIL') else 0


if __name__ == '__main__':
    sys.exit(main())
