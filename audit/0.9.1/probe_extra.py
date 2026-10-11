from pathlib import Path
import subprocess,json,time
root=Path(__file__).resolve().parents[2]
d=Path(__file__).parent
cases={'nan_comparisons': 'n = 0.0 / 0.0\nprint n == n, n != n, n < 1.0, n <= 1.0, n > 1.0, n >= 1.0\n', 'isclose_opposite_inf': 'load math\nprint math.is_close(1.0 / 0.0, -1.0 / 0.0, 1e-9, 0.0)\n', 'isclose_nan': 'load math\nprint math.is_close(0.0 / 0.0, 1.0, 1e-9, 0.0)\n', 'round_small_digits_min': 'load math\nprint math.round(0.015, -9223372036854775807 - 1)\n', 'float_abs_nan': 'n = 0.0 / 0.0\nprint abs(n), max(n, 0.0), min(n, 0.0)\n', 'loop_break_unassigned': 'for i in [1]:\n    break\n    x = 1\nend\nprint x\n', 'loop_continue_unassigned': 'for i in [1]:\n    continue\n    x = 1\nend\nprint x\n', 'global_retype': 'x = 1\nfunction f():\n    global x\n    x = "hi"\nend\ncall f()\nprint x, type(x)\n', 'global_partial': 'x = 1\nfunction f():\n    if False:\n        global x\n    end\n    x = 2\nend\ncall f()\nprint x\n', 'intarray_unpack': 'a = IntArray([1, 2])\nx, y = a\nprint x, y\n', 'float_roundtrip': 'x = 1.7976931348623157e308\nprint Float(String(x)) == x\n', 'json_roundtrip': 'load json\nx = 1.7976931348623157e308\nprint json.decode(json.encode(x)) == x\n', 'floor_large': 'load math\nprint math.floor(1e20)\n', 'ceil_large': 'load math\nprint math.ceil(1e20)\n', 'sin_large': 'load math\nprint math.sin(1e20)\n', 'sqrt_nan': 'print sqrt(0.0 / 0.0)\n', 'float_subnormal_parse': 'print Float("5e-324")\n', 'float_large_exponent_zero': 'print Float("0e999999999999999999999")\n'}
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
(d/'results_extra.json').write_text(json.dumps(results,indent=2))
