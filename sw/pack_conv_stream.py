#!/usr/bin/env python3
from operator import index as integer

import argparse, json, struct

def i8(v,label="value"):
    v=integer(v)
    if v < -128 or v > 127:
        raise ValueError(f"{label}={v} is outside signed INT8 range")
    return v & 0xff

def i32(v,label="value"):
    v=integer(v)
    if v < -(1<<31) or v > (1<<31)-1:
        raise ValueError(f"{label}={v} is outside signed INT32 range")
    return v

def pack_conv_nhwc(inp, weights, stride=1, pad=0, groups=1, bias=None):
    stride=integer(stride); pad=integer(pad); groups=integer(groups)
    if not inp or not inp[0] or not inp[0][0]: raise ValueError('input must be non-empty NHWC')
    H=len(inp); W=len(inp[0]); Cin=len(inp[0][0])
    if any(len(row)!=W for row in inp): raise ValueError('ragged input height/width')
    if any(len(px)!=Cin for row in inp for px in row): raise ValueError('ragged input channels')
    if not weights or not weights[0] or not weights[0][0]: raise ValueError('weights must be non-empty OHWI')
    Cout=len(weights); Kh=len(weights[0]); Kw=len(weights[0][0])
    if groups < 1 or Cin % groups or Cout % groups: raise ValueError('groups must divide Cin and Cout')
    Cpg=Cin//groups; Opg=Cout//groups
    if any(len(oc)!=Kh for oc in weights): raise ValueError('ragged weight Kh')
    if any(len(row)!=Kw for oc in weights for row in oc): raise ValueError('ragged weight Kw')
    if any(len(v)!=Cpg for oc in weights for row in oc for v in row):
        raise ValueError(f'grouped OHWI weights must have Cin/groups={Cpg} channels per kernel point')
    if bias is None: bias=[0]*Cout
    if len(bias)!=Cout: raise ValueError('bias length must equal Cout')
    if stride <= 0: raise ValueError('stride must be > 0')
    if pad < 0: raise ValueError('pad must be >= 0')
    Oh=(H+2*pad-Kh)//stride+1; Ow=(W+2*pad-Kw)//stride+1
    if Oh<=0 or Ow<=0: raise ValueError('invalid convolution geometry')
    # Worst-case signed INT8 product magnitude is 16384 (-128 * -128).
    # Keep the INT32 accumulator safe even for adversarial data.
    macs_per_output=Kh*Kw*Cpg
    if macs_per_output > 131071:
        raise ValueError('Conv MAC count per output exceeds safe INT32 accumulator bound')
    beats=[]
    for oy in range(Oh):
        for ox in range(Ow):
            for oc in range(Cout):
                g=oc//Opg; ic_base=g*Cpg
                seq=[]
                for ky in range(Kh):
                    for kx in range(Kw):
                        iy=oy*stride+ky-pad; ix=ox*stride+kx-pad
                        for lic in range(Cpg):
                            ic=ic_base+lic
                            a=inp[iy][ix][ic] if 0<=iy<H and 0<=ix<W else 0
                            wt=weights[oc][ky][kx][lic]
                            seq.append((a,wt))
                for idx,(a,wt) in enumerate(seq):
                    last_sample = 1 if idx==len(seq)-1 else 0
                    word = i8(a,"activation") | (i8(wt,"weight")<<8) | (last_sample<<16)
                    # Bias is valid only on the first MAC beat of each output scalar.
                    # RTL consumes bits[63:32] only when it starts that scalar.
                    b=i32(bias[oc],f"bias[{oc}]") if idx==0 else 0
                    beats.append(struct.pack('<Ii8x',word,b))
    return b''.join(beats),(Oh,Ow,Cout)

if __name__=='__main__':
    ap=argparse.ArgumentParser()
    ap.add_argument('json_file')
    ap.add_argument('-o','--output',default='conv_stream.bin')
    ap.add_argument('--stride',type=int,default=None)
    ap.add_argument('--pad',type=int,default=None)
    ap.add_argument('--groups',type=int,default=None)
    args=ap.parse_args()
    d=json.load(open(args.json_file))
    stride=d.get('stride',1) if args.stride is None else args.stride
    pad=d.get('pad',0) if args.pad is None else args.pad
    groups=d.get('groups',1) if args.groups is None else args.groups
    payload,shape=pack_conv_nhwc(d['input'],d['weights'],stride,pad,groups,d.get('bias'))
    open(args.output,'wb').write(payload)
    print('beats',len(payload)//16,'bytes',len(payload),'output_shape',shape,'groups',groups)
    print('Per-output INT32 bias is embedded in bits [63:32] of the first beat.')
    print('AXI DMA TLAST must be asserted only on the final beat of the transfer.')
