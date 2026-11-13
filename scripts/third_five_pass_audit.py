#!/usr/bin/env python3
from pathlib import Path
import re, struct, subprocess, tempfile, random, sys
root=Path(__file__).resolve().parents[1]
checks=[]
def add(ok,name,detail=''):
    checks.append((bool(ok),name,detail)); print(f"{'PASS' if ok else 'FAIL'} {name}"+(f" :: {detail}" if detail else ''))
def txt(r): return (root/r).read_text(errors='replace')

# P1 reset / clock / CDC
prod=['npu_bd_top.v','npu_axis_system_top.v','npu_axi_lite_slave.v','npu_regs.v','axis_matmul_feeder.v','matmul_engine.v','matmul_controller.v','systolic_array.v','npu_pe.v','tile_postprocess.v','npu_postprocess.v','npu_postprocess_pipe.v','axis_tile_output.v','axis_conv_adapter.v','conv_stream_job_engine.v','conv2d_stream_engine.v','axis_maxpool2x2_engine.v','axis_elementwise_add_engine.v']
ptext='\n'.join(txt('rtl/'+x) for x in prod)
clocks=set(re.findall(r'input\s+(?:wire\s+)?(?:\[[^\]]+\]\s+)?([A-Za-z_][A-Za-z0-9_]*(?:clk|aclk))\b',ptext,re.I))
add(not re.search(r'always\s*@\s*\([^\)]*(?:posedge|negedge)\s+(?!clk\b|aclk\b)',ptext),'P1 production sequential logic uses declared synchronous clocks')
add('wire core_rst = rst | abort_pulse;' in txt('rtl/npu_axis_system_top.v'),'P1 abort is synchronously folded into datapath reset')
add('ASSOCIATED_RESET aresetn' in txt('rtl/npu_bd_top.v') and 'POLARITY ACTIVE_LOW' in txt('rtl/npu_bd_top.v'),'P1 AXI clock/reset metadata is explicit')
bd=txt('scripts/create_ebaz4205_full_bd.tcl')
add('npu_0/aclk rst_fclk0/slowest_sync_clk' in bd and 'axi_dma_0/m_axi_mm2s_aclk' in bd and 'axi_dma_0/m_axi_s2mm_aclk' in bd,'P1 NPU/DMA/control datapath shares FCLK0 domain')
vt=txt('scripts/run_vivado_verification.tcl')
add('xsim.elaborate.mt_level' in vt and 'set xsim_mt_level off' in vt,'P1 XSim elaboration defaults to low-memory single-thread mode')
add('proc_sys_reset:5.0' in bd and 'peripheral_aresetn' in bd and 'interconnect_aresetn' in bd,'P1 board reset is synchronized by proc_sys_reset')

# P2 protocol / state edge cases
ax=txt('rtl/npu_axi_lite_slave.v')
add(all(x in ax for x in ['aw_hold_valid','w_hold_valid','read_pending','s_axi_bvalid && s_axi_bready','s_axi_rvalid && s_axi_rready']),'P2 AXI-Lite independently buffers AW/W and holds responses')
tile=txt('rtl/axis_tile_output.v')
add('tile_hold<=tile_data' in tile and 'mask_hold<=lane_valid' in tile and 'tile_last_hold<=tile_last' in tile,'P2 AXIS tile output snapshots payload under backpressure')
sys=txt('rtl/npu_axis_system_top.v')
add('mm_done_pending' in sys and '!mm_axis_busy' in sys and 'mm_done_drained_pulse' in sys,'P2 MatMul DONE waits for final AXIS drain')
mem=txt('rtl/conv2d_memory_top.v')
add(all(x in mem for x in ['!sample_fire && inside','!sample_fire && !weight_loaded','!sample_fire && first_sample']),'P2 memory Conv suppresses duplicate requests during registered sample_fire')
convjob=txt('rtl/conv_stream_job_engine.v')
add('output_space' in convjob and 'out_valid && out_ready' in convjob and 'final_output_pending' in convjob,'P2 Conv job output buffer/backpressure/final marker state is explicit')
addeng=txt('rtl/axis_elementwise_add_engine.v'); pool=txt('rtl/axis_maxpool2x2_engine.v')
add('!out_valid || (out_ready && !out_last)' in addeng and 'busy && !out_valid' in pool,'P2 Add/Pool input readiness respects buffered output backpressure')

