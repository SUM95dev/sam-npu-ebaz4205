#!/usr/bin/env python3
"""Strict packer for the compact SNPU v2 weight/layer package."""
from operator import index as integer

import json, struct, argparse

MAGIC=b"SNPU"; VERSION=2; VERSION_Q=3
QUANT_KEYS=("qmul","qshift","zero_point","relu","src")
OP_MATMUL=1; OP_CONV2D=2; OP_RELU=3; OP_MAXPOOL2=4; OP_ADD=5

def require_u16(v,name,allow_zero=False):
    v=integer(v)
    if v<0 or v>65535 or (not allow_zero and v==0): raise ValueError(f"{name} must be {'0..' if allow_zero else '1..'}65535")
    return v

def as_i8(vals,name):
    out=[]
    for i,v in enumerate(vals):
        v=integer(v)
        if v < -128 or v > 127: raise ValueError(f"{name}[{i}]={v} is outside signed INT8 range")
        out.append(v)
    return out

def as_i32(vals,name):
    out=[]
    for i,v in enumerate(vals):
        v=integer(v)
        if v < -(1<<31) or v > (1<<31)-1: raise ValueError(f"{name}[{i}]={v} is outside signed INT32 range")
        out.append(v)
    return out

def quant_block(L,li):
    """v3 per-layer requantization record: int32 qmul, uint8 qshift, int8 zero_point, uint8 flags(bit0=ReLU)."""
    qmul=integer(L.get("qmul",1)); qshift=integer(L.get("qshift",0)); zp=integer(L.get("zero_point",0))
    relu=L.get("relu",False)
    if not (-(1<<31)<=qmul<(1<<31)): raise ValueError(f"layer {li} qmul is outside signed INT32 range")
    if not (0<=qshift<=63): raise ValueError(f"layer {li} qshift must be 0..63")
    if not (-128<=zp<=127): raise ValueError(f"layer {li} zero_point is outside signed INT8 range")
    if relu not in (True,False,0,1): raise ValueError(f"layer {li} relu must be a boolean")
    return struct.pack("<iBbB",qmul,qshift,zp,1 if relu else 0)

def write_i8(f,vals):
    for v in vals: f.write(struct.pack("b",v))

def flatten(x):
    if isinstance(x,list):
        for e in x: yield from flatten(e)
    else: yield x

def pack_model(spec,out_path):
    layers=spec.get("layers")
    if not isinstance(layers,list) or not layers: raise ValueError("model must contain a non-empty layers list")
    if len(layers)>65535: raise ValueError("too many layers for SNPU header")
    ver=spec.get("version")
    ver=None if ver is None else integer(ver)
    if ver not in (None,VERSION,VERSION_Q): raise ValueError("model version must be 2 or 3")
    has_q=any(isinstance(L,dict) and any(k in L for k in QUANT_KEYS) for L in layers)
    if ver is None: ver=VERSION
    if ver==VERSION and has_q and "version" in spec:
        raise ValueError("per-layer quantization/src fields require model version 3")
    if has_q: ver=VERSION_Q
    q3=(ver==VERSION_Q)
    encoded=[]
    for li,L in enumerate(layers):
        if not isinstance(L,dict) or "type" not in L: raise ValueError(f"layer {li} must be an object with type")
        typ=str(L["type"]).lower(); b=bytearray()
        if typ=="matmul":
            M=require_u16(L["M"],f"layer {li} M"); N=require_u16(L["N"],f"layer {li} N"); K=require_u16(L["K"],f"layer {li} K")
            weights=as_i8(list(flatten(L["weights"])),f"layer {li} weights"); bias=as_i32(L.get("bias",[0]*N),f"layer {li} bias")
            if len(weights)!=K*N: raise ValueError(f"layer {li} MatMul weights count {len(weights)} != K*N {K*N}")
            if len(bias)!=N: raise ValueError(f"layer {li} MatMul bias count {len(bias)} != N {N}")
            b += struct.pack("<B",OP_MATMUL)
            if q3: b += quant_block(L,li)
            b += struct.pack("<HHH",M,N,K); b += struct.pack("<I",len(weights)); b += struct.pack(f"<{len(weights)}b",*weights)
            b += struct.pack("<I",len(bias)); b += struct.pack(f"<{len(bias)}i",*bias)
        elif typ in ("conv2d","depthwiseconv2d"):
            H=require_u16(L["in_h"],f"layer {li} in_h"); W=require_u16(L["in_w"],f"layer {li} in_w"); C=require_u16(L["in_c"],f"layer {li} in_c"); O=require_u16(L["out_c"],f"layer {li} out_c")
            G=integer(L.get("groups",C if typ=="depthwiseconv2d" else 1)); Kh=integer(L["k_h"]); Kw=integer(L["k_w"]); S=integer(L.get("stride",1)); P=integer(L.get("pad",0))
            if not (1<=G<=65535 and C%G==0 and O%G==0): raise ValueError(f"layer {li} invalid Conv groups")
            if not (1<=Kh<=255 and 1<=Kw<=255 and 1<=S<=255 and 0<=P<=255): raise ValueError(f"layer {li} Conv kernel/stride/pad exceeds package byte fields")
            if H+2*P<Kh or W+2*P<Kw: raise ValueError(f"layer {li} Conv kernel exceeds padded input")
            weights=as_i8(list(flatten(L["weights"])),f"layer {li} weights"); bias=as_i32(L.get("bias",[0]*O),f"layer {li} bias")
            need=O*Kh*Kw*(C//G)
            if len(weights)!=need: raise ValueError(f"layer {li} Conv weights count {len(weights)} != {need}")
            if len(bias)!=O: raise ValueError(f"layer {li} Conv bias count {len(bias)} != out_c {O}")
            b += struct.pack("<B",OP_CONV2D)
            if q3: b += quant_block(L,li)
            b += struct.pack("<HHHHHBBBB",H,W,C,O,G,Kh,Kw,S,P); b += struct.pack("<I",len(weights)); b += struct.pack(f"<{len(weights)}b",*weights)
            b += struct.pack("<I",len(bias)); b += struct.pack(f"<{len(bias)}i",*bias)
        elif typ=="relu": b += struct.pack("<B",OP_RELU)
        elif typ=="maxpool2": b += struct.pack("<B",OP_MAXPOOL2)
        elif typ in ("add","residual_add"):
            if q3:
                if "src" not in L: raise ValueError(f"layer {li} Add needs 'src' (-1=model input, or an earlier layer index) in a version 3 model")
                src=integer(L["src"])
                if not (-1<=src<li): raise ValueError(f"layer {li} Add src must be -1..{li-1}")
                b += struct.pack("<BhB",OP_ADD,src,1 if L.get("relu",False) else 0)
            else: b += struct.pack("<B",OP_ADD)
        else: raise ValueError("unsupported layer "+typ)
        encoded.append(bytes(b))
    with open(out_path,"wb") as f:
        f.write(MAGIC); f.write(struct.pack("<HH",ver,len(encoded)))
        for b in encoded: f.write(b)

if __name__=="__main__":
    ap=argparse.ArgumentParser(); ap.add_argument("model_json"); ap.add_argument("-o","--output",default="model.snpu")
    a=ap.parse_args(); pack_model(json.load(open(a.model_json)),a.output); print(a.output)
