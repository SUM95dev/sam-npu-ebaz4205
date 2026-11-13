#!/usr/bin/env python3
"""End-to-end Sam NPU benchmark over a persistent TCP connection."""
import argparse, random, statistics, sys, time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import npu_net_client as cli

def percentile(xs,p):
    ys=sorted(xs)
    if not ys: return 0.0
    i=(len(ys)-1)*p; lo=int(i); hi=min(lo+1,len(ys)-1); f=i-lo
    return ys[lo]*(1-f)+ys[hi]*f

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('host'); ap.add_argument('--port',type=int,default=9505)
    ap.add_argument('--m',type=int,default=32); ap.add_argument('--n',type=int,default=32); ap.add_argument('--k',type=int,default=32)
    ap.add_argument('--runs',type=int,default=20); ap.add_argument('--warmup',type=int,default=3)
    ap.add_argument('--bias',action='store_true'); ap.add_argument('--relu',action='store_true'); ap.add_argument('--seed',type=int,default=956)
    ap.add_argument('--clock-mhz',type=float,default=100.0,help='FCLK used to convert hardware cycle counter to time')
    a=ap.parse_args()
    if min(a.m,a.n,a.k,a.runs)<=0: raise SystemExit('dimensions/runs must be positive')
    rnd=random.Random(a.seed)
    A=[[rnd.randint(-3,3) for _ in range(a.k)] for _ in range(a.m)]
    B=[[rnd.randint(-3,3) for _ in range(a.n)] for _ in range(a.k)]
    bias=[rnd.randint(-16,16) for _ in range(a.n)] if a.bias else None
    payload,(M,N,K)=cli.pack_matmul(A,B,bias=bias)
    flags=cli.FLAG_MATMUL_BIAS if bias is not None else 0
    out_bytes=M*N*4
    with cli.NpuSession(a.host,a.port) as s:
        before=cli.parse_info(s.request(cli.OP_INFO))
        caps=before['caps']
        if not (caps&1): raise SystemExit('hardware does not advertise MatMul')
        if a.bias and not (caps&(1<<7)): raise SystemExit('hardware does not advertise streamed MatMul bias')
        for _ in range(a.warmup): s.request(cli.OP_MATMUL,M,N,K,payload,out_bytes,a.relu,extra_flags=flags)
        ts=[]
        for _ in range(a.runs):
            t0=int(time.perf_counter()*1e9); s.request(cli.OP_MATMUL,M,N,K,payload,out_bytes,a.relu,extra_flags=flags); ts.append((int(time.perf_counter()*1e9)-t0)/1e6)
        after=cli.parse_info(s.request(cli.OP_INFO))
    ops=2.0*M*N*K
    avg=statistics.mean(ts); med=statistics.median(ts); p95=percentile(ts,0.95); best=min(ts)
    print(f'MatMul {M}x{K} * {K}x{N}, runs={a.runs}, input={len(payload)} B, output={out_bytes} B, bias={bool(bias)}')
    print(f'end-to-end ms: best={best:.3f} median={med:.3f} mean={avg:.3f} p95={p95:.3f}')
    print(f'end-to-end effective GOPS: best={ops/(best*1e6):.4f} median={ops/(med*1e6):.4f}')
    cyc=after['last_job_cycles']
    if cyc and a.clock_mhz>0:
        hw_ms=cyc/(a.clock_mhz*1000.0); print(f'last hardware busy cycles={cyc} -> {hw_ms:.4f} ms @ {a.clock_mhz:g} MHz, effective={ops/(hw_ms*1e6):.4f} GOPS')
    dj=(after['jobs']-before['jobs'])&0xffffffff; de=(after['errors']-before['errors'])&0xffffffff
    print(f'hardware counters delta: jobs={dj} errors={de}, caps=0x{caps:08x}')

if __name__=='__main__': main()
