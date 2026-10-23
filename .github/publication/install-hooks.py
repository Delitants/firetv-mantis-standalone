#!/usr/bin/env python3
"""Install persistent publication hooks while retaining existing custom hooks."""
import json,os,pathlib,re,shlex,shutil,subprocess

def git(*args):return subprocess.check_output(['git',*args],text=True).strip()
def config(key):
 result=subprocess.run(['git','config','--get',key],capture_output=True,text=True)
 return result.stdout.strip() if result.returncode==0 else ''

root=pathlib.Path(git('rev-parse','--show-toplevel')).resolve()
control=pathlib.Path(__file__).resolve().parent
policy=json.loads((control/'policy.json').read_text())
origin=git('remote','get-url','origin')
match=re.search(r'github\.com[:/]([^/]+/[^/]+?)(?:\.git)?$',origin,re.I)
if not match or match[1].casefold()!=policy['repository'].casefold():raise SystemExit('Repository identity differs from publication policy')
common=pathlib.Path(git('rev-parse','--git-common-dir')).resolve();target=common/'publication-safety-hooks'
previous=config('core.hooksPath');global_hooks=config('publication.safeGlobalHooksPath')
if previous and pathlib.Path(previous).resolve()==target:
 state=json.loads((target/'state.json').read_text());previous=state['previous']
elif not previous or previous==global_hooks:previous=str(common/'hooks')
else:previous=str(pathlib.Path(previous).resolve())
target.mkdir(exist_ok=True)
for name in ['guard.py','policy.json']:shutil.copy2(control/name,target/name)
(target/'state.json').write_text(json.dumps({'previous':previous})+'\n')
runner='''import json,os,pathlib,subprocess,sys
cache=pathlib.Path(__file__).resolve().parent
root=pathlib.Path(subprocess.check_output(['git','rev-parse','--show-toplevel'],text=True).strip())
hook=sys.argv[1]
previous=pathlib.Path(json.loads((cache/'state.json').read_text())['previous'])/hook
if hook not in {'pre-commit','pre-push'}:
 if previous.is_file() and os.access(previous,os.X_OK):os.execv(str(previous),[str(previous),*sys.argv[2:]])
 sys.exit(0)
data=sys.stdin.buffer.read() if hook=='pre-push' else None
if previous.is_file() and os.access(previous,os.X_OK):
 result=subprocess.run([str(previous),*sys.argv[2:]],input=data)
 if result.returncode:sys.exit(result.returncode)
mode='index' if hook=='pre-commit' else 'pre-push'
sys.exit(subprocess.run([sys.executable,str(cache/'guard.py'),'--repository',str(root),'--policy',str(cache/'policy.json'),mode],input=data).returncode)
'''
(target/'dispatch.py').write_text(runner)
hooks=set('applypatch-msg pre-applypatch post-applypatch pre-commit pre-merge-commit prepare-commit-msg commit-msg post-commit pre-rebase post-checkout post-merge pre-push pre-receive update post-receive post-update reference-transaction push-to-checkout pre-auto-gc post-index-change fsmonitor-watchman sendemail-validate'.split())
if pathlib.Path(previous).is_dir():hooks.update(p.name for p in pathlib.Path(previous).iterdir() if p.is_file() and os.access(p,os.X_OK) and not p.name.endswith('.sample'))
for hook in hooks:
 path=target/hook
 path.write_text('#!/bin/sh\nexec python3 '+shlex.quote(str(target/'dispatch.py'))+' '+hook+' "$@"\n');path.chmod(0o755)
subprocess.run(['git','config','--local','core.hooksPath',str(target)],check=True)
print('Publication hooks installed; existing custom hooks retained.')
