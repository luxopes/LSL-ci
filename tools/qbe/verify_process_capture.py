#!/usr/bin/env python3
"""Compare native subprocess input/callback hooks with 0.8.9 and independent helpers."""
import argparse, hashlib, json, os, pathlib, signal, subprocess, time
ROOT = pathlib.Path(__file__).resolve().parents[2]
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--frontend',type=pathlib.Path,required=True);p.add_argument('--backend',type=pathlib.Path,required=True);p.add_argument('--build-directory',type=pathlib.Path,required=True);p.add_argument('--old-compiler',type=pathlib.Path,default=pathlib.Path.home()/'.local/bin/lslc');args=p.parse_args()
 b=args.build_directory.resolve();b.mkdir(parents=True,exist_ok=True);front=args.frontend.resolve();back=args.backend.resolve();old=args.old_compiler.resolve();compiler=b/'compiler'
 report={'complete':False,'scope':'Native existing runtime subprocess hooks, independent per-compiler children','frontend_sha256':sha(front),'backend_sha256':sha(back),'old_compiler_sha256':sha(old),'runtime_sha256':sha(ROOT/'build/qbe/runtime.o'),'emitter_sha256':sha(ROOT/'compiler/pure/qbe_emit.lsl'),'helpers':[],'cases':[]}
 def save():(b/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
 def run(command):
  command=list(map(str,command));start=time.monotonic()
  v=subprocess.Popen(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True);timed_out=False
  try:stdout,stderr=v.communicate(timeout=25)
  except subprocess.TimeoutExpired:
   timed_out=True;os.killpg(v.pid,signal.SIGKILL);stdout,stderr=v.communicate()
  return {'command':command,'seconds':time.monotonic()-start,'returncode':v.returncode,'stdout':stdout.decode(errors='replace'),'stderr':stderr.decode(errors='replace'),'timed_out':timed_out}
 report['compiler_build']=run([front,'compiler/pure/lslc_qbe.lsl',compiler,back]);save();assert report['compiler_build']['returncode']==0;report['compiler_sha256']=sha(compiler)
 providers=[('candidate',compiler),('v089',old)]
 for kind,cc in providers:
  fixtures=b/kind;fixtures.mkdir(exist_ok=True)
  for source,name in [('input_conformance','input-server'),('capture_stream_server','capture-stream-server'),('capture_result_server','capture-result-server')]:
   out=fixtures/name;src=pathlib.Path('tests')/(source+'.lsl');v={'provider':kind,'source':str(src),'source_sha256':sha(ROOT/src),'build':run([cc]+(["--unsafe"] if kind=='candidate' else [])+[src,out]+([back] if kind=='candidate' else []))};report['helpers'].append(v);save();assert v['build']['returncode']==0;v['binary_sha256']=sha(out)
 process_cases=['capture_input_conformance','capture_stream_conformance','capture_result_conformance','qbe/process_capture_variants']
 for name in process_cases+['slice_step_conformance','sequence_ops_conformance','qbe/string_contiguous_slice']:
  src=pathlib.Path('tests')/(name+'.lsl');expected=(ROOT/src).with_suffix('.out').read_text();row={'source':str(src),'source_sha256':sha(ROOT/src),'expected_stdout':expected};report['cases'].append(row)
  for kind,cc in providers:
   out=b/(name.replace('/','-')+'-'+kind);v={'build':run([cc]+(["--unsafe"] if kind=='candidate' else [])+[src,out]+([back] if kind=='candidate' else []))};row[kind]=v
   if v['build']['returncode']==0:
    v['binary_sha256']=sha(out);v['execution']=run([out]+([b/kind] if name in process_cases else []));v['pass']=v['execution']['returncode']==0 and v['execution']['stdout']==expected
   else:v['pass']=False
  print(name,[row[k]['pass'] for k in ['candidate','v089']],flush=True);save()
 report['complete']=True;report['all_pass']=all(row[k]['pass'] for row in report['cases'] for k in ['candidate','v089']);save()
if __name__=='__main__':main()
