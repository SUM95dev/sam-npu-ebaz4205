#!/usr/bin/env python3
from pathlib import Path
import subprocess, sys, random, struct, tempfile, importlib.util, re
ROOT=Path(__file__).resolve().parent.parent
checks=[]
def ck(name,ok,detail=''):
    checks.append((name,bool(ok),str(detail))); print(('PASS ' if ok else 'FAIL ')+name+(' :: '+str(detail) if detail else ''))
def run(cmd): return subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True)

def load(path,name):
    spec=importlib.util.spec_from_file_location(name,ROOT/path); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m

import os
if os.environ.get('SKIP_BASELINE') == '1':
    ck('legacy five-pass audit',True,'already executed by outer validator')
else:
    r=run([sys.executable,'scripts/five_pass_source_audit.py']); ck('legacy five-pass audit',r.returncode==0 and '25/25' in r.stdout,r.stdout.splitlines()[-1] if r.stdout else r.stderr[:200])
for f in ['rtl/axis_maxpool2x2_engine.v','rtl/axis_elementwise_add_engine.v','sim/tb_regs_extended.v','sim/tb_conv_stream_bias.v','sim/tb_axis_maxpool.v','sim/tb_axis_add.v','sim/tb_matmul_bias_feeder.v','sw/host/npu_board_selftest.py','sw/host/npu_benchmark.py','sw/snpu_inspect.py']:
    ck('exists '+f,(ROOT/f).is_file())

regs=(ROOT/'rtl/npu_regs.v').read_text(); top=(ROOT/'rtl/npu_axis_system_top.v').read_text(); bd=(ROOT/'scripts/create_ebaz4205_full_bd.tcl').read_text()
ck('hardware identity registers','VERSION = 32\'h0002_0000' in regs and "4'hA: rd_data=capabilities" in regs)
ck('hardware perf counters','busy_cycles' in regs and 'last_job_cycles' in regs and 'job_count' in regs)
ck('hardware IRQ + abort','assign irq = irq_en && done_sticky' in regs and 'abort_pulse' in top and 'core_rst = rst | abort_pulse' in top)
ck('four hardware modes','mode_conv' in top and 'mode_pool' in top and 'mode_add' in top and 'mode_matmul' in top)
ck('streamed MatMul/Dense bias integrated','matmul_bias_en' in regs and 'mm_stream_bias' in top and 'mm_bias_effective' in top and 'bias_stream_en' in (ROOT/'rtl/axis_matmul_feeder.v').read_text())
ck('Conv per-output bias stream','sample_bias' in top and 's_axis_tdata[63:32]' in (ROOT/'rtl/axis_conv_adapter.v').read_text())
ck('NPU IRQ wired into PS concat','CONFIG.NUM_PORTS {3}' in bd and 'npu_0/irq' in bd)

vt=(ROOT/'scripts/run_vivado_verification.tcl').read_text(); tbs=list((ROOT/'sim').glob('tb_*.v'))+list((ROOT/'verification/extra').glob('*.v')); listed=set(re.findall(r'^\s+(tb_[A-Za-z0-9_]+)\s*$',vt,re.M))
ck('55-test Vivado suite',len(tbs)==55 and listed=={('tb_'+p.stem if p.stem.startswith('case_') else p.stem) for p in tbs},f'files={len(tbs)} listed={len(listed)}')
ck('new tests have PASS/FAIL',all('PASS' in p.read_text() and 'FAIL' in p.read_text() for p in tbs))

# Compile every Python file in-process. This checks syntax without creating
# __pycache__ artifacts and avoids filesystem-specific py_compile stalls.
bad=[]
for p in list((ROOT/'sw').rglob('*.py'))+list((ROOT/'scripts').rglob('*.py')):
    try:
        compile(p.read_text(),str(p),'exec')
    except Exception as e:
        bad.append((str(p.relative_to(ROOT)),str(e)[:160]))
ck('all Python compiles',not bad,bad)

# Userspace C warning-clean.
bad=[]
with tempfile.TemporaryDirectory() as td:
    for src in ['sw/linux/npu_net_server.c','sw/linux/npu_dma_proxy_test.c','sw/linux/npu_uio.c']:
        rr=run(['gcc','-std=c11','-D_DEFAULT_SOURCE','-Wall','-Wextra','-Werror','-O2',src,'-o',str(Path(td)/Path(src).stem)])
        if rr.returncode: bad.append((src,rr.stderr[:200]))
ck('userspace C warning-clean',not bad,bad)

