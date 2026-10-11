from pathlib import Path
import subprocess,json,time,resource
root=Path(__file__).resolve().parents[2]
d=Path(__file__).resolve().parent
build=root.parent/'verification/audit-091-more';build.mkdir(parents=True,exist_ok=True)
cases={
'bigint_zero_sign':'load bigint\nx = bigint.BigInt({"sign": 0, "digits": "5"})\nprint x.text(), x.is_zero(), x.absolute().text()\n',
'bigint_sign_float':'load bigint\nx = bigint.BigInt({"sign": 1.9, "digits": "5"})\nprint x.text()\n',
'bigint_zero_divisor':'load bigint\nx = bigint.BigInt({"sign": 1, "digits": "0"})\nprint x.text(), x.is_zero()\n',
'float_long_fraction':'print Float("1." + "0" * 400)\n',
'float_long_mantissa':'print Float("1" + "0" * 400 + "e-400")\n',
'json_long_float':'load json\nprint json.decode("1." + "0" * 400)\n',
'json_true_budget':'load json\nprint json.encode_value(True, 1, [4])\n',
'json_exact_limit':'load json\ns = "x" * 4194295\nprint len(json.encode([s, True]))\n',
'json_limit_control':'load json\ns = "x" * 4194294\nprint len(json.encode([s, False]))\n',
'lconf_encode_limit':'load lconf\ns = lconf.encode({"apt": ["x" * 1048577], "lux": [], "lsl": []})\nprint len(s)\nprint lconf.decode(s)\n',
'median_mutation':'load math\nx = [3, 1, 2]\nprint math.median(x)\nprint x\n',
'tensor_shape_alias':'load tensor\nshape = [2]\nx = tensor.from_values([10, 20], shape)\nshape[0] = 3\nprint x.size()\nprint x.get([2])\n',
'round_negative_zero':'load math\nx = math.trunc(-0.01, 1)\nprint 1.0 / x\n',
'list_append_self':'x = [1]\nx.append(x)\ncall gc()\nprint x[0], len(x)\n',
'global_delete':'x = 1\nfunction f():\n    global x\n    del(x)\nend\ncall f()\nprint x\n',
'global_for_target':'x = 0\nfunction f():\n    global x\n    for x in [1, 2]:\n        print x\n    end\nend\ncall f()\nprint x\n',
}
results={}
def limits():resource.setrlimit(resource.RLIMIT_AS,(4*1024**3,4*1024**3))
for name,src in cases.items():
 p=d/(name+'.lsl');p.write_text(src);b=build/name;t=time.monotonic()
 try:
  c=subprocess.run([str(root/'compiler/lslc'),'--unsafe',str(p),str(b),str(root/'compiler/pure/luxir')],cwd=root,capture_output=True,text=True,timeout=30,preexec_fn=limits)
  r=subprocess.run([str(b)],cwd=root,capture_output=True,text=True,timeout=20,preexec_fn=limits) if c.returncode==0 else c
  result={'compile_rc':c.returncode,'rc':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'seconds':round(time.monotonic()-t,3)}
 except subprocess.TimeoutExpired as e:
  result={'timeout':True,'stdout':str(e.stdout),'stderr':str(e.stderr),'seconds':round(time.monotonic()-t,3)}
 results[name]=result
 (d/(name+'.stdout')).write_text(result['stdout']);(d/(name+'.stderr')).write_text(result['stderr'])
 print(name,json.dumps(result),flush=True)
 (d/'results_more.json').write_text(json.dumps(results,indent=2))
