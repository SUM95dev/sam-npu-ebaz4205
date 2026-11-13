#!/usr/bin/env python3
"""Strict ONNX -> SNPU JSON converter for the supported INT8 inference subset.

This tool intentionally rejects ambiguous/unquantized models instead of silently
casting floating-point weights to INT8.  It also uses ONNX shape inference and
requires static shapes for operators whose SNPU records need dimensions.

Supported compute subset:
- MatMul
- Gemm (transA=0, transB=0, alpha=beta=1)
- Conv2D including grouped/depthwise Conv
- Relu
- Add (tensor-tensor; constant Add is not auto-fused)
- MaxPool 2x2 stride 2, no padding

Optional dependency: onnx + numpy.
"""
import argparse, json

def require_onnx():
    try:
        import onnx
        import numpy as np
        from onnx import numpy_helper
        return onnx,np,numpy_helper
    except Exception as e:
        raise SystemExit("Install optional dependencies: pip install onnx numpy\n"+str(e))

def attrs(node):
    out={}
    for a in node.attribute:
        if a.type == 1: out[a.name]=a.f
        elif a.type == 2: out[a.name]=a.i
        elif a.type == 3: out[a.name]=a.s.decode("utf-8")
        elif a.type == 7: out[a.name]=list(a.ints)
    return out

def check_spatial_attrs(op,a):
    if a.get("auto_pad","NOTSET") not in ("NOTSET", ""):
        raise SystemExit(f"{op} auto_pad is unsupported; supply explicit symmetric pads")
    if a.get("dilations",[1,1]) != [1,1]:
        raise SystemExit(f"{op} dilation is unsupported")
    if op=="MaxPool" and (a.get("ceil_mode",0) or a.get("storage_order",0)):
        raise SystemExit("MaxPool ceil_mode/storage_order is unsupported")

def flatten(x): return x.reshape(-1).tolist()

def build_shape_map(model):
    sm={}
    vals=list(model.graph.input)+list(model.graph.value_info)+list(model.graph.output)
    for v in vals:
        tt=v.type.tensor_type
        if not tt.HasField('shape'): continue
        dims=[]
        for d in tt.shape.dim:
            dims.append(int(d.dim_value) if d.HasField('dim_value') and int(d.dim_value)>0 else None)
        sm[v.name]=dims
    return sm

def static_shape(sm,name,rank,what):
    sh=sm.get(name)
    if sh is None or len(sh)!=rank or any(x is None or x<=0 for x in sh):
        raise SystemExit(f"{what} requires a static rank-{rank} shape for {name!r}; got {sh}")
    return [int(x) for x in sh]

def as_i8_exact(arr,np,label):
    if not np.issubdtype(arr.dtype,np.integer):
        raise SystemExit(f"{label} is {arr.dtype}; SNPU converter will not silently quantize/cast floating-point weights")
    if arr.size and (int(arr.min()) < -128 or int(arr.max()) > 127):
        raise SystemExit(f"{label} contains values outside signed INT8 range")
    return arr.astype(np.int8)

def as_i32_exact(arr,np,label):
    if not np.issubdtype(arr.dtype,np.integer):
        raise SystemExit(f"{label} is {arr.dtype}; bias must already be quantized integer data")
    if arr.size and (int(arr.min()) < -(1<<31) or int(arr.max()) > (1<<31)-1):
        raise SystemExit(f"{label} contains values outside signed INT32 range")
    return arr.astype(np.int32)

