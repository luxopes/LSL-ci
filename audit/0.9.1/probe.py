from pathlib import Path
import subprocess,json,time
root=Path(__file__).resolve().parents[2]
d=Path(__file__).parent
cases={
'alias_unpack':'a = [1, 2]\na[1], a[0] = a\nprint a\n',
'round_float_digits_max':'load math\nprint math.round(1.5, 9223372036854775807)\n',
'trunc_float_digits_max':'load math\nprint math.trunc(1.5, 9223372036854775807)\n',
'round_int_digits_min':'load math\nprint math.round(123, -9223372036854775807 - 1)\n',
'round_int_overflow':'load math\nprint math.round(5000000000000000000, -19)\n',
'trunc_int_min':'load math\nprint math.trunc(-9223372036854775807 - 1, -1)\n',
'exp_finite':'load math\nprint math.exp(709.5)\n',
'exp_subnormal':'load math\nprint math.exp(-710.0)\n',
'hypot_large':'load math\nprint math.hypot(1e200, 1e200)\n',
'hypot_small':'load math\nprint math.hypot(1e-200, 1e-200)\n',
'isclose_inf_finite':'load math\nprint math.is_close(1.0 / 0.0, 1.0, 1e-9, 0.0)\n',
'isclose_inf_self':'load math\nprint math.is_close(1.0 / 0.0, 1.0 / 0.0, 1e-9, 0.0)\n',
'gcd_min':'load math\nprint math.gcd(-9223372036854775807 - 1, 0)\n',
'lcm_overflow':'load math\nprint math.lcm(9223372036854775807, 2)\n',
'median_large':'load math\nprint math.median([1e308, 1e308])\n',
'mean_large':'load math\nprint math.mean([1e308, 1e308])\n',
'time_last_fraction':'load time\nprint time.iso8601(253402300799.5)\n',
'time_parse_range':'load time\nx = time.parse_iso8601("0001-01-01T00:00:00+01:00")\nprint x\nprint time.iso8601(x)\n',
'float_boundary':'print Float("0.49999999999999994") == 0.5\n',
}
results={}
for name,src in cases.items():
 p=d/(name+'.lsl');p.write_text(src);b=d/name
 t=time.monotonic()
 c=subprocess.run([str(root/'compiler/lslc'),'--unsafe',str(p),str(b),str(root/'compiler/pure/luxir')],cwd=root,capture_output=True,text=True,timeout=30)
 if c.returncode==0:
  r=subprocess.run([str(b)],cwd=root,capture_output=True,text=True,timeout=3)
 else:r=c
 results[name]={'compile_rc':c.returncode,'rc':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'seconds':round(time.monotonic()-t,3)}
 (d/(name+'.stdout')).write_text(r.stdout);(d/(name+'.stderr')).write_text(r.stderr)
 print(name,json.dumps(results[name]),flush=True)
(d/'results.json').write_text(json.dumps(results,indent=2))
