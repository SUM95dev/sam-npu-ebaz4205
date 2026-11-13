#!/usr/bin/env python3
from operator import index as integer

import argparse, struct, json

def require_i8(x,label="value"):
    x=integer(x)
    if x < -128 or x > 127:
        raise ValueError(f"{label}={x} is outside signed INT8 range")
    return x

def require_i32(x,label="value"):
    x=integer(x)
    if x < -(1<<31) or x > (1<<31)-1:
        raise ValueError(f"{label}={x} is outside signed INT32 range")
    return x

def pack_int8(x,label="value"):
    return struct.pack("b", require_i8(x,label))

def make_feed(A, B, tile=8, bias=None):
    tile=integer(tile)
    if tile <= 0:
        raise ValueError("tile must be positive")
    if bias is not None and tile != 8:
        raise ValueError("streamed bias preamble is defined for the release 8x8 hardware tile")
    if not A or not B or not A[0] or not B[0]:
        raise ValueError("A and B must be non-empty matrices")
    M=len(A); K=len(A[0]); N=len(B[0])
    if any(len(row) != K for row in A):
        raise ValueError("A is ragged")
    if len(B) != K or any(len(row) != N for row in B):
        raise ValueError("B shape must be KxN and non-ragged")
    if M > 65535 or N > 65535 or K > 65535:
        raise ValueError("M/N/K exceed 16-bit hardware register limits")
    if bias is not None and len(bias) != N:
        raise ValueError("bias length must equal N")
    out=bytearray()
    mtiles=(M+tile-1)//tile
    ntiles=(N+tile-1)//tile

    for tm in range(mtiles):
        for tn in range(ntiles):
            if bias is not None:
                cols=[require_i32(bias[tn*tile+c],f"bias[{tn*tile+c}]") if tn*tile+c<N else 0 for c in range(tile)]
                for base in range(0,tile,4):
                    chunk=cols[base:base+4]+[0]*max(0,4-len(cols[base:base+4]))
                    out += struct.pack("<4i",*chunk[:4])
            # The systolic edge stream is skewed: for feed_step s,
            # row r gets A[row, k=s-r], col c gets B[k=s-c, col].
            for s in range(K+tile-1):
                avec=[]
                bvec=[]
                for r in range(tile):
                    row=tm*tile+r
                    k=s-r
                    v=A[row][k] if row<M and 0<=k<K else 0
                    avec.append(v)
                for c in range(tile):
                    col=tn*tile+c
                    k=s-c
                    v=B[k][col] if col<N and 0<=k<K else 0
                    bvec.append(v)
                for r,v in enumerate(avec): out += pack_int8(v,f"A tile row {r}")
                for c,v in enumerate(bvec): out += pack_int8(v,f"B tile col {c}")
    return bytes(out)

def matmul(A,B):
    M=len(A);K=len(A[0]);N=len(B[0])
    return [[sum(int(A[i][k])*int(B[k][j]) for k in range(K)) for j in range(N)] for i in range(M)]

if __name__=="__main__":
    ap=argparse.ArgumentParser()
    ap.add_argument("json_file", help='JSON: {"A":[...],"B":[...]}')
    ap.add_argument("-o","--output",default="matmul_feed.bin")
    ap.add_argument("--tile",type=int,default=8)
    args=ap.parse_args()
    d=json.load(open(args.json_file))
    blob=make_feed(d["A"],d["B"],args.tile,d.get("bias"))
    open(args.output,"wb").write(blob)
    print("bytes",len(blob))
    print("golden",matmul(d["A"],d["B"]))
