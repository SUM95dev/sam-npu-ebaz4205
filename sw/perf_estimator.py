#!/usr/bin/env python3
import argparse, math

def matmul_cycles(M,N,K,tile,post_lanes=None):
    post_lanes = post_lanes or tile*tile
    mt=math.ceil(M/tile)
    nt=math.ceil(N/tile)
    # Feed K+tile-1, flush tile-1, plus tile postprocess serialized.
    per_tile=(K+tile-1)+(tile-1)+post_lanes
    return mt*nt*per_tile

if __name__=="__main__":
    ap=argparse.ArgumentParser()
    ap.add_argument("--M",type=int,required=True)
    ap.add_argument("--N",type=int,required=True)
    ap.add_argument("--K",type=int,required=True)
    ap.add_argument("--tile",type=int,default=8)
    ap.add_argument("--mhz",type=float,default=100.0)
    args=ap.parse_args()

    cyc=matmul_cycles(args.M,args.N,args.K,args.tile)
    sec=cyc/(args.mhz*1e6)
    macs=args.M*args.N*args.K
    print("estimated_cycles",cyc)
    print("estimated_seconds",sec)
    print("effective_GMAC_s",macs/sec/1e9 if sec else 0)
