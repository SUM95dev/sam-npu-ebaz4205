#!/usr/bin/env python3
import json, random, argparse

def matmul(A,B):
    M=len(A); K=len(A[0]); N=len(B[0])
    return [[sum(A[i][k]*B[k][j] for k in range(K)) for j in range(N)] for i in range(M)]

def conv2d(inp,w,bias=None,stride=1,pad=0,groups=1):
    H=len(inp); W=len(inp[0]); Cin=len(inp[0][0]); Cout=len(w); Kh=len(w[0]); Kw=len(w[0][0])
    if Cin%groups or Cout%groups: raise ValueError('invalid groups')
    Cpg=Cin//groups; Opg=Cout//groups
    Oh=(H+2*pad-Kh)//stride+1; Ow=(W+2*pad-Kw)//stride+1
    out=[[[0 for _ in range(Cout)] for _ in range(Ow)] for _ in range(Oh)]
    for oy in range(Oh):
      for ox in range(Ow):
       for oc in range(Cout):
        s=0 if bias is None else bias[oc]; base=(oc//Opg)*Cpg
        for ky in range(Kh):
         for kx in range(Kw):
          iy=oy*stride+ky-pad; ix=ox*stride+kx-pad
          if 0<=iy<H and 0<=ix<W:
           for lic in range(Cpg): s += inp[iy][ix][base+lic]*w[oc][ky][kx][lic]
        out[oy][ox][oc]=s
    return out

def rnd(): return random.randint(-4,4)

if __name__=="__main__":
    ap=argparse.ArgumentParser(); ap.add_argument("-o","--output",default="selftest_vectors.json"); ap.add_argument("--seed",type=int,default=95)
    args=ap.parse_args(); random.seed(args.seed); tests=[]
    for M,K,N in [(2,2,2),(8,8,8),(5,7,3),(9,4,10)]:
        A=[[rnd() for _ in range(K)] for _ in range(M)]; B=[[rnd() for _ in range(N)] for _ in range(K)]
        tests.append({"type":"matmul","M":M,"N":N,"K":K,"A":A,"B":B,"golden":matmul(A,B)})

    H,W,Cin,Cout,Kh,Kw=5,5,2,3,3,3
    inp=[[[rnd() for _ in range(Cin)] for _ in range(W)] for _ in range(H)]
    weights=[[[[rnd() for _ in range(Cin)] for _ in range(Kw)] for _ in range(Kh)] for _ in range(Cout)]
    bias=[random.randint(-10,10) for _ in range(Cout)]
    tests.append({"type":"conv2d","input":inp,"weights":weights,"bias":bias,"groups":1,"stride":1,"pad":1,"golden":conv2d(inp,weights,bias,1,1,1)})

    # Depthwise Conv: groups=Cin=Cout, one input channel per output kernel.
    H=W=3; Cin=Cout=3; Kh=Kw=3
    inp=[[[rnd() for _ in range(Cin)] for _ in range(W)] for _ in range(H)]
    weights=[[[[rnd()] for _ in range(Kw)] for _ in range(Kh)] for _ in range(Cout)]
    bias=[random.randint(-5,5) for _ in range(Cout)]
    tests.append({"type":"conv2d","input":inp,"weights":weights,"bias":bias,"groups":Cin,"stride":1,"pad":1,"golden":conv2d(inp,weights,bias,1,1,Cin)})

    add_a=[random.randint(-128,127) for _ in range(16)]; add_b=[random.randint(-128,127) for _ in range(16)]
    tests.append({"type":"add","A":add_a,"B":add_b,"golden":[max(-128,min(127,a+b)) for a,b in zip(add_a,add_b)]})
    groups=[[random.randint(-128,127) for _ in range(4)] for _ in range(8)]
    tests.append({"type":"maxpool2","groups":groups,"golden":[max(g) for g in groups]})

    with open(args.output,"w") as f: json.dump({"seed":args.seed,"tests":tests},f,indent=2)
    print(args.output)