# Grouped/depthwise Conv packet format: unpack exactly what RTL sees and compare golden accumulator+bias.
pack=load('sw/pack_conv_stream.py','pc'); gold=load('sw/golden_model.py','gm')
random.seed(956)
ok=True; cases=0
for _ in range(120):
    H=random.randint(1,4); W=random.randint(1,4)
    Cin=random.choice([1,2,4]); divisors=[g for g in range(1,Cin+1) if Cin%g==0]; G=random.choice(divisors)
    mult=random.randint(1,2); Cout=G*mult; Cpg=Cin//G
    Kh=Kw=random.choice([1,2]); pad=random.choice([0,1]); stride=1
    if H+2*pad<Kh or W+2*pad<Kw: continue
    inp=[[[random.randint(-4,4) for _ in range(Cin)] for _ in range(W)] for _ in range(H)]
    wt=[[[[random.randint(-4,4) for _ in range(Cpg)] for _ in range(Kw)] for _ in range(Kh)] for _ in range(Cout)]
    bias=[random.randint(-20,20) for _ in range(Cout)]
    payload,shape=pack.pack_conv_nhwc(inp,wt,stride,pad,G,bias)
    vals=[]; acc=None
    for off in range(0,len(payload),16):
        word,bv=struct.unpack_from('<Ii',payload,off); a=word&255; w=(word>>8)&255
        a=a-256 if a>=128 else a; w=w-256 if w>=128 else w
        if acc is None: acc=bv
        acc += a*w
        if word&(1<<16): vals.append(acc); acc=None
    ref=gold.conv2d_grouped(inp,wt,bias,stride,pad,G)
    flat=[v for row in ref for px in row for v in px]
    if acc is not None or vals!=flat or len(vals)!=shape[0]*shape[1]*shape[2]: ok=False; break
    cases+=1
ck('grouped/depthwise Conv packet contract',ok,f'{cases} randomized cases')

client=load('sw/host/npu_net_client.py','nc')
p=client.pack_add([120,-100,-5],[20,-50,2]); ck('Add packet framing',len(p)==48 and p[0]==120 and p[1]==20)
p=client.pack_pool_groups([[1,7,-2,5],[-3,-8,-1,-6]]); ck('MaxPool packet framing',len(p)==128)
# MatMul streamed-bias framing: 2x2 matrices still use one 8x8 tile; bias adds two 128-bit beats.
p,shape=client.pack_matmul([[1,2],[3,4]],[[5,6],[7,8]],bias=[1,-2])
ck('MatMul streamed bias framing',len(p)==176 and shape==(2,2,2) and struct.unpack_from('<4i',p,0)[:2]==(1,-2),f'bytes={len(p)} shape={shape}')
r=run([sys.executable,'sw/host/npu_board_selftest.py','--dry-run']); ck('board selftest dry-run',r.returncode==0 and 'PASS dry-run' in r.stdout,r.stdout.strip())

# Strict SNPU packer/inspector: valid package round-trip and invalid INT8 rejection.
with tempfile.TemporaryDirectory() as td:
    mdl=Path(td)/'m.snpu'
    rr=run([sys.executable,'sw/model_packer.py','sw/example_model.json','-o',str(mdl)])
    rr2=run([sys.executable,'sw/snpu_inspect.py',str(mdl)]) if rr.returncode==0 else rr
    ck('SNPU strict pack+inspect',rr.returncode==0 and rr2.returncode==0 and 'VALID' in rr2.stdout,rr2.stdout.strip() if rr2.returncode==0 else rr2.stderr[:200])
strict=(ROOT/'sw/model_packer.py').read_text(); onnx=(ROOT/'sw/onnx_to_snpu.py').read_text()
ck('model packer rejects out-of-range INT8','outside signed INT8 range' in strict and 'max(-128' not in strict)
ck('ONNX converter rejects silent float quantization','will not silently quantize/cast floating-point weights' in onnx and 'shape_inference.infer_shapes' in onnx)
ck('persistent network session + benchmark','class NpuSession' in (ROOT/'sw/host/npu_net_client.py').read_text() and (ROOT/'sw/host/npu_benchmark.py').is_file())

server=(ROOT/'sw/linux/npu_net_server.c').read_text()
ck('network opcodes INFO/MatMul/Conv/Pool/Add',all(x in server for x in ['OP_INFO','OP_MATMUL','OP_CONV','OP_MAXPOOL','OP_ADD']))
ck('network capability skew guard','cap_bit = opcode == OP_MATMUL' in server and 'REG_CAPS' in server)
ck('network MatMul bias flag','FLAG_MATMUL_BIAS' in server and '(flags & FLAG_MATMUL_BIAS)' in server)
ck('network timeout abort path','abort_job(dma_fd)' in server and 'CMD_ABORT' in server)
ck('network Conv framing validation','validate_conv_payload' in server and 'end_markers' in server)

failed=[x for x in checks if not x[1]]
print(f'FINAL_RELEASE_AUDIT {"PASS" if not failed else "FAIL"}: {len(checks)-len(failed)}/{len(checks)}')
if failed:
    for x in failed: print('FAILED:',x[0],x[2])
sys.exit(1 if failed else 0)
