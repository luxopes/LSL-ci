#!/usr/bin/env python3
"""Konformní testy na dalších cílech: každý tests/X.lsl s tests/X.out se
přeloží pro cíl i pro hostitele, spustí (cizí architektura přes qemu-user
binfmt, Windows přes wine, s --adb na připojeném zařízení Android) a výstup se
porovná s výstupem hostitele a s X.out.

Test, který bez argumentů neprojde ani na hostiteli (potřebuje argumenty,
vstup nebo prostředí test_runneru), se hlásí zvlášť jako "host-only".

Použití: cross_targets.py --compiler LSLC --target linux-arm64|windows-x86_64 [--adb] [-j N] [TEST...]
"""
import argparse, concurrent.futures, os, pathlib, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
# Pracovní adresář testů na zařízení Android (adb shell smí spouštět odtud).
ADB_DIRECTORY = '/data/local/tmp/lsl-cross'


def run(command, timeout):
    try:
        r = subprocess.run(command, capture_output=True, timeout=timeout, cwd=ROOT, stdin=subprocess.DEVNULL, env=dict(os.environ, WINEDEBUG='-all'))
        return r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        return 'timeout', b'', b''


# Testy, které na Windows smysl nemají: surová systémová volání Linuxu,
# unixové nástroje (/bin/sh, true, sh v PATH) nebo curl.exe, který wine
# na rozdíl od Windows 10+ nemá.
WINDOWS_SKIP = {
    'gc_bigheap_threads_conformance.lsl': 'Linux syscall (setitimer)',
    'gc_stream_worker_conformance.lsl': '/bin/sh',
    'language_safety_features.lsl': 'Unix command true',
    'module_group_conformance.lsl': 'Unix command sh',
    'process_fork_fault_conformance.lsl': 'Linux syscalls (geteuid, prlimit)',
    'requests_conformance.lsl': 'curl.exe (missing in wine)',
    'syscall6_conformance.lsl': 'Linux syscalls',
    'x11_transport_conformance.lsl': 'Linux syscalls (socketpair)',
}


def run_adb(binary, timeout):
    """Spustí program na zařízení (adb shell vrací stdout, stderr i kód)."""
    remote = f'{ADB_DIRECTORY}/{binary.name}'
    status, _, error = run(['adb', 'push', str(binary), remote], 120)
    if status != 0:
        return 'adb', b'', error
    result = run(['adb', 'shell', f'cd {ADB_DIRECTORY} && chmod 700 {binary.name} && ./{binary.name}; status=$?; rm -f {binary.name}; exit $status'], timeout)
    return result


def check(compiler, target, source, scratch, timeout, adb=False):
    if target.startswith('windows-') and source.name in WINDOWS_SKIP:
        return 'skip', source.name, WINDOWS_SKIP[source.name]
    expected = source.with_suffix('.out').read_bytes()
    results = {}
    # Jako test_runner v režimu qbe: korpus používá i surové služby runtime.
    for name, extra in (('host', ['--unsafe']), (target, ['--unsafe', '--target', target])):
        binary = scratch / f'{source.stem}-{name}'
        launcher = []
        if name.startswith('windows-'):
            binary = binary.with_name(binary.name + '.exe')
            launcher = ['wine']
        status, _, error = run([str(compiler), *extra, str(source), str(binary)], 600)
        if status != 0:
            results[name] = ('compile', error.decode(errors='replace').strip().splitlines()[:3])
            continue
        if adb and name == target:
            status, out, error = run_adb(binary, timeout)
        else:
            status, out, error = run([*launcher, str(binary)], timeout)
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
    ap.add_argument('--adb', action='store_true', help='spouštět cíl na zařízení přes adb')
    ap.add_argument('tests', nargs='*')
    a = ap.parse_args()
    sources = [ROOT / t for t in a.tests] if a.tests else sorted(p for p in (ROOT / 'tests').glob('*.lsl') if p.with_suffix('.out').exists())
    counts = {}
    if a.adb:
        run(['adb', 'shell', f'mkdir -p {ADB_DIRECTORY}'], 60)
    with tempfile.TemporaryDirectory(prefix='lsl-cross-') as scratch:
        with concurrent.futures.ThreadPoolExecutor(a.j) as pool:
            jobs = [pool.submit(check, a.compiler.resolve(), a.target, s, pathlib.Path(scratch), a.timeout, a.adb) for s in sources]
            for job in jobs:
                verdict, name, detail = job.result()
                counts[verdict] = counts.get(verdict, 0) + 1
                if verdict != 'ok':
                    print(f'{verdict:9} {name} {detail}', flush=True)
    print(a.target, counts)
    return 1 if counts.get('FAIL') else 0


if __name__ == '__main__':
    sys.exit(main())
