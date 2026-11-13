import re, pathlib, json
files=list(pathlib.Path('rtl').glob('*.v'))+list(pathlib.Path('sim').glob('*.v'))
texts={p:p.read_text() for p in files}
mods={}

def match_bal(s,start,op='(',cl=')'):
 d=0
 for i in range(start,len(s)):
  if s[i]==op:d+=1
  elif s[i]==cl:
   d-=1
   if d==0:return i
 return -1

def split_top(s):
 out=[]; cur=[]; d=0
 for ch in s:
  if ch in '([{': d+=1
  elif ch in ')]}': d-=1
  if ch==',' and d==0:
   out.append(''.join(cur));cur=[]
  else:cur.append(ch)
 out.append(''.join(cur));return out

for p,s in texts.items():
 # simpler locate module and first port list after optional parameter block
 for m in re.finditer(r'\bmodule\s+([A-Za-z_]\w*)',s):
  name=m.group(1); pos=m.end()
  while pos<len(s) and s[pos].isspace():pos+=1
  if pos<len(s) and s[pos]=='#':
   pos=s.find('(',pos); end=match_bal(s,pos); pos=end+1
  while pos<len(s) and s[pos].isspace():pos+=1
  if pos>=len(s) or s[pos]!='(': continue
  end=match_bal(s,pos); hdr=s[pos+1:end]
  ports=[]; dirs={}
  current_dir=None
  for part in split_top(hdr):
   part=re.sub(r'//.*','',part).strip()
   dm=re.search(r'\b(input|output|inout)\b',part)
   if dm: current_dir=dm.group(1)
   # last identifier
   ids=re.findall(r'\b([A-Za-z_]\w*)\b',part)
   ignore={'input','output','inout','wire','reg','signed','integer','parameter','localparam'}
   ids=[x for x in ids if x not in ignore and not x.isdigit()]
   if ids:
    pname=ids[-1]; ports.append(pname); dirs[pname]=current_dir
  mods[name]={'ports':ports,'dirs':dirs,'file':str(p)}

issues=[]; insts=[]
for p,s in texts.items():
 # remove comments for easier scanning
 ss=re.sub(r'//.*','',s)
 for mod,info in mods.items():
  for m in re.finditer(r'\b'+re.escape(mod)+r'\b',ss):
   # skip declaration
   pre=ss[max(0,m.start()-20):m.start()]
   if re.search(r'\bmodule\s*$',pre): continue
   pos=m.end()
   while pos<len(ss) and ss[pos].isspace():pos+=1
   if pos<len(ss) and ss[pos]=='#':
    q=ss.find('(',pos); e=match_bal(ss,q)
    if e<0: continue
    pos=e+1
   while pos<len(ss) and ss[pos].isspace():pos+=1
   im=re.match(r'([A-Za-z_]\w*)',ss[pos:])
   if not im: continue
   iname=im.group(1); pos+=im.end()
   while pos<len(ss) and ss[pos].isspace():pos+=1
   if pos>=len(ss) or ss[pos]!='(': continue
   e=match_bal(ss,pos)
   if e<0: issues.append((str(p),iname,'unbalanced instance')); continue
   body=ss[pos+1:e]
   named=re.findall(r'\.([A-Za-z_]\w*)\s*\(',body)
   if not named: continue
   insts.append((str(p),mod,iname,named))
   unknown=[x for x in named if x not in info['ports']]
   missing=[x for x in info['ports'] if x not in named]
   if unknown: issues.append((str(p),iname,'unknown ports',unknown))
   # flag missing input ports only
   miss_in=[x for x in missing if info['dirs'].get(x)=='input']
   if miss_in: issues.append((str(p),iname,'missing input ports',miss_in))
print('modules',len(mods),'instances',len(insts),'issues',len(issues))
for x in issues:print(x)