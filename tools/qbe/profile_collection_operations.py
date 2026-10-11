#!/usr/bin/env python3
"""Count collection operations in isolated diagnostic runtime copies.

No diagnostic wall times are performance evidence. Baseline and candidate
runtime assembly must reproduce their supplied production object hashes.
"""
import argparse, hashlib, json, pathlib, subprocess, sys
import profile_float_allocations as counters
import source_artifacts
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]/'qbe_port'))
from compare_v089 import checksum
ROOT=pathlib.Path(__file__).resolve().parents[2]
SYMBOLS=('runtime_alloc','runtime_box_dynamic_int','runtime_dynamic_get',
 'runtime_dynamic_set','runtime_list_append','runtime_dict_get','runtime_dict_set',
 'runtime_add_any','runtime_sub_any','runtime_mul_any','runtime_gc',
 'runtime_type_code','runtime_unbox_dynamic_int','runtime_string_concat',
 'runtime_text_split_byte','rt_runtime_maybe_gc')
def digest(p): return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def run(cmd,cwd):
 p=subprocess.run(list(map(str,cmd)),cwd=cwd,capture_output=True,timeout=120)
 if p.returncode: raise RuntimeError(f'{cmd}: {p.returncode}: {p.stderr.decode(errors="replace")}')
 return p

def main():
 p=argparse.ArgumentParser(description=__doc__)
 for name in ('baseline-root','candidate-root','baseline','compiler','backend','baseline-runtime','candidate-runtime','baseline-assembly','candidate-assembly'):
  p.add_argument('--'+name,type=pathlib.Path,required=True)
 p.add_argument('--build-directory',type=pathlib.Path,default=ROOT/'build/qbe-collection-profile')
 p.add_argument('--iterations',type=int,default=10000)
 p.add_argument('--report',type=pathlib.Path,required=True)
 a=p.parse_args(); b=a.build_directory.resolve();b.mkdir(parents=True,exist_ok=True)
 if a.iterations<=0:p.error('iterations must be positive')
 report={'complete':False,'scope':'diagnostic call counts; instrumented timings excluded','iterations':a.iterations,'cases':[],'runtime':{}}
 counters.SYMBOLS=SYMBOLS
 for kind,assembly,obj in [('baseline',a.baseline_assembly,a.baseline_runtime),('candidate',a.candidate_assembly,a.candidate_runtime)]:
  check=b/f'{kind}-checked.o';run(['cc','-c',assembly.resolve(),'-o',check],ROOT)
  if digest(check)!=digest(obj):raise RuntimeError('runtime assembly/object hash mismatch: '+kind)
  report['runtime'][kind]={'object_sha256':digest(obj),'assembly_sha256':digest(assembly)}
  asm=b/f'{kind}-diagnostic.s';asm.write_text(counters.instrument_runtime(assembly));run(['cc','-c',asm,'-o',b/f'{kind}-diagnostic.o'],ROOT)
 for case in ('list_access','dictionary_access','string_split_join','allocation_gc'):
  row={'name':case,'expected_stdout':str(checksum(case,a.iterations))+'\n','samples':[]};report['cases'].append(row)
  for kind,compiler,cwd in [('baseline',a.baseline,a.baseline_root),('candidate',a.compiler,a.candidate_root)]:
   source=cwd/'tests/benchmarks/v089'/f'{case}.lsl';out=b/f'{case}-{kind}'
   source_artifacts.clear(out)
   run([compiler.resolve()]+(["--unsafe"] if kind=="candidate" else [])+[source.resolve(),out,a.backend.resolve()],cwd)
   _,program_assembly,provenance=source_artifacts.obtain(compiler,a.backend,source.resolve(),out,cwd)
   instrumented=b/f'{case}-{kind}-diagnostic.s';instrumented.write_text(counters.instrument_program(program_assembly))
   exe=b/f'{case}-{kind}-diagnostic';run(['cc','-nostdlib','-no-pie','-Wl,--build-id=none','-o',exe,instrumented,b/f'{kind}-diagnostic.o'],ROOT)
   result=run([exe,a.iterations],cwd)
   if result.stdout.decode()!=row['expected_stdout']:raise RuntimeError('checksum mismatch: '+case+' '+kind)
   counts={}
   for line in result.stderr.decode().splitlines():
    name,value=line.split();counts[name]=int(value,16)
   if set(counts)!=set(SYMBOLS):raise RuntimeError('incomplete counters')
   row['samples'].append({'kind':kind,'compiler_sha256':digest(compiler),'source_sha256':digest(source),'assembly_sha256':digest(program_assembly),'diagnostic_artifacts':provenance,'counts':counts,'stdout':result.stdout.decode()})
 report['complete']=True;a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n');print(a.report)
if __name__=='__main__':main()
