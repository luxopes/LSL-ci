#!/usr/bin/env python3
"""Fetch pinned backend/manual sources and export offline manuals for a build."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]

def git(*args, cwd=None):
    return subprocess.check_output(['git', *map(str,args)], cwd=cwd, text=True).strip()

def checkout(spec, supplied=None):
    destination = ROOT / spec['directory']
    if supplied:
        source = supplied.resolve()
        git('cat-file','-e',spec['commit']+'^{commit}',cwd=source)
        if destination.exists() and destination.resolve() != source:
            if git('rev-parse','HEAD',cwd=destination) != spec['commit']:
                raise RuntimeError('existing dependency differs; preserve it and choose a clean checkout')
            if git('status','--porcelain','--untracked-files=no',cwd=destination):
                raise RuntimeError('existing dependency has modified files')
            return destination
        if not destination.exists():
            destination.parent.mkdir(parents=True,exist_ok=True)
            subprocess.run(['git','clone','--no-hardlinks',str(source),str(destination)],check=True)
        subprocess.run(['git','checkout','--detach',spec['commit']],cwd=destination,check=True)
        return destination
    if not destination.exists():
        destination.parent.mkdir(parents=True,exist_ok=True)
        subprocess.run(['git','clone',spec['repository'],str(destination)],check=True)
    if git('status','--porcelain','--untracked-files=no',cwd=destination):
        raise RuntimeError('dependency has local changes: '+str(destination))
    if git('rev-parse','HEAD',cwd=destination) != spec['commit']:
        subprocess.run(['git','fetch','origin',spec['commit']],cwd=destination,check=True)
        subprocess.run(['git','checkout','--detach',spec['commit']],cwd=destination,check=True)
    return destination

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--luxir-checkout',type=Path)
    parser.add_argument('--web-checkout',type=Path)
    args=parser.parse_args()
    lock=json.loads((ROOT/'release.json').read_text())
    backend=checkout(lock['backend'],args.luxir_checkout)
    web=checkout(lock['manual'],args.web_checkout)
    export=ROOT/'build/manual-source'
    export.mkdir(parents=True,exist_ok=True)
    files={}
    for source in sorted((web/lock['manual']['path']).glob('*.md')):
        files[source.name]=hashlib.sha256(source.read_bytes()).hexdigest()
        shutil.copy2(source,export/source.name)
    for old in export.glob('*.md'):
        if old.name not in files: old.unlink()
    provenance={k:lock['manual'][k] for k in ['repository','commit','path']}
    provenance['files']=files
    (export/'SOURCE.json').write_text(json.dumps(provenance,indent=2)+'\n')
    public=ROOT/'docs/developer_guides'
    if public.is_symlink():
        if public.resolve()!=export.resolve(): raise RuntimeError('manual symlink points to a different source')
    elif public.exists():
        # Offline source archives include the generated manual snapshot.
        current=json.loads((public/'SOURCE.json').read_text())
        if current!=provenance: raise RuntimeError('manual snapshot differs from the pinned web source')
    else: public.symlink_to('../build/manual-source',target_is_directory=True)
    native=ROOT/'build/luxir/luxir'; native.parent.mkdir(parents=True,exist_ok=True)
    if not native.exists(): native.symlink_to('../../compiler/pure/luxir')
    compat=ROOT/'build/qbe/runtime.o';compat.parent.mkdir(parents=True,exist_ok=True)
    if not compat.exists():compat.symlink_to('../../compiler/qbe/runtime.o')
    print('Pinned LuxIR:',lock['backend']['commit'])
    print('Pinned web/manual:',lock['manual']['commit'],'pages:',len(files))
    return 0

if __name__=='__main__':raise SystemExit(main())
