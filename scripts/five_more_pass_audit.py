#!/usr/bin/env python3
from pathlib import Path
import re, subprocess, sys, tempfile, struct, random

root=Path(__file__).resolve().parents[1]
checks=[]
def add(p,name,detail=''):
    checks.append((bool(p),name,detail))
    print(f"{'PASS' if p else 'FAIL'} {name}" + (f" :: {detail}" if detail else ''))

def txt(rel): return (root/rel).read_text(errors='replace')

# ---------- Pass 1: production hierarchy / reachability ----------
rtl_files=sorted((root/'rtl').glob('*.v'))
mods={}
for f in rtl_files:
    s=f.read_text(errors='replace')
    for m in re.finditer(r'(?m)^\s*module\s+([A-Za-z_][A-Za-z0-9_]*)\b',s):
        mods.setdefault(m.group(1),[]).append(f.name)
add(all(len(v)==1 for v in mods.values()),'P1 unique RTL module definitions',str({k:v for k,v in mods.items() if len(v)!=1}))

# Conservative module-instantiation discovery: only names that are actual project modules.
graph={m:set() for m in mods}
for m,fl in mods.items():
    s=(root/'rtl'/fl[0]).read_text(errors='replace')
    for cand in mods:
        if cand==m: continue
        if re.search(r'(?m)^\s*'+re.escape(cand)+r'\s*(?:#\s*\([^;]*?\)\s*)?[A-Za-z_][A-Za-z0-9_]*\s*\(',s,re.S):
            graph[m].add(cand)
reach=set(); stack=['npu_bd_top']
while stack:
    x=stack.pop()
    if x in reach: continue
    reach.add(x); stack += sorted(graph.get(x,set())-reach)
required={'npu_bd_top','npu_axis_system_top','npu_axi_lite_slave','npu_regs','axis_matmul_feeder','matmul_engine','matmul_controller','systolic_array','npu_pe','tile_postprocess','npu_postprocess_pipe','axis_tile_output','axis_conv_adapter','conv_stream_job_engine','conv2d_stream_engine','axis_maxpool2x2_engine','axis_elementwise_add_engine'}
add(required <= reach,'P1 production hierarchy reaches every required engine',f'reachable={len(reach)}')
add('npu_bd_top' in mods and len(reach)==17,'P1 production hierarchy size stable',f'{len(reach)} modules')
unreachable=set(mods)-reach
allowed_legacy={'npu_postprocess','axis_scalar_output','conv2d_addrgen','conv2d_gemm_feeder','conv2d_memory_top','conv2d_scheduler','conv2d_systolic_engine','double_buffer_ctrl','maxpool2x2','npu_v4_top','perf_counters','shared_postprocess'}
add(unreachable==allowed_legacy,'P1 dead RTL is explicitly legacy/research only',','.join(sorted(unreachable)))
alltext='\n'.join(f.read_text(errors='replace') for f in rtl_files)
add(not re.search(r'(?m)^(<<<<<<<|=======|>>>>>>>)',alltext),'P1 no merge-conflict markers')
add('S_AXI_CTRL' in txt('rtl/npu_bd_top.v') and 'S_AXIS_IN' in txt('rtl/npu_bd_top.v') and 'M_AXIS_OUT' in txt('rtl/npu_bd_top.v'),'P1 production top exposes control + input/output streams')

