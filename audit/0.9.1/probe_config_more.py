from pathlib import Path
import subprocess,json,time
root=Path(__file__).resolve().parents[2];d=Path(__file__).resolve().parent
cases={'config_float_option': 'load config\noptions = {"rate": config.option("Float", 1.5, "rate")}\nconfig = {}\n', 'config_float_explicit': 'load config\noptions = {"rate": config.required("Float", "rate")}\nconfig = {"rate": 1.5}\n', 'config_missing_sentinel': 'load config\noptions = {"data": config.required("Dictionary", "data")}\nconfig = {"data": {"__missing": True}}\n', 'config_list_omit': 'load config\nconfig = {"items": [1, config.mkIf(False, 2), 3]}\n', 'config_force_list': 'load config\nconfig = {"items": config.mkForce([1, 2])}\n'}
results={}
for name,s in cases.items():
 p=d/(name+'.lsl');p.write_text(s);t=time.monotonic()
 r=subprocess.run([str(root/'lsl'),'config',str(p)],cwd=root,text=True,capture_output=True,timeout=20)
 row={'rc':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'seconds':round(time.monotonic()-t,3)}
 print(name,json.dumps(row),flush=True);results[name]=row
 (d/(name+'.stdout')).write_text(row['stdout']);(d/(name+'.stderr')).write_text(row['stderr']);(d/'results_config_more.json').write_text(json.dumps(results,indent=2))