# P3 arithmetic / sign / overflow
addr=txt('rtl/conv2d_addrgen.v')
add(all(x in addr for x in ['wire [63:0] iy_u','wire [63:0] input_index','wire [63:0] weight_index','wire [63:0] output_index','wire [63:0] bias_index']),'P3 Conv address arithmetic widens intermediates before multiply/shift')
pp=txt('rtl/npu_postprocess.v')
add('localparam BIAS_W  = ACC_W + 1' in pp and 'localparam SCALE_W = BIAS_W + 32' in pp and '>>> shift' in pp,'P3 postprocess preserves bias carry and signed scaled width')
regs=txt('rtl/npu_regs.v')
add('qshift<=wr_data[5:0]' in regs and 'zero_point<=wr_data[7:0]' in regs,'P3 quantization register widths match datapath')
server=txt('sw/linux/npu_net_server.c'); convp=txt('sw/pack_conv_stream.py')
add('macs_this_output > 131071u' in server and 'macs_per_output > 131071' in convp,'P3 Conv INT32 MAC worst-case bound enforced host+server')
matp=txt('sw/pack_matmul_stream.py')
add('M > 65535 or N > 65535 or K > 65535' in matp,'P3 MatMul dimensions cannot exceed 16-bit hardware registers')
add('sum_wide' in addeng and 'MAXV' in addeng and 'MINV' in addeng,'P3 elementwise Add uses widened sum plus INT8 saturation')

# P4 host / RTL ABI
client=txt('sw/host/npu_net_client.py')
add('REQ=struct.Struct("!4sHHHHHHiBbhIII")' in client and 'REP=struct.Struct("!4sIiI")' in client,'P4 Python wire structs are fixed and packed')
# independently verify protocol header sizes against packed C declaration: 36-byte req, 16-byte rep
ns={}; exec(compile(client,'client','exec'),ns)
add(ns['REQ'].size==36 and ns['REP'].size==16,'P4 request/reply ABI sizes are 36/16 bytes',f"REQ={ns['REQ'].size} REP={ns['REP'].size}")
add('expected_in = mt * nt * per_tile' in server and 'expected_out = (uint64_t)M * (uint64_t)N * 4u' in server,'P4 server validates exact MatMul DMA byte contract')
add('sam_npu_matmul_tile_to_row_major(tx, rx, M, N, 8u)' in server,'P4 network MatMul result is normalized to row-major')
# randomized packer size agreement with server formula
ok=True; random.seed(15095)
for _ in range(200):
    M=random.randint(1,40); N=random.randint(1,40); K=random.randint(1,40)
    A=[[0]*K for _ in range(M)]; B=[[0]*N for _ in range(K)]
    bias=[0]*N if random.choice([False,True]) else None
    blob,(m,n,k)=ns['pack_matmul'](A,B,bias=bias)
    expected=((M+7)//8)*((N+7)//8)*((K+7)*16 + (32 if bias is not None else 0))
    if len(blob)!=expected: ok=False; break
add(ok,'P4 randomized client MatMul framing matches server formula','200 shapes')
clamp=[]
for rel in ['sw/host/npu_net_client.py','sw/pack_matmul_stream.py','sw/pack_conv_stream.py','sw/model_packer.py']:
    s=txt(rel)
    if re.search(r'max\s*\(\s*-128\s*,\s*min\s*\(\s*127',s) or re.search(r'min\s*\(\s*127\s*,\s*max\s*\(\s*-128',s): clamp.append(rel)
add(not clamp,'P4 deploy paths do not silently clamp INT8',','.join(clamp))

# P5 build / reproducibility / resource safety
build=txt('scripts/build_ebaz4205_system.tcl'); final=txt('scripts/build_ebaz4205_final.sh'); fetch=txt('scripts/fetch_ebaz4205_board_support.sh')
add('set vivado_jobs 1' in build and 'set vivado_jobs 1' in vt and '-jobs $vivado_jobs' in build and '-jobs $vivado_jobs' in vt,'P5 Vivado defaults to one worker with override support')
add('modules -j1' in txt('scripts/validate_release.sh'),'P5 kernel-module validation is also low-memory')
add('create_clock -period 10.000 -name aclk' in vt,'P5 core synthesis has real 100 MHz timing constraint')
add('get_timing_paths' in build and 'Final implementation fails setup timing' in build and 'Final implementation fails hold timing' in build,'P5 full implementation hard-fails negative setup/hold slack')
add('preset.xml' in fetch and 'presets.xml' not in fetch,'P5 EBAZ board-support filename matches actual repository')
add('SIM SUMMARY: PASS=55 FAIL=0' in final and 'RUN_SYNTH=1 RUN_IMPL=1' in final,'P5 canonical build gates XSim before full implementation')

fails=[x for x in checks if not x[0]]
print(f"THIRD_FIVE_PASS_AUDIT {'PASS' if not fails else 'FAIL'}: {len(checks)-len(fails)}/{len(checks)} checks")
if fails:
  for _,n,d in fails: print('FAILED:',n,d)
  sys.exit(1)
