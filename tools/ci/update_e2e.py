#!/usr/bin/env python3
"""End-to-end self-update (Windows, macOS) proti produkčnímu kanálu
stable-v2.json: instalace vývojového balíku (verze vyšší než vydaná),
lsl update --check, odmítnutí downgradu, skutečný přechod na vydanou verzi
(stažení, podpis, SHA-256, rozbalení, instalace, výměna) a --rollback zpět.

Krok "rollback" spouští updater vývojové verze z prefixu (vydaná verze ho
ještě nemá); vrací vývojovou verzi uloženou v lib/lsl-updates/previous.

Vydanou verzi čte z kanálu. Je-li stejná jako vývojová (po vydání), ověří
jen hlášení "is up to date".

Použití: update_e2e.py PACKAGE
  LSL_E2E_WINE=1 spustí Windows balík ve wine (lokální kontrola na Linuxu;
  wine nemá curl.exe ani tar.exe, takže projde jen část bez sítě).
"""
import json, os, pathlib, shutil, subprocess, sys, tempfile, urllib.request

package = pathlib.Path(sys.argv[1]).resolve()
request = urllib.request.Request('https://lsl.lux-ai.cz/updates/channels/stable-v2.json', headers={'User-Agent': 'lsl-ci'})
release = json.load(urllib.request.urlopen(request, timeout=60))['version']
wine = bool(os.environ.get('LSL_E2E_WINE'))
windows = os.name == 'nt' or wine
exe = '.exe' if windows else ''
runner = ['wine'] if wine else []
environment = dict(os.environ)
if wine:
    environment['WINEDEBUG'] = '-all'


def native(path):
    return 'Z:' + str(path) if wine else str(path)


def run(arguments, success=True, contains=None, cwd=None):
    result = subprocess.run(runner + [str(argument) for argument in arguments], capture_output=True, timeout=1800, env=environment, stdin=subprocess.DEVNULL, cwd=cwd)
    output = (result.stdout + result.stderr).decode(errors='replace').replace('\r', '')
    print('$', ' '.join(str(argument) for argument in arguments), '->', result.returncode, flush=True)
    print('  ' + output.strip().replace('\n', '\n  ')[:3000], flush=True)
    if (result.returncode == 0) != success:
        raise SystemExit('FAIL    unexpected exit status %d' % result.returncode)
    if contains is not None and contains not in output:
        raise SystemExit('FAIL    output lacks: ' + contains)
    return output


work = pathlib.Path(tempfile.mkdtemp(prefix='lsl-update-e2e-'))
prefix = work / 'prefix'
lsl = prefix / 'bin' / ('lsl' + exe)
store = prefix / 'lib' / 'lsl-updates'
development = run([package / 'bin' / ('lsl' + exe), 'version']).strip()
print('development version', development, 'release', release, flush=True)
run([package / 'bin' / ('lsl-install' + exe), native(prefix)], contains='installed LSL')
if not (prefix / 'lib' / 'lsl' / 'INSTALLATION').exists():
    raise SystemExit('FAIL    lsl-install did not write the installation marker')
run([lsl, 'update', '--system'], success=False, contains='--system is only for Linux')
run([lsl, 'update', '--rollback'], success=False, contains='no previous LSL version is retained')
if development == release:
    run([lsl, 'update', '--check'], contains='LSL %s is up to date.' % release)
    run([lsl, 'update'], contains='LSL %s is up to date.' % release)
    print('update e2e: ok (development version equals the release)', flush=True)
    raise SystemExit(0)
run([lsl, 'update', '--check', '--allow-downgrade'], contains='LSL %s is available (installed %s)' % (release, development))
run([lsl, 'update'], success=False, contains='release downgrade refused')
# Rozbalený balík (bez značky instalace) se neaktualizuje.
run([package / 'bin' / ('lsl' + exe), 'update', '--allow-downgrade'], success=False, contains='installations made by lsl-install')
run([lsl, 'update', '--allow-downgrade'], contains='Updated LSL %s -> %s' % (development, release))
run([lsl, 'version'], contains=release)
if not (store / 'previous' / 'bin' / ('lsl' + exe)).exists():
    raise SystemExit('FAIL    previous version is not retained')
leftovers = sorted(name for name in os.listdir(store) if name != 'previous')
if leftovers:
    raise SystemExit('FAIL    update left files in the store: %s' % leftovers)
program = work / 'hello.lsl'
program.write_text('print "update ok", 6 * 7\n')
run([lsl, native(program)], contains='update ok 42')
# Vydaná verze updater ještě nemá: vývojový lsl na její místo (jen bin/lsl).
shutil.copy2(package / 'bin' / ('lsl' + exe), lsl)
run([lsl, 'update', '--rollback'], contains='Rolled back to LSL ' + development)
run([lsl, 'version'], contains=development)
run([lsl, native(program)], contains='update ok 42')
if (store / 'previous' / 'version').read_text().strip() != development:
    # Rollback uloží aktivní verzi pod štítkem běžícího lsl (zde vývojový).
    print('previous label', (store / 'previous' / 'version').read_text().strip(), flush=True)
leftovers = sorted(name for name in os.listdir(store) if name != 'previous')
if leftovers:
    raise SystemExit('FAIL    rollback left files in the store: %s' % leftovers)
print('update e2e: ok', flush=True)