def main():
    onnx,np,numpy_helper=require_onnx()
    ap=argparse.ArgumentParser(); ap.add_argument("model"); ap.add_argument("-o","--output",default="model_from_onnx.json")
    args=ap.parse_args()
    m=onnx.load(args.model); onnx.checker.check_model(m)
    try: m=onnx.shape_inference.infer_shapes(m)
    except Exception as e: raise SystemExit("ONNX shape inference failed: "+str(e))
    shapes=build_shape_map(m)
    init={x.name:numpy_helper.to_array(x) for x in m.graph.initializer}; layers=[]

    for node in m.graph.node:
        op=node.op_type; a=attrs(node); label=node.name or op
        if op=="Relu":
            layers.append({"type":"relu"})
        elif op=="Add":
            if any(x in init for x in node.input):
                raise SystemExit("Add with constant initializer is not automatically lowered; fuse/quantize it explicitly")
            layers.append({"type":"add"})
        elif op=="MaxPool":
            check_spatial_attrs(op,a)
            if len(node.output)>1: raise SystemExit("MaxPool indices output is unsupported")
            k=a.get("kernel_shape",[2,2]); s=a.get("strides",[1,1]); pads=a.get("pads",[0,0,0,0])
            if k != [2,2] or s != [2,2] or pads != [0,0,0,0]:
                raise SystemExit("Only MaxPool 2x2 stride2 without padding supported in hardware mode")
            layers.append({"type":"maxpool2"})
        elif op=="MatMul":
            if len(node.input)<2 or node.input[1] not in init: raise SystemExit("MatMul requires constant weight initializer")
            M,Kin=static_shape(shapes,node.input[0],2,"MatMul")
            W=as_i8_exact(init[node.input[1]],np,label+" weights")
            if W.ndim != 2: raise SystemExit("MatMul weight must be rank-2")
            K,N=map(int,W.shape)
            if Kin!=K: raise SystemExit(f"MatMul K mismatch: activation K={Kin}, weight K={K}")
            layers.append({"type":"matmul","M":M,"N":N,"K":K,"weights":flatten(W),"bias":[0]*N})
        elif op=="Gemm":
            if a.get("transA",0) or a.get("transB",0): raise SystemExit("Gemm transpose not supported")
            if float(a.get("alpha",1.0))!=1.0 or float(a.get("beta",1.0))!=1.0: raise SystemExit("Gemm alpha/beta other than 1 are not supported")
            if len(node.input)<2 or node.input[1] not in init: raise SystemExit("Gemm requires constant weights")
            M,Kin=static_shape(shapes,node.input[0],2,"Gemm")
            W=as_i8_exact(init[node.input[1]],np,label+" weights")
            if W.ndim!=2: raise SystemExit("Gemm weight must be rank-2")
            K,N=map(int,W.shape)
            if Kin!=K: raise SystemExit(f"Gemm K mismatch: activation K={Kin}, weight K={K}")
            bias=[0]*N
            if len(node.input)>2 and node.input[2] and node.input[2] not in init:
                raise SystemExit("Gemm requires constant bias when provided")
            if len(node.input)>2 and node.input[2] in init:
                b=as_i32_exact(init[node.input[2]],np,label+" bias").reshape(-1)
                if b.size!=N: raise SystemExit(f"Gemm bias length {b.size} != N {N}")
                bias=flatten(b)
            layers.append({"type":"matmul","M":M,"N":N,"K":K,"weights":flatten(W),"bias":bias})
        elif op=="Conv":
            check_spatial_attrs(op,a)
            if len(node.input)<2 or node.input[1] not in init: raise SystemExit("Conv requires constant weights")
            n,Cin,H,Wid=static_shape(shapes,node.input[0],4,"Conv")
            if n!=1: raise SystemExit("SNPU Conv converter currently requires batch size 1")
            W=as_i8_exact(init[node.input[1]],np,label+" weights")
            if W.ndim != 4: raise SystemExit("Only 2D Conv supported")
            O,Cpg,Kh,Kw=map(int,W.shape); groups=int(a.get("group",1))
            if groups < 1 or O % groups or Cin % groups or Cpg*groups!=Cin: raise SystemExit("Invalid/inconsistent Conv group count")
            strides=a.get("strides",[1,1]); pads=a.get("pads",[0,0,0,0]); dil=a.get("dilations",[1,1])
            if dil != [1,1]: raise SystemExit("Dilated Conv is not supported")
            if strides[0]!=strides[1] or pads[0]!=pads[1] or pads[2]!=pads[3] or pads[0]!=pads[2]:
                raise SystemExit("Only symmetric equal H/W stride/padding supported")
            W2=np.transpose(W,(0,2,3,1)).astype(np.int8,copy=False)
            bias=[0]*O
            if len(node.input)>2 and node.input[2] and node.input[2] not in init:
                raise SystemExit("Conv requires constant bias when provided")
            if len(node.input)>2 and node.input[2] in init:
                b=as_i32_exact(init[node.input[2]],np,label+" bias").reshape(-1)
                if b.size!=O: raise SystemExit(f"Conv bias length {b.size} != output channels {O}")
                bias=flatten(b)
            layers.append({"type":"conv2d","in_h":H,"in_w":Wid,"in_c":Cin,"out_c":O,
                           "groups":groups,"k_h":Kh,"k_w":Kw,"stride":int(strides[0]),"pad":int(pads[0]),
                           "weights":flatten(W2),"bias":bias})
        else:
            raise SystemExit("Unsupported ONNX operator: "+op)

    with open(args.output,"w") as f: json.dump({"layers":layers},f,indent=2)
    print(args.output)
if __name__=="__main__": main()
