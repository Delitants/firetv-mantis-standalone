#!/usr/bin/env python3
"""Keep local planning and reports out of source pushes and release uploads."""
import argparse,fnmatch,json,pathlib,re,shutil,stat,subprocess,sys,tarfile,tempfile,zipfile
CONTROL='.github/publication/'
CONTROL_FILES={CONTROL+'guard.py',CONTROL+'install-hooks.py',CONTROL+'policy.json'}
PRIVATE_DIRS={'work','outputs','internal','reports','test-reports','evidence','acceptance','plans',
              'superpowers','.superpowers','.codex','.agents','.agent-artifacts','privatefixtures'}
PRIVATE_FILES={'release-info.json','release-evidence.json','host-matrix.json','development-evidence.json',
               'qualification-results.json','format-matrix.json','reference-actions.csv','reference-tools.csv',
               'results.json','test-results.xml','test-results.json','test-report.json','agents.md','claude.md','gemini.md'}
DOC_TYPES={'.md','.rst','.txt','.json','.csv','.pdf','.html','.xml'}
REPORT=re.compile(r'(?:^|[-_ .])(?:test[-_ ]?(?:reports?|results)|implementation[-_ ]?(?:plans?|notes)|planning|qualification|verification[-_ ]?report|development[-_ ]?(?:notes|evidence)|host[-_ ]?matrix)(?:[-_ .]|$)',re.I)
INTERNAL=re.compile(r'(?im)(?:/Users/[^\s/]+/|\b\d+\s+(?:(?:unit|integration|native)\s+)?tests?\s+(?:passed|failed|skipped)\b|^\s*(?:#+\s*)?(?:implementation plan|test results|test report|verification report|acceptance evidence|qualification results|post-signing checks|source commit|reviewed source|build log)\b)')
USER_DOCS={'readme.md','readme.txt','readme','install.md','install.txt','recovery.md','known-limits.md','changelog.md'}
PACKAGE_DATA={'package.json','package-lock.json','composer.json','composer.lock','tsconfig.json','Cargo.lock'}
CODE_TYPES={'.go','.c','.h','.cc','.cpp','.cxx','.hpp','.swift','.py','.sh','.js','.ts','.php','.rs','.java','.m','.mm','.lua','.pl','.rb','.erl','.ex','.sql','.s','.asm'}
MAX_TEXT=1048576

def private_error(name):
 p=pathlib.PurePosixPath(name)
 if not name or not p.parts or p.is_absolute() or '..' in p.parts or '\\' in name:return 'unsafe path'
 parts=[x.removeprefix('._').casefold() for x in p.parts]
 if any(x in PRIVATE_DIRS and not (x=='internal' and (p.suffix.casefold() in CODE_TYPES or parts[-1]=='openapi.json')) for x in parts):return 'local-only directory'
 if parts[-1] in PRIVATE_FILES or p.suffix.casefold()=='.log':return 'local-only report/log'
 if p.suffix.casefold() in DOC_TYPES|{'.zip','.gz','.xz','.tar','.tgz'} and REPORT.search(parts[-1]):return 'internal planning/report file'
 return None

def text_errors(name,text):
 return [name+': keep planning, test details and local paths out of public help/notes'] if INTERNAL.search(text) else []

def workflow_errors(name,text):
 errors=[]
 starts=list(re.finditer(r'(?m)^( +)- (?:name|uses|run|id|if):',text))
 for i,match in enumerate(starts):
  end=next((m.start() for m in starts[i+1:] if len(m[1])<=len(match[1])),len(text))
  step=text[match.start():end]
  if not re.search(r'uses:\s*[^\n]*upload-artifact@',step):continue
  visible='\n'.join(line for line in step.splitlines() if not line.strip().startswith('!'))
  private_paths=any(re.search(r"(?:^|[/\s:'\"])"+re.escape(part)+r'(?:/|$)',visible,re.I) for part in PRIVATE_DIRS)
  if private_paths or re.search(r'(?i)(?:evidence|coverage[-_ ]?report|(?:qa|test)[-_ /](?:results?|reports?|logs?)|work/qa|\.log\b|junit[^\n]*\.xml)',visible):
   errors.append(name+': internal QA/test reports must stay local')
 return errors

def git(repo,*args):return subprocess.check_output(['git','-C',str(repo),*args],stderr=subprocess.PIPE)

def exists_at(repo,revision,path):
 return subprocess.run(['git','-C',str(repo),'cat-file','-e',revision+':'+path],capture_output=True).returncode==0

