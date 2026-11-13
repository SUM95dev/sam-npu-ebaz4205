#!/usr/bin/env python3
"""Parse and validate SNPU v2 packages without needing FPGA hardware."""
import argparse, json, struct
MAGIC=b'SNPU'; VERSION=2; VERSION_Q=3
NAMES={1:'MatMul',2:'Conv2D',3:'ReLU',4:'MaxPool2x2',5:'Add'}

def take(data,off,fmt):
    st=struct.Struct(fmt)
    if off+st.size>len(data): raise ValueError('truncated package')
    return st.unpack_from(data,off),off+st.size

def inspect(path):
    with open(path,'rb') as f:
        data=f.read()
    if len(data)<8 or data[:4]!=MAGIC: raise ValueError('bad SNPU magic/truncated header')
    (ver,nlayers),off=take(data,4,'<HH')
    if ver not in (VERSION,VERSION_Q): raise ValueError(f'unsupported SNPU version {ver}')
    q3=(ver==VERSION_Q)
    if not nlayers: raise ValueError('model must contain at least one layer')
    layers=[]
    for idx in range(nlayers):
        (op,),off=take(data,off,'<B')
        quant=None
        if q3 and op in (1,2):
            (qmul,qshift,zp,qflags),off=take(data,off,'<iBbB')
            if qshift>63 or qflags>1: raise ValueError(f'layer {idx}: invalid quantization record')
            quant={'qmul':qmul,'qshift':qshift,'zero_point':zp,'relu':bool(qflags)}
        if op==1:
            (M,N,K),off=take(data,off,'<HHH'); (nw,),off=take(data,off,'<I')
            if off+nw>len(data): raise ValueError(f'layer {idx}: truncated MatMul weights')
            off+=nw; (nb,),off=take(data,off,'<I')
            if off+4*nb>len(data): raise ValueError(f'layer {idx}: truncated MatMul bias')
            off+=4*nb
            if not (M and N and K): raise ValueError(f'layer {idx}: zero MatMul dimension')
            if nw!=K*N or nb!=N: raise ValueError(f'layer {idx}: invalid MatMul counts weights={nw}/{K*N} bias={nb}/{N}')
            layers.append({'type':'matmul','M':M,'N':N,'K':K,'weights':nw,'bias':nb,**({'quant':quant} if quant else {})})
        elif op==2:
            (H,W,C,O,G,Kh,Kw,S,P),off=take(data,off,'<HHHHHBBBB')
            (nw,),off=take(data,off,'<I');
            if off+nw>len(data): raise ValueError(f'layer {idx}: truncated Conv weights')
            off+=nw; (nb,),off=take(data,off,'<I')
            if off+4*nb>len(data): raise ValueError(f'layer {idx}: truncated Conv bias')
            off+=4*nb
            if not (H and W and C and O and Kh and Kw and S): raise ValueError(f'layer {idx}: zero Conv dimension/kernel/stride')
            if H+2*P<Kh or W+2*P<Kw: raise ValueError(f'layer {idx}: Conv kernel exceeds padded input')
            if not G or C%G or O%G: raise ValueError(f'layer {idx}: invalid Conv groups')
            need=O*Kh*Kw*(C//G)
            if nw!=need or nb!=O: raise ValueError(f'layer {idx}: invalid Conv counts weights={nw}/{need} bias={nb}/{O}')
            layers.append({'type':'conv2d','in_h':H,'in_w':W,'in_c':C,'out_c':O,'groups':G,'kernel':[Kh,Kw],'stride':S,'pad':P,'weights':nw,'bias':nb,**({'quant':quant} if quant else {})})
        elif op==5 and q3:
            (src,aflags),off=take(data,off,'<hB')
            if not (-1<=src<idx) or aflags>1: raise ValueError(f'layer {idx}: invalid Add src/flags')
            layers.append({'type':'add','src':src,'relu':bool(aflags)})
        elif op in (3,4,5): layers.append({'type':NAMES[op].lower()})
        else: raise ValueError(f'layer {idx}: unknown opcode {op}')
    if off!=len(data): raise ValueError(f'{len(data)-off} trailing bytes after declared layers')
    return {'version':ver,'layers':layers,'bytes':len(data)}

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('model'); ap.add_argument('--json',action='store_true'); a=ap.parse_args()
    x=inspect(a.model)
    if a.json: print(json.dumps(x,indent=2)); return
    print(f"SNPU v{x['version']} layers={len(x['layers'])} bytes={x['bytes']}")
    for i,L in enumerate(x['layers']): print(f"{i:03d}: {L}")
    print('VALID')
if __name__=='__main__': main()
