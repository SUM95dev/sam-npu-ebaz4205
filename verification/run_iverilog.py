#!/usr/bin/env python3
"""Run shipped regressions plus continuous-stream/WSTRB cases; no Vivado needed."""
from pathlib import Path
import os, subprocess, tempfile, json, re, sys
root=Path(__file__).resolve().parents[1]
compiler=os.environ.get('IVERILOG','iverilog')
runtime=os.environ.get('VVP','vvp')
flags=['-B',os.environ['IVERILOG_BASE']] if os.environ.get('IVERILOG_BASE') else []
results=[]
with tempfile.TemporaryDirectory() as tmp:
    for tb in sorted((root/'sim').glob('tb_*.v'))+sorted((root/'verification/extra').glob('*.v')):
        top=re.search(r'\bmodule\s+(\w+)',tb.read_text()).group(1)
        exe=str(Path(tmp)/'test.vvp')
        c=subprocess.run([compiler,*flags,'-g2005','-s',top,'-o',exe,*map(str,sorted((root/'rtl').glob('*.v'))),str(tb)],capture_output=True,text=True)
        try:
            run=subprocess.run([runtime,exe],capture_output=True,text=True,timeout=15) if c.returncode==0 else c
            ok=c.returncode==0 and run.returncode==0 and re.search(r'^PASS',run.stdout,re.M) is not None and re.search(r'FAIL|MISMATCH',run.stdout) is None
            output=run.stdout+run.stderr
        except subprocess.TimeoutExpired:
            ok=False;output='TIMEOUT'
        results.append({'test':str(tb.relative_to(root)),'passed':ok,'output':output,'compiler_stderr':c.stderr})
        print(('PASS ' if ok else 'FAIL ')+str(tb.relative_to(root)),flush=True)
out=root/'verification/evidence/iverilog_results.json'
out.write_text(json.dumps(results,indent=2))
passed=sum(x['passed'] for x in results)
print(f'IVERILOG RESULT: {passed}/{len(results)}')
sys.exit(0 if passed==len(results) else 1)
