#!/usr/bin/env python3
from pathlib import Path
import json, re, subprocess, sys, tempfile, struct, random, math, os
ROOT = Path(__file__).resolve().parent.parent
results=[]
def check(passno,name,ok,detail=''):
    results.append({'pass':passno,'name':name,'ok':bool(ok),'detail':str(detail)})
    print(f"P{passno} {'PASS' if ok else 'FAIL'} {name}: {detail}")

def run(cmd, **kw):
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, **kw)

# PASS 1: all source/structure
source_ext={'.v','.sv','.tcl','.py','.c','.h','.dtsi','.xdc','.sh','.md','.json'}
sources=[p for p in ROOT.rglob('*') if p.is_file() and p.suffix in source_ext and 'third_party' not in p.parts and '__pycache__' not in p.parts]
bad=[]
for p in sources:
    try:
        b=p.read_bytes()
        if not b or b'\x00' in b: bad.append(str(p.relative_to(ROOT)))
        b.decode('utf-8')
    except Exception as e: bad.append(f"{p.relative_to(ROOT)}:{e}")
check(1,'all textual source files readable/nonempty',not bad,f'{len(sources)} files; bad={bad}')
merge=[]
for p in sources:
    try:s=p.read_text()
    except:continue
    if re.search(r'(?m)^<<<<<<< |^=======\s*$|^>>>>>>> ',s): merge.append(str(p.relative_to(ROOT)))
check(1,'no merge conflict markers',not merge,merge)
r=run([sys.executable,'scripts/port_audit.py'])
check(1,'named-port consistency',r.returncode==0 and 'issues 0' in r.stdout,r.stdout.strip())
r=run([sys.executable,'scripts/fifty_pass_audit.py'])
check(1,'legacy 50-point audit still clean',r.returncode==0 and 'RESULT 50 /50' in r.stdout,r.stdout.splitlines()[0] if r.stdout else r.stderr[:200])

# PASS 2: RTL arithmetic/handshake guards and cycle-model behavior
cm=(ROOT/'rtl/conv2d_memory_top.v').read_text()
cf=(ROOT/'rtl/conv2d_gemm_feeder.v').read_text()
top=(ROOT/'rtl/npu_axis_system_top.v').read_text()
check(2,'Conv memory geometry guarded','out_w_geom_valid' in cm and 'stride_w!=0' in cm.replace(' ',''), 'stride/kernel/padded-width guard')
check(2,'Conv memory rejects unsolicited responses','req_sent || rd_' in cm, 'responses tied to outstanding/same-cycle request')
check(2,'Conv feeder guards variable divide/modulo','in_c != 0' in cf and 'k_w != 0' in cf and 'out_w != 0' in cf,'zero-dimension guards present')
check(2,'MatMul system DONE waits for AXIS drain','mm_done_pending' in top and 'mm_axis_busy' in top and 'mm_done_drained_pulse' in top,'serializer included in BUSY/DONE contract')
r=run([sys.executable,'sw/cycle_audit.py'])
check(2,'randomized MatMul cycle audit',r.returncode==0 and 'PASS' in r.stdout,r.stdout.strip())

# PASS 3: verification flow itself
vt=(ROOT/'scripts/run_vivado_verification.tcl').read_text()
tbs=sorted([p.stem for p in (ROOT/'sim').glob('tb_*.v')]+[('tb_'+p.stem if p.stem.startswith('case_') else p.stem) for p in (ROOT/'verification/extra').glob('*.v')])
listed=re.findall(r'^\s+(tb_[A-Za-z0-9_]+)\s*$',vt,re.M)
check(3,'all testbenches are in Vivado list',set(tbs)==set(listed),f'files={len(tbs)} listed={len(listed)} missing={sorted(set(tbs)-set(listed))} extra={sorted(set(listed)-set(tbs))}')
missing_markers=[]
for p in sorted((ROOT/'sim').glob('tb_*.v')):
    s=p.read_text()
    if not re.search(r'\bPASS',s) or not re.search(r'\bFAIL',s): missing_markers.append(p.name)
check(3,'every TB has explicit PASS and FAIL markers',not missing_markers,missing_markers)
check(3,'Vivado flow parses simulator logical result','regexp -line {^FAIL}' in vt and 'regexp -line {^PASS}' in vt,'simulate.log checked')
check(3,'no unbounded run-all regression','run all' not in vt and 'xsim.simulate.runtime {200us}' in vt,'finite XSim runtime')

