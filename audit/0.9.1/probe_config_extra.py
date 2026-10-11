from pathlib import Path
import subprocess,json,time
root=Path(__file__).resolve().parents[2];d=Path(__file__).resolve().parent
cases={
'config_options_control':'load config\noptions = {"port": config.required("Int", "required port")}\nconfig = {}\n',
'config_options_tab':'load config\noptions\t= {"port": config.required("Int", "required port")}\nconfig = {}\n',
'config_assertions_control':'assertions = [[False, "must fail"]]\nconfig = {}\n',
'config_assertions_tab':'assertions\t= [[False, "must fail"]]\nconfig = {}\n',
'config_options_comment':'# options = optional declarations\nconfig = {"value": 1}\n',
'config_cpu_count':'config = {"cpus": cpu_count()}\n',
}
results={}
for name,s in cases.items():
 p=d/(name+'.lsl');p.write_text(s);t=time.monotonic()
 r=subprocess.run([str(root/'lsl'),'config',str(p)],cwd=root,text=True,capture_output=True,timeout=20)
 row={'rc':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'seconds':round(time.monotonic()-t,3)}
 print(name,json.dumps(row),flush=True);results[name]=row
 (d/(name+'.stdout')).write_text(row['stdout']);(d/(name+'.stderr')).write_text(row['stderr']);(d/'results_config_extra.json').write_text(json.dumps(results,indent=2))
