from pathlib import Path
import subprocess,json,time
root=Path(__file__).resolve().parents[2];d=Path(__file__).resolve().parent
cases={
'config_control':'config = {"value": 1}\n',
'config_printr':'printr "UNEXPECTED-OUTPUT"\nconfig = {"value": 1}\n',
'config_monotonic':'config = {"stamp": monotonic()}\n',
'config_block_comment':'/* readfile("not-executed") */\nconfig = {"value": 1}\n',
'config_escaped_quote':'config = {"value": "a\\\"b"}\n',
'config_tab_export':'config\t= {"value": 1}\n',
'config_raw_backslash':'config = {"value": r"a\\"}\n',
'config_print_blocked':'print "blocked"\nconfig = {"value": 1}\n',
}
results={}
for name,s in cases.items():
 p=d/(name+'.lsl');p.write_text(s);t=time.monotonic()
 try:
  r=subprocess.run([str(root/'lsl'),'config',str(p)],cwd=root,text=True,capture_output=True,timeout=20)
  row={'rc':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'seconds':round(time.monotonic()-t,3)}
 except subprocess.TimeoutExpired as e:row={'timeout':True,'stdout':str(e.stdout),'stderr':str(e.stderr)}
 print(name,json.dumps(row),flush=True);results[name]=row
 (d/(name+'.stdout')).write_text(row['stdout']);(d/(name+'.stderr')).write_text(row['stderr'])
 (d/'results_config.json').write_text(json.dumps(results,indent=2))