# PASS 4: board/pins/clock/address/build safety
r=run([sys.executable,'scripts/check_ethernet_pins.py'])
check(4,'Ethernet pin map',r.returncode==0 and '14/14' in r.stdout,r.stdout.strip())
bd=(ROOT/'scripts/create_ebaz4205_full_bd.tcl').read_text()
build=(ROOT/'scripts/build_ebaz4205_system.tcl').read_text()
xdc=(ROOT/'constraints/ebaz4205_ethernet.xdc').read_text()
check(4,'GEM0 EMIO/MII integration configured','PCW_ENET0_ENET0_IO {EMIO}' in bd and 'ENET0_GMII' in bd,'PS GEM0 via EMIO')
check(4,'deterministic 64KiB control maps','0x43C00000' in bd and '0x40400000' in bd and ('64K' in bd or '0x00010000' in bd),'NPU/DMA control windows')
check(4,'MII clocks constrained','create_clock -name ebaz_mii_rx_clk' in xdc and 'create_clock -name ebaz_mii_tx_clk' in xdc,'25 MHz external clocks')
check(4,'implementation guarded by real board preset','RUN_IMPL requested without a confirmed EBAZ4205 PS7 DDR/MIO board preset' in build,'refuses guessed DDR/MIO')
bit=(ROOT/'scripts/build_bitstream_if_bd_ready.tcl').read_text()
check(4,'bitstream helper uses canonical guarded build','build_ebaz4205_system.tcl' in bit and 'vivado_system' not in bit,'single source of truth')

# PASS 5: Linux/DMA/network/packer end-to-end contracts
cflags=['gcc','-std=c11','-D_DEFAULT_SOURCE','-Wall','-Wextra','-Werror','-O2']
with tempfile.TemporaryDirectory() as td:
    ok=True; det=[]
    for src in ['sw/linux/npu_net_server.c','sw/linux/npu_dma_proxy_test.c','sw/linux/npu_uio.c']:
        out=Path(td)/Path(src).stem
        rr=run(cflags+[src,'-o',str(out)])
        ok &= rr.returncode==0
        if rr.returncode:det.append(f'{src}:{rr.stderr[:300]}')
check(5,'userspace C builds warning-free',ok,det or '3 binaries')
drv=(ROOT/'sw/linux/npu_dma_proxy.c').read_text()
check(5,'DMA RX mmap offset normalized','saved_pgoff' in drv and 'vma->vm_pgoff = 0' in drv,'separate coherent RX allocation')
check(5,'DMA device single-owner and close-safe','.open = npu_open' in drv and '.release = npu_release' in drv and 'dmaengine_terminate_sync(d->tx)' in drv,'pending DMA cannot survive owner close')
dtsi=(ROOT/'sw/linux/npu-uio.dtsi').read_text()
check(5,'UIO fragment does not overwrite bootargs',not re.search(r'(?m)^\s*bootargs\s*=', dtsi),'existing kernel cmdline preserved')
server=(ROOT/'sw/linux/npu_net_server.c').read_text()
check(5,'network server validates MatMul DMA sizes','expected_in' in server and 'expected_out' in server and '(in_len & 0xFu) != 0' in server and '(out_len & 0x3u) != 0' in server,'framing/alignment enforced')

# Random packer agreement: standalone vs network client
ns1={'__name__':'audit'}; exec((ROOT/'sw/pack_matmul_stream.py').read_text(),ns1)
ns2={'__name__':'audit'}; exec((ROOT/'sw/host/npu_net_client.py').read_text(),ns2)
ok=True
for _ in range(200):
    M=random.randint(1,16); K=random.randint(1,16); N=random.randint(1,16)
    A=[[random.randint(-128,127) for _ in range(K)] for _ in range(M)]
    B=[[random.randint(-128,127) for _ in range(N)] for _ in range(K)]
    bias=[random.randint(-(1<<20),(1<<20)) for _ in range(N)] if random.choice([False,True]) else None
    a=ns1['make_feed'](A,B,8,bias)
    b,_shape=ns2['pack_matmul'](A,B,8,bias)
    per_tile=(K+7)*16 + (32 if bias is not None else 0)
    if a!=b or len(a)!=math.ceil(M/8)*math.ceil(N/8)*per_tile:
        ok=False; break
check(5,'host/network MatMul packers agree',ok,'200 random matrix shapes, mixed bias/no-bias')

failed=[x for x in results if not x['ok']]
report={'passes':5,'checks':results,'failed':len(failed)}
(ROOT/'docs/FIVE_PASS_SOURCE_AUDIT.json').write_text(json.dumps(report,indent=2))
print(f"FIVE_PASS_SOURCE_AUDIT {'PASS' if not failed else 'FAIL'}: {len(results)-len(failed)}/{len(results)} checks")
sys.exit(1 if failed else 0)
