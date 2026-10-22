#!/usr/bin/env python3
"""Konformní testy na dalších cílech: každý tests/X.lsl s tests/X.out se
přeloží pro cíl i pro hostitele, spustí (cizí architektura přes qemu-user
binfmt, Windows přes wine, WebAssembly v Node s WASI, bare metal v qemu-system
se semihostingem, s --adb na připojeném zařízení Android) a výstup se
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
# cesty Linuxu (/proc, /dev/null; wine je zpřístupní, Windows ne), unixové
# nástroje (/bin/sh, true, sh v PATH) nebo curl.exe, který wine na rozdíl
# od Windows 10+ nemá.
WINDOWS_SKIP = {
    'automatic_gc_conformance.lsl': 'memory from /proc/self/status',
    'call_statement_conformance.lsl': 'writes /dev/null',
    'gc_bigheap_threads_conformance.lsl': 'Linux syscall (setitimer)',
    'gc_stream_worker_conformance.lsl': '/bin/sh',
    'language_safety_features.lsl': 'Unix command true',
    'module_group_conformance.lsl': 'Unix command sh',
    'process_fork_fault_conformance.lsl': 'Linux syscalls (geteuid, prlimit)',
    'requests_conformance.lsl': 'curl.exe (missing in wine)',
    'syscall6_conformance.lsl': 'Linux syscalls',
    'unixsock_fd_passing_conformance.lsl': 'no descriptor passing (SCM_RIGHTS)',
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

# macOS má POSIX nástroje i /dev/null; chybí syscally Linuxu a /proc.
MACOS_SKIP = {
    'automatic_gc_conformance.lsl': 'memory from /proc/self/status',
    'gc_bigheap_threads_conformance.lsl': 'Linux syscall (setitimer)',
    'process_fork_fault_conformance.lsl': 'Linux syscalls (geteuid, prlimit)',
    'syscall6_conformance.lsl': 'Linux syscalls',
    'x11_transport_conformance.lsl': 'Linux syscalls (socketpair)',
}

# WebAssembly s WASI preview1: bez procesů, socketů, /proc, /dev/null
# a nativního strojového kódu.
WASI_SKIP = {
    'automatic_gc_conformance.lsl': 'memory from /proc/self/status',
    'automatic_gc_threads_conformance.lsl': 'processes (run, capture)',
    'call_statement_conformance.lsl': 'writes /dev/null',
    'list_directory_conformance.lsl': 'directory listing (WASI preview1 fd_readdir not used)',
    'rename_conformance.lsl': 'rename (WASI path_rename not used)',
    'update_portable_conformance.lsl': 'self-update needs rename and processes',
    'update_portable_internal_conformance.lsl': 'self-update needs rename and processes',
    'gc_bigheap_threads_conformance.lsl': 'Linux syscall (setitimer)',
    'gc_stream_worker_conformance.lsl': '/bin/sh',
    'language_safety_features.lsl': 'processes (system)',
    'native_portable_conformance.lsl': 'native machine code',
    'plugin_timeout_conformance.lsl': 'processes (plugins)',
    'process_fork_fault_conformance.lsl': 'Linux syscalls (geteuid, prlimit)',
    'requests_conformance.lsl': 'sockets (HTTP server)',
    'syscall6_conformance.lsl': 'Linux syscalls',
    'unixsock_fd_passing_conformance.lsl': 'Unix sockets',
    'x11_transport_conformance.lsl': 'Linux syscalls (socketpair)',
}

# Bare metal: bez procesů, socketů, systémových volání a nativního kódu;
# /proc by četl stav qemu na hostiteli.
BAREMETAL_SKIP = {
    'automatic_gc_conformance.lsl': 'memory from /proc/self/status',
    'list_directory_conformance.lsl': 'no directories without an OS',
    'rename_conformance.lsl': 'no file system rename without an OS',
    'update_portable_conformance.lsl': 'no self-update without an OS',
    'update_portable_internal_conformance.lsl': 'no self-update without an OS',
    'automatic_gc_threads_conformance.lsl': 'processes (run, capture)',
    'gc_bigheap_threads_conformance.lsl': 'Linux syscall (setitimer)',
    'gc_stream_worker_conformance.lsl': '/bin/sh',
    'language_safety_features.lsl': 'processes (system)',
    'native_portable_conformance.lsl': 'native machine code',
    'plugin_timeout_conformance.lsl': 'processes (plugins)',
    'process_fork_fault_conformance.lsl': 'Linux syscalls (geteuid, prlimit)',
    'requests_conformance.lsl': 'sockets (HTTP server)',
    'syscall6_conformance.lsl': 'Linux syscalls',
    'unixsock_fd_passing_conformance.lsl': 'Unix sockets',
    'x11_transport_conformance.lsl': 'Linux syscalls (socketpair)',
}


# 32bitový Linux (přes C): nativní knihovny (vlastní zavaděč ELF64 a volací
# konvence 64bitových CPU) zatím nejsou.
LINUX32_SKIP = {
    'native_portable_conformance.lsl': 'native libraries are 64-bit only',
}


def skip_reason(target, name):
    """Důvod, proč test na cíli nemá smysl, nebo None."""
    if target in ('linux-arm', 'linux-x86'):
        return LINUX32_SKIP.get(name)
    if target.startswith('windows-'):
        return WINDOWS_SKIP.get(name)
    if target.startswith('macos-'):
        return MACOS_SKIP.get(name)
    if target.startswith('wasm32-'):
        return WASI_SKIP.get(name)
    if target.startswith('baremetal-'):
        return BAREMETAL_SKIP.get(name)
    return None


# Pod qemu-user (cizí architektura Linuxu bez --adb) chybí strict seccomp,
# runtime izolované nativní volání správně odmítne.
EMULATED_SKIP = {'native_portable_conformance.lsl': 'no seccomp in qemu-user'}


def check(compiler, target, source, scratch, timeout, adb=False):
    reason = skip_reason(target, source.name)
    if not reason and target in ('linux-arm64', 'linux-riscv64', 'linux-arm') and not adb:
        reason = EMULATED_SKIP.get(source.name)
    if reason:
        return 'skip', source.name, reason
    expected = source.with_suffix('.out').read_bytes()
    results = {}
    # tests/gnu: moduly glib, gio a gtk jen pro linux-x86_64-gnu; hostitelský
    # překlad (statický) by nespojil knihovny, porovnává se přímo s .out.
    gnu_only = source.parent.name == 'gnu'
    if gnu_only and target != 'linux-x86_64-gnu':
        return 'skip', source.name, 'needs linux-x86_64-gnu'
    builds = (('host', ['--unsafe']), (target, ['--unsafe', '--target', target]))
    if gnu_only:
        builds = builds[1:]
    for name, extra in builds:
        binary = scratch / f'{source.stem}-{name}'
        launcher = []
        if name.startswith('windows-'):
            binary = binary.with_name(binary.name + '.exe')
            launcher = ['wine']
        elif name.startswith('wasm32-'):
            binary = binary.with_name(binary.name + '.wasm')
            launcher = ['node', '--no-warnings', str(ROOT / 'tools/wasi_run.mjs')]
        elif name.startswith('baremetal-'):
            launcher = [sys.executable, str(ROOT / 'tools/baremetal_run.py')]
        status, _, error = run([str(compiler), *extra, str(source), str(binary)], 600)
        if status != 0:
            results[name] = ('compile', error.decode(errors='replace').strip().splitlines()[:3])
            continue
        if adb and name == target:
            status, out, error = run_adb(binary, timeout)
        else:
            status, out, error = run([*launcher, str(binary)], timeout)
        results[name] = (status, out, error)
    cross = results[target]
    if gnu_only:
        if cross[0] == 'compile':
            return 'FAIL', source.name, 'compile: ' + ' | '.join(cross[1])
        if cross[0] == 0 and cross[1].startswith(b'SKIP: '):
            return 'skip', source.name, cross[1][6:].decode(errors='replace').strip()
        if cross[0] != 0 or cross[1] != expected:
            return 'FAIL', source.name, f'status {cross[0]}; stderr: ' + cross[2].decode(errors='replace').strip()[:200]
        return 'ok', source.name, ''
    host = results['host']
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
    if not a.tests and a.target == 'linux-x86_64-gnu':
        sources += sorted(p for p in (ROOT / 'tests/gnu').glob('*.lsl') if p.with_suffix('.out').exists())
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