def changed_errors(repo,policy,revision,index=False):
 base=policy['baseline']
 if index and subprocess.run(['git','-C',str(repo),'cat-file','-e',base+'^{commit}'],capture_output=True).returncode:
  base='HEAD' if subprocess.run(['git','-C',str(repo),'rev-parse','--verify','HEAD'],capture_output=True).returncode==0 else '4b825dc642cb6eb9a060e54bf8d69288fbee4904'
 command=('diff','--cached','--name-only','--diff-filter=ACMRT','-z',base) if index else ('diff-tree','--root','-m','--no-commit-id','--name-only','--diff-filter=ACMRT','-r','-z',revision)
 names=set(x.decode('utf-8') for x in git(repo,*command).split(b'\0') if x)
 errors=[]
 for name in sorted(names):
  if not index and not exists_at(repo,revision,name):continue
  error=private_error(name)
  if error:errors.append(name+': '+error);continue
  p=pathlib.PurePosixPath(name)
  if p.suffix.casefold() in DOC_TYPES and name not in CONTROL_FILES and p.name not in PACKAGE_DATA:
   allowed=policy.get('public_data',[])+policy.get('public_docs',[])
   known=exists_at(repo,base,name)
   standard=bool(re.fullmatch(r'(?:README|CHANGELOG|LICENSE|COPYING|NOTICE)(?:\.[A-Za-z0-9_-]+)?',p.name,re.I))
   if not known and not standard and not any(fnmatch.fnmatchcase(name,x) for x in allowed):
    errors.append(name+': new document/data path needs public-policy approval');continue
  if name.startswith('.github/workflows/') and p.suffix.casefold() in {'.yml','.yaml'}:
   errors+=workflow_errors(name,git(repo,'show',(':' if index else revision+':')+name).decode('utf-8'))
  if p.name.casefold() in USER_DOCS and p.suffix.casefold()!='.json':
   value=git(repo,'show',(':' if index else revision+':')+name)
   if len(value)>MAX_TEXT:errors.append(name+': help file exceeds size limit')
   else:errors+=text_errors(name,value.decode('utf-8'))
 return errors

def index_errors(repo,policy):return changed_errors(repo,policy,None,index=True)

def history_errors(repo,policy,revision):
 try:
  base=policy['baseline']
  if subprocess.run(['git','-C',str(repo),'merge-base','--is-ancestor',base,revision],capture_output=True).returncode:
   return ['Update/rebase from the protected public baseline before publishing.']
  errors=[]
  for commit in git(repo,'rev-list',revision,'^'+base).decode().splitlines():errors += [commit[:12]+' '+e for e in changed_errors(repo,policy,commit)]
  return errors
 except (OSError,ValueError,UnicodeError,subprocess.CalledProcessError) as e:return ['Cannot verify source: '+str(e)]

def archive_errors(path):
 errors=[]
 def entry(name,size,reader):
  error=private_error(name+'__directory__.c' if name.endswith('/') else name)
  if error:errors.append(name+': '+error)
  elif pathlib.PurePosixPath(name).name.casefold() in USER_DOCS and reader:
   if size>MAX_TEXT:errors.append(name+': help exceeds size limit')
   else:errors.extend(text_errors(name,reader().decode('utf-8')))
 try:
  if zipfile.is_zipfile(path):
   with zipfile.ZipFile(path) as z:
    for item in z.infolist():
     if stat.S_ISLNK(item.external_attr>>16):
      target=z.read(item).decode('utf-8')
      if private_error(target):errors.append(item.filename+': unsafe or private archive link')
     entry(item.filename,item.file_size,None if item.is_dir() else lambda i=item:z.read(i))
  elif tarfile.is_tarfile(path):
   with tarfile.open(path,'r:*') as tar:
    for item in tar:
     if item.issym() or item.islnk():
      error=private_error(item.linkname)
      if error:errors.append(item.name+': unsafe or private archive link')
     entry(item.name+'/' if item.isdir() else item.name,item.size,(lambda i=item:tar.extractfile(i).read(MAX_TEXT+1)) if item.isfile() else None)
  elif str(path).lower().endswith(('.zip','.tar','.tar.gz','.tgz','.tar.xz','.tar.bz2')):
   errors.append(str(path)+': unreadable archive')
 except (OSError,ValueError,UnicodeError,RuntimeError,zipfile.BadZipFile,tarfile.TarError) as e:errors.append(str(path)+': '+str(e))
 return errors

