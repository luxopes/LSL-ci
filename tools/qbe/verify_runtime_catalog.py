#!/usr/bin/env python3
"""Build tracked native runtime/atomic catalog and compare unchanged fixtures."""
import argparse,hashlib,json,pathlib,subprocess,time
ROOT=pathlib.Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--frontend',type=pathlib.Path,required=True);p.add_argument('--backend',type=pathlib.Path,required=True);p.add_argument('--old-compiler',type=pathlib.Path,default=pathlib.Path.home()/'.local/bin/lslc');p.add_argument('--build-directory',type=pathlib.Path,required=True);args=p.parse_args();b=args.build_directory.resolve();b.mkdir(parents=True,exist_ok=True);frontend=args.frontend.resolve();backend=args.backend.resolve();old=args.old_compiler.resolve();runtime=ROOT/'build/qbe/runtime.o';report={'complete':False,'scope':'Tracked runtime leaf atomics and unchanged low-setup runtime controls; sequential old/new checks','source_sha256':{str(p.relative_to(ROOT)):sha(p) for p in [ROOT/'compiler/pure/qbe_emit.lsl',ROOT/'compiler/pure/thread_runtime_linux_x86_64.lsl']},'seed_frontend_sha256':sha(frontend),'backend_sha256':sha(backend),'old_compiler_sha256':sha(old),'seed_runtime_sha256':sha(runtime),'steps':[],'cases':[]}
 def save():(b/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
 def run(command,timeout=60):
  command=list(map(str,command));t=time.monotonic()
  try:
   a=subprocess.run(command,cwd=ROOT,capture_output=True,timeout=timeout);v={'command':command,'seconds':time.monotonic()-t,'returncode':a.returncode,'stdout':a.stdout.decode(errors='replace'),'stderr':a.stderr.decode(errors='replace'),'timed_out':False}
  except subprocess.TimeoutExpired as e:v={'command':command,'seconds':time.monotonic()-t,'returncode':None,'stdout':(e.stdout or b'').decode(errors='replace'),'stderr':(e.stderr or b'').decode(errors='replace'),'timed_out':True}
  return v
 dump=b/'runtime-dump';prefix=b/'runtime';compiler=b/'compiler'
 for command in [[frontend,'compiler/pure/qbe_runtime_dump.lsl',dump,backend],[dump,prefix],['python3','tools/qbe/runtime_object.py',prefix]]:
  a=run(command);report['steps'].append(a);save();assert a['returncode']==0,a
 runtime.write_bytes(prefix.with_suffix('.o').read_bytes());report['runtime_sha256']=sha(runtime);report['runtime_assembly_sha256']=sha(prefix.with_suffix('.s'))
 a=run([frontend,'compiler/pure/lslc_qbe.lsl',compiler,backend]);report['steps'].append(a);save();assert a['returncode']==0,a;report['compiler_sha256']=sha(compiler)
 names=['qbe/atomic_native','atomic_conformance','time_conformance','gc_raw_buffer_conformance','gc_stress_conformance','automatic_gc_threads_conformance','thread_conformance','thread_reuse_conformance','security_runtime_conformance']
 fixtures=b/'fixtures';fixtures.mkdir(exist_ok=True)
 for name in names:
  source=pathlib.Path('tests')/(name+'.lsl');expected=(ROOT/source).with_suffix('.out').read_text();row={'source':str(source),'source_sha256':sha(ROOT/source),'expected_stdout':expected};report['cases'].append(row)
  for kind,cc in [('candidate',compiler),('v089',old)]:
   out=b/(name.replace('/','-')+'-'+kind);row[kind]={'build':run([cc]+(["--unsafe"] if kind=='candidate' else [])+[source,out]+([backend] if kind=='candidate' else []))};v=row[kind]
   if v['build']['returncode']==0:
    v['binary_sha256']=sha(out);v['execution']=run([out]+([fixtures] if name=='security_runtime_conformance' else []),20);v['pass']=v['execution']['returncode']==0 and v['execution']['stdout']==expected
   else:v['pass']=False
  print(name,[(k,row[k]['pass']) for k in ['candidate','v089']],flush=True);save()
 report['complete']=True;report['all_pass']=all(row[k]['pass'] for row in report['cases'] for k in ['candidate','v089']);save()
if __name__=='__main__':main()