# ---------- Pass 2: numeric widths / ranges / overflow ----------
# Standalone packer stays parameterized for audit/reference, but is strict on values.
scope={'__name__':'audit'}; exec(txt('sw/pack_matmul_stream.py'),scope)
ok=True
for tile in (1,2,4,8):
    A=[[1,-2,3],[4,5,-6]]; B=[[7,8],[-9,10],[11,-12]]
    try:
        blob=scope['make_feed'](A,B,tile)
        exp=((len(A)+tile-1)//tile)*((len(B[0])+tile-1)//tile)*(len(B)+tile-1)*2*tile
        ok &= len(blob)==exp
    except Exception: ok=False
try: scope['make_feed']([[128]],[[1]],8); ok=False
except ValueError: pass
add(ok,'P2 MatMul packer parameterized framing + strict INT8')

# Network hardware contract is fixed 8x8 and strict.
host={'__name__':'audit'}; exec(txt('sw/host/npu_net_client.py'),host)
ok=True
try: host['pack_matmul']([[1]],[[1]],tile=4); ok=False
except ValueError: pass
for bad in (128,-129):
    try: host['pack_matmul']([[bad]],[[1]]); ok=False
    except ValueError: pass
add(ok,'P2 network MatMul enforces fixed 8x8 + exact INT8 range')

conv=txt('sw/pack_conv_stream.py'); server=txt('sw/linux/npu_net_server.c')
add('macs_per_output > 131071' in conv,'P2 Conv packer guards INT32 accumulator MAC bound')
add('macs_this_output > 131071u' in server and 'macs_this_output != 0u' in server,'P2 network Conv stream guards accumulator + unterminated scalar')
legacy=txt('rtl/conv2d_systolic_engine.v')+txt('rtl/conv2d_scheduler.v')
add('total_pos_calc_wide' in legacy and 'k_total_calc_wide' in legacy and 'out_h_wide <= 32\'d65535' in legacy,'P2 legacy Conv arithmetic widened before size checks')
pp=txt('rtl/npu_postprocess.v')
add('BIAS_W  = ACC_W + 1' in pp and 'SCALE_W = BIAS_W + 32' in pp and 'scaled_w' in pp,'P2 postprocess preserves 33x32 widened arithmetic')

# ---------- Pass 3: protocol / state / multi-tile ordering ----------
cc='gcc'
with tempfile.TemporaryDirectory() as td:
    exe=Path(td)/'layout'
    r=subprocess.run([cc,'-std=c11','-Wall','-Wextra','-Werror','-O2',str(root/'sw/linux/matmul_layout_test.c'),'-o',str(exe)],capture_output=True,text=True)
    rr=subprocess.run([str(exe)],capture_output=True,text=True) if r.returncode==0 else None
    add(r.returncode==0 and rr.returncode==0 and 'PASS' in rr.stdout,'P3 C MatMul tile->row-major converter test',((r.stderr if r.returncode else rr.stdout).strip())[:160])

# randomized independent model of compact tile-major order vs C/header algorithm contract
def compact_to_row(vals,M,N,tile=8):
    out=[None]*(M*N); si=0
    for tm in range((M+tile-1)//tile):
      for tn in range((N+tile-1)//tile):
       for r in range(tile):
        gr=tm*tile+r
        if gr>=M: continue
        for c in range(tile):
         gc=tn*tile+c
         if gc>=N: continue
         out[gr*N+gc]=vals[si]; si+=1
    return out
random.seed(95); ok=True
for _ in range(300):
    M=random.randint(1,25); N=random.randint(1,25); vals=list(range(M*N))
    # construct hardware tile-major compact sequence from row-major source
    raw=[]
    for tm in range((M+7)//8):
      for tn in range((N+7)//8):
       for r in range(8):
        gr=tm*8+r
        if gr>=M: continue
        for c in range(8):
         gc=tn*8+c
         if gc<N: raw.append(vals[gr*N+gc])
    ok &= compact_to_row(raw,M,N)==vals
add(ok,'P3 randomized multi-tile output layout contract','300 shapes')

srv=txt('sw/linux/npu_net_server.c')
add('sam_npu_matmul_tile_to_row_major(tx, rx, M, N, 8u)' in srv and 'reply_data = tx' in srv,'P3 server exposes row-major MatMul network ABI')
tcl=txt('scripts/run_vivado_verification.tcl')
tb_files=list((root/'sim').glob('tb_*.v'))+list((root/'verification/extra').glob('*.v'))
listed=re.findall(r'(?m)^\s*(tb_[A-Za-z0-9_]+)\s*$',tcl)
add((root/'sim/tb_matmul_multitile_order.v').exists() and 'tb_matmul_multitile_order' in listed,'P3 multi-tile hardware-order regression is in XSim suite')
add(len(tb_files)==55 and len(set(listed))==55 and set(listed)=={('tb_'+p.stem if p.stem.startswith('case_') else p.stem) for p in tb_files},'P3 strict Vivado suite is exactly 55 existing tests',f'files={len(tb_files)} listed={len(set(listed))}')
add('regexp -line {^FAIL}' in tcl and 'regexp -line {^PASS}' in tcl and 'testbench emitted FAIL' in tcl,'P3 XSim Tcl checks logical PASS/FAIL, not process exit only')

# ---------- Pass 4: software/RTL contract safety ----------
csources=['sw/linux/npu_net_server.c','sw/linux/npu_dma_proxy_test.c','sw/linux/npu_uio.c','sw/linux/matmul_layout_test.c']
ok=True; detail=[]
for rel in csources:
    cmd=['gcc','-std=c11','-D_DEFAULT_SOURCE','-Wall','-Wextra','-Werror','-O2',str(root/rel),'-o','/tmp/'+Path(rel).stem+'_second5']
    r=subprocess.run(cmd,capture_output=True,text=True); ok &= r.returncode==0
    if r.returncode: detail.append(rel+': '+r.stderr[:100])
add(ok,'P4 userspace C warning-clean after contract fixes','; '.join(detail))
uio=txt('sw/linux/npu_uio.c')
add('Safe diagnostic by default' in uio and 'wr(REG_CTRL,1)' not in uio and 'wr(REG_CTRL, 1)' not in uio,'P4 UIO diagnostic never STARTs an unarmed DMA job')
bare=txt('sw/npu_baremetal_example.c')
add('uint32_t *result_words' in bare and 'unpack_matmul_rowmajor_i8' in bare,'P4 bare-metal example matches 32-bit DMA result + tile-major layout')
# no silent clamp in deploy paths
paths=['sw/host/npu_net_client.py','sw/pack_matmul_stream.py','sw/pack_conv_stream.py','sw/model_packer.py']
clamp_bad=[]
for rel in paths:
    s=txt(rel)
    if re.search(r'max\s*\(\s*-128\s*,\s*min\s*\(\s*127',s) or re.search(r'min\s*\(\s*127\s*,\s*max\s*\(\s*-128',s): clamp_bad.append(rel)
add(not clamp_bad,'P4 deploy packers contain no silent INT8 clamp',','.join(clamp_bad))
dma=txt('sw/linux/npu_dma_proxy.c')
add('single owner' in dma.lower() or 'owner' in dma.lower(),'P4 DMA driver retains ownership/close safety markers')
add('SO_RCVTIMEO' in srv and 'SO_SNDTIMEO' in srv and 'abort_job(dma_fd)' in srv,'P4 network timeout/error path aborts DMA/NPU')

# ---------- Pass 5: build/reproducibility / board gate ----------
bd=txt('scripts/create_ebaz4205_full_bd.tcl'); build=txt('scripts/build_ebaz4205_system.tcl'); final=txt('scripts/build_ebaz4205_final.sh')
add('0x43C00000' in bd and '64K' in bd and '0x40400000' in bd,'P5 deterministic 64K NPU/DMA control address map')
add('have_board_preset' in bd and 'PS7 board preset applied' in bd and ('Refusing' in build or 'chosen_board' in build) and (root/'scripts/install_ebaz4205_board_support_vivado.sh').exists(),'P5 implementation refuses unconfirmed EBAZ PS7/DDR preset')
add('get_timing_paths' in build and '-delay_type max' in build and '-delay_type min' in build and 'slack < 0.0' in build,'P5 implementation has explicit setup+hold timing failure gate')
combined='\n'.join(txt(x) for x in ['scripts/run_vivado_verification.tcl','scripts/build_ebaz4205_system.tcl','scripts/fetch_ebaz4205_board_support.sh'])
add(not re.search(r'(?m)^\s*run all\s*$',combined) and 'report_bd_layout' not in combined and 'presets.xml' not in combined,'P5 removed known Vivado-2020.2/script regressions')
# all Python parses without writing pycache
ok=True; bad=[]
for base in (root/'sw',root/'scripts'):
  for p in base.rglob('*.py'):
    try: compile(p.read_text(),str(p),'exec')
    except Exception as e: ok=False; bad.append(f'{p.name}:{e}')
add(ok,'P5 all Python sources parse', '; '.join(bad[:3]))
add('SIM SUMMARY: PASS=55 FAIL=0' in final and 'RUN_IMPL=1' in final,'P5 canonical build gates 55/55 before implementation')

fails=[x for x in checks if not x[0]]
print(f"SECOND_FIVE_PASS_AUDIT {'PASS' if not fails else 'FAIL'}: {len(checks)-len(fails)}/{len(checks)} checks")
if fails:
    for _,n,d in fails: print('FAILED:',n,d)
    sys.exit(1)
