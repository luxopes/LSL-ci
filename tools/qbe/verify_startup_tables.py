#!/usr/bin/env python3
"""Compare startup table bootstrap and automatic GC against installed 0.8.9.

Build the candidate first with the native frontend and matching QBE backend:
  FRONTEND compiler/pure/lslc_qbe.lsl BUILD/compiler BACKEND
"""
import argparse, hashlib, json, pathlib, subprocess, time
import source_artifacts
ROOT = pathlib.Path(__file__).resolve().parents[2]
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler', type=pathlib.Path, required=True)
    p.add_argument('--backend', type=pathlib.Path, required=True)
    p.add_argument('--build-directory', type=pathlib.Path, required=True)
    p.add_argument('--old-compiler', type=pathlib.Path, default=pathlib.Path.home()/'.local/bin/lslc')
    args = p.parse_args()
    build = args.build_directory.resolve(); build.mkdir(parents=True, exist_ok=True)
    compiler = args.compiler.resolve(); backend = args.backend.resolve(); old = args.old_compiler.resolve()
    report = {'complete': False, 'compiler_sha256': sha(compiler), 'backend_sha256': sha(backend), 'old_compiler_sha256': sha(old), 'runtime_sha256': sha(ROOT/'build/qbe/runtime.o'), 'emitter_sha256': sha(ROOT/'compiler/pure/qbe_emit.lsl'), 'cases': []}
    def save():
        (build/'verification.json').write_text(json.dumps(report, indent=2)+'\n')
    def run(command):
        command = list(map(str, command)); start = time.monotonic()
        result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=25)
        return {'command': command, 'returncode': result.returncode, 'seconds': time.monotonic()-start, 'stdout': result.stdout.decode(errors='replace'), 'stderr': result.stderr.decode(errors='replace')}
    for name in ['table_growth_conformance', 'qbe/startup_tables', 'automatic_gc_conformance']:
        source = pathlib.Path('tests')/(name+'.lsl'); expected = (ROOT/source).with_suffix('.out').read_text()
        row = {'source': str(source), 'source_sha256': sha(ROOT/source), 'expected_stdout': expected}; report['cases'].append(row)
        for kind, cc in [('candidate', compiler), ('v089', old)]:
            output = build/(name.replace('/', '-')+'-'+kind)
            source_artifacts.clear(output)
            result = {'build': run([cc]+(['--unsafe'] if kind == 'candidate' else [])+[source, output]+([backend] if kind == 'candidate' else []))}; row[kind] = result
            if result['build']['returncode'] == 0:
                result['binary_sha256'] = sha(output); result['execution'] = run([output])
                result['pass'] = result['execution']['returncode'] == 0 and result['execution']['stdout'] == expected
                if kind == 'candidate' and name != 'automatic_gc_conformance':
                    ssa, _, provenance = source_artifacts.obtain(cc, backend, source, output)
                    row['diagnostic_artifacts'] = provenance
                    entry = ssa.read_text().split('export function l $lsl_entry(', 1)[1]
                    row['entry_bootstrap_calls'] = entry.count('call $rt_runtime_test_small_tables(')
                    row['bootstrap_before_literals'] = entry.index('call $rt_runtime_test_small_tables(') < entry.index('call $lsl_init_literals(')
            else:
                result['pass'] = False
        print(name, [row[k]['pass'] for k in ['candidate', 'v089']], flush=True); save()
    report['complete'] = True
    report['all_pass'] = all(row[k]['pass'] for row in report['cases'] for k in ['candidate', 'v089']) and all(row.get('entry_bootstrap_calls', 1) == 1 and row.get('bootstrap_before_literals', True) for row in report['cases'])
    save()
if __name__ == '__main__':
    main()