def release_errors(policy,tag,assets,notes=None):
 if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._+-]*',tag):return ['Unsafe release tag']
 version=tag[1:] if tag.startswith('v') else tag
 patterns=[p.replace('{version}',version) for p in policy.get('release_assets',[])]
 errors=[];seen=set()
 for value in assets:
  p=pathlib.Path(value);name=p.name
  if name in seen:errors.append('Duplicated release asset: '+name)
  seen.add(name)
  error=private_error(name)
  if error:errors.append(name+': '+error);continue
  if not any(fnmatch.fnmatchcase(name,pattern) for pattern in patterns):errors.append(name+': not an approved release asset');continue
  if p.is_symlink() or not p.is_file():errors.append(name+': missing/unsafe asset');continue
  errors+=archive_errors(p)
  if name.casefold() in USER_DOCS:
   if p.stat().st_size>MAX_TEXT:errors.append(name+': help exceeds size limit')
   else:errors+=text_errors(name,p.read_text(encoding='utf-8'))
 if notes:
  p=pathlib.Path(notes)
  if p.is_symlink() or not p.is_file() or p.stat().st_size>MAX_TEXT:errors.append('Missing/unsafe release notes')
  else:errors+=text_errors('Release notes',p.read_text(encoding='utf-8'))
 return errors

def upload_snapshot(repo,policy,tag,assets,notes):
 common=(pathlib.Path(repo)/git(repo,'rev-parse','--git-common-dir').decode().strip()).resolve()
 stage=pathlib.Path(tempfile.mkdtemp(prefix='publication-upload-',dir=common));paths=[]
 for asset in assets:
  destination=stage/pathlib.Path(asset).name
  if destination.exists():raise ValueError('Duplicate upload filename')
  shutil.copyfile(asset,destination,follow_symlinks=False);paths.append(destination)
 note=None
 if notes:
  note=stage/'upload-notes.txt';shutil.copyfile(notes,note,follow_symlinks=False)
 errors=release_errors(policy,tag,paths,note)
 if errors:raise ValueError('; '.join(errors))
 return paths,note

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--repository',type=pathlib.Path,default=pathlib.Path.cwd());p.add_argument('--policy',type=pathlib.Path)
 sub=p.add_subparsers(dest='command',required=True)
 sub.add_parser('index');h=sub.add_parser('history');h.add_argument('revision',nargs='?',default='HEAD')
 sub.add_parser('pre-push')
 for mode in ['release-files','upload']:
  r=sub.add_parser(mode);r.add_argument('--tag',required=True);r.add_argument('--asset',action='append',type=pathlib.Path,required=True);r.add_argument('--notes-file',type=pathlib.Path)
 args=p.parse_args();repo=args.repository.resolve()
 try:
  policy=json.loads((args.policy or repo/(CONTROL+'policy.json')).read_text())
  if args.command=='index':errors=index_errors(repo,policy)
  elif args.command=='history':errors=history_errors(repo,policy,args.revision)
  elif args.command=='pre-push':
   errors=[]
   for line in sys.stdin:
    fields=line.split()
    if len(fields)!=4:errors.append('Invalid pre-push input');continue
    if fields[1]=='0'*40:continue
    if not re.fullmatch('[0-9a-f]{40}',fields[1]):errors.append('Invalid push revision');continue
    errors+=history_errors(repo,policy,fields[1])
  else:
   errors=release_errors(policy,args.tag,args.asset,args.notes_file)
   if args.command=='upload':
    errors+=history_errors(repo,policy,'HEAD')
    if git(repo,'status','--porcelain').strip():errors.append('Upload requires a clean source checkout')
  if errors:
   for error in errors:print('Publication blocked: '+error,file=sys.stderr)
   return 1
  if args.command=='upload':
   # Preserve existing project signing/qualification gates; this checks the upload only.
   origin=git(repo,'remote','get-url','origin').decode().strip()
   identity=re.search(r'github\.com[:/]([^/]+/[^/]+?)(?:\.git)?$',origin,re.I)
   if not identity or identity[1].casefold()!=policy['repository'].casefold():raise ValueError('Upload repository identity differs')
   assets,notes=upload_snapshot(repo,policy,args.tag,args.asset,args.notes_file)
   release=json.loads(subprocess.check_output(['gh','api',f'repos/{policy["repository"]}/releases/tags/{args.tag}']))
   if text_errors('Release notes',release.get('body') or ''):raise ValueError('Existing release notes contain internal details')
   version=args.tag[1:] if args.tag.startswith('v') else args.tag
   patterns=[p.replace('{version}',version) for p in policy.get('release_assets',[])]
   for asset in release['assets']:
    if private_error(asset['name']) or not any(fnmatch.fnmatchcase(asset['name'],p) for p in patterns):raise ValueError('Existing release has an unapproved attachment; review it before upload')
   subprocess.run(['gh','release','upload',args.tag,*[str(x) for x in assets],'--repo',policy['repository']],check=True)
  return 0
 except (OSError,ValueError,UnicodeError,KeyError,TypeError,subprocess.CalledProcessError) as error:
  print('Publication blocked: '+str(error),file=sys.stderr);return 1

if __name__=='__main__':sys.exit(main())
