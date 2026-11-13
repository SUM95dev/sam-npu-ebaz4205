#!/usr/bin/env python3
"""TCP client/runtime helpers for the Sam NPU EBAZ4205 network accelerator."""
from operator import index as integer

import argparse, json, socket, struct
from pathlib import Path
import sys

# The host-side spatial lowering is shared with the standalone Conv packer.
_THIS_FILE = globals().get("__file__")
_SW_DIR = Path(_THIS_FILE).resolve().parents[1] if _THIS_FILE else (Path.cwd() / "sw")
if str(_SW_DIR) not in sys.path:
    sys.path.insert(0, str(_SW_DIR))
from pack_conv_stream import pack_conv_nhwc

MAGIC=b"SNPU"; VERSION=1
OP_INFO=0; OP_MATMUL=1; OP_CONV=2; OP_MAXPOOL=3; OP_ADD=4
FLAG_RELU=1; FLAG_MATMUL_BIAS=2
REQ=struct.Struct("!4sHHHHHHiBbhIII")
REP=struct.Struct("!4sIiI")
INFO=struct.Struct("!7I")

def recv_exact(s,n):
    b=bytearray()
    while len(b)<n:
        x=s.recv(n-len(b))
        if not x: raise ConnectionError("connection closed")
        b+=x
    return bytes(b)

def as_i8(v,label="value"):
    v=integer(v)
    if v < -128 or v > 127:
        raise ValueError(f"{label}={v} is outside signed INT8 range")
    return v

def as_i32(v,label="value"):
    v=integer(v)
    if v < -(1<<31) or v > (1<<31)-1:
        raise ValueError(f"{label}={v} is outside signed INT32 range")
    return v

def pack_matmul(A,B,tile=8,bias=None):
    if tile != 8: raise ValueError("EBAZ4205 release hardware uses a fixed 8x8 tile")
    if not A or not B or not A[0] or not B[0]:
        raise ValueError("A and B must be non-empty matrices")
    M=len(A); K=len(A[0]); N=len(B[0])
    if any(len(row) != K for row in A): raise ValueError("A is ragged")
    if len(B) != K or any(len(row) != N for row in B): raise ValueError("B shape must be KxN and non-ragged")
    if M > 65535 or N > 65535 or K > 65535: raise ValueError("M/N/K exceed 16-bit hardware register limits")
    if bias is not None and len(bias)!=N: raise ValueError("bias length must equal N")
    out=bytearray()
    for tm in range((M+tile-1)//tile):
      for tn in range((N+tile-1)//tile):
        if bias is not None:
          cols=[as_i32(bias[tn*tile+c],f"bias[{tn*tile+c}]") if tn*tile+c<N else 0 for c in range(tile)]
          for base in range(0,tile,4):
            chunk=cols[base:base+4]+[0]*max(0,4-len(cols[base:base+4]))
            out += struct.pack("<4i",*chunk[:4])
        for step in range(K+tile-1):
          for r in range(tile):
            row=tm*tile+r; k=step-r
            out += struct.pack("b",as_i8(A[row][k],f"A[{row}][{k}]") if row<M and 0<=k<K else 0)
          for c in range(tile):
            col=tn*tile+c; k=step-c
            out += struct.pack("b",as_i8(B[k][col],f"B[{k}][{col}]") if col<N and 0<=k<K else 0)
    return bytes(out),(M,N,K)

def pack_add(a,b):
    if len(a)!=len(b) or not a: raise ValueError("A and B vectors must have equal non-zero length")
    out=bytearray()
    for i,(x,y) in enumerate(zip(a,b)): out += struct.pack('<bb14x',as_i8(x,f'A[{i}]'),as_i8(y,f'B[{i}]'))
    return bytes(out)

def pack_pool_groups(groups):
    out=bytearray()
    for g in groups:
        if len(g)!=4: raise ValueError("each MaxPool2x2 group must contain exactly four INT8 values")
        for j,v in enumerate(g): out += struct.pack('<b15x',as_i8(v,f'pool[{j}]'))
    if not out: raise ValueError("at least one pool group is required")
    return bytes(out)

class NpuSession:
    """Persistent TCP session. The server supports multiple requests/connection.

    Reusing one connection removes TCP connect/teardown cost from layer-by-layer
    execution and makes benchmark latency representative of accelerator service
    time rather than socket setup time.
    """
    def __init__(self,host,port=9505,timeout=10):
        self.host=host; self.port=port; self.timeout=timeout; self.sock=None; self._next_id=1
    def connect(self):
        if self.sock is None:
            sock=socket.create_connection((self.host,self.port),timeout=self.timeout)
            try:
                sock.settimeout(self.timeout)
            except Exception:
                sock.close()
                raise
            self.sock=sock
        return self
    def conv_nhwc(self, input_nhwc, weights_ohwi, stride=1, pad=0, groups=1,
                  bias=None, relu=False, qmul=1, qshift=0, zp=0):
        """Run a complete spatial Conv2D lowered to the streaming MAC engine.

        The ARM/host packs NHWC windows into the hardware's 16-byte MAC beats;
        the PL performs the INT8 dot products, bias and post-processing.
        Returns (signed_INT8_flat_output, (out_h, out_w, out_channels)).
        """
        payload, shape = pack_conv_nhwc(
            input_nhwc, weights_ohwi, stride=stride, pad=pad, groups=groups, bias=bias
        )
        out_bytes = shape[0] * shape[1] * shape[2] * 4
        raw = self.request(OP_CONV, payload=payload, out_bytes=out_bytes,
                           relu=relu, qmul=qmul, qshift=qshift, zp=zp)
        return decode_i8_words(raw), shape

    def close(self):
        if self.sock is not None:
            try: self.sock.close()
            finally: self.sock=None
    def __enter__(self): return self.connect()
    def __exit__(self,*_): self.close()
    def request(self,opcode,M=0,N=0,K=0,payload=b'',out_bytes=0,relu=False,qmul=1,qshift=0,zp=0,request_id=None,extra_flags=0):
        qshift=integer(qshift)
        if not (0 <= qshift <= 63): raise ValueError("qshift must be 0..63")
        as_i8(zp,"zero_point")
        as_i32(qmul,"qmul")
        if request_id is None:
            request_id=self._next_id; self._next_id=(self._next_id+1)&0xffffffff or 1
        flags=(FLAG_RELU if relu else 0) | integer(extra_flags)
        hdr=REQ.pack(MAGIC,VERSION,opcode,M,N,K,flags,int(qmul),int(qshift),int(zp),0,len(payload),out_bytes,request_id)
        try:
            self.connect()
            self.sock.sendall(hdr)
            if payload: self.sock.sendall(payload)
            rep=recv_exact(self.sock,REP.size)
            magic,rid,status,n=REP.unpack(rep)
            if magic!=b"SNPR" or rid!=request_id: raise RuntimeError("bad reply header")
            if status!=0: raise RuntimeError(f"NPU server status {status}")
            expected = INFO.size if opcode == OP_INFO else out_bytes
            if n != expected:
                raise RuntimeError(f"unexpected reply size {n}, expected {expected}")
            return recv_exact(self.sock,n)
        except Exception:
            self.close()
            raise

def request(host,port=9505,opcode=OP_INFO,M=0,N=0,K=0,payload=b'',out_bytes=0,relu=False,qmul=1,qshift=0,zp=0,request_id=1,extra_flags=0):
    s=NpuSession(host,port)
    try:
        return s.request(opcode,M,N,K,payload,out_bytes,relu,qmul,qshift,zp,request_id,extra_flags)
    finally:
        s.close()

def decode_i8_words(result):
    if len(result)%4: raise ValueError("result length is not 32-bit-word aligned")
    vals=[]
    for i in range(0,len(result),4):
        w=struct.unpack_from('<I',result,i)[0]
        v=w & 0xff
        vals.append(v-256 if v>=128 else v)
    return vals

def parse_info(blob):
    if len(blob)!=INFO.size: raise RuntimeError(f"unexpected INFO size {len(blob)}")
    ver,caps,total,busy,jobs,errors,last=INFO.unpack(blob)
    return {"version":ver,"caps":caps,"total_cycles":total,"busy_cycles":busy,"jobs":jobs,"errors":errors,"last_job_cycles":last,
            "array_n":(caps>>8)&0xff,"data_w":(caps>>16)&0xff,"acc_w":(caps>>24)&0xff}

def print_info(blob):
    x=parse_info(blob); ver=x['version']; caps=x['caps']
    major,minor=ver>>16,ver&0xffff
    flags=[]
    for bit,name in [(0,'matmul'),(1,'conv'),(2,'maxpool2x2'),(3,'add'),(4,'conv_bias'),(5,'irq'),(6,'abort'),(7,'matmul_bias')]:
        if caps&(1<<bit): flags.append(name)
    print(f"hardware v{major}.{minor} array={x['array_n']}x{x['array_n']} data={x['data_w']}-bit acc={x['acc_w']}-bit")
    print("capabilities:",", ".join(flags))
    print(f"cycles total={x['total_cycles']} busy={x['busy_cycles']} jobs={x['jobs']} errors={x['errors']} last_job={x['last_job_cycles']}")

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("host"); ap.add_argument("--port",type=int,default=9505)
    ap.add_argument("--relu",action="store_true")
    ap.add_argument("--qmul",type=int,default=1); ap.add_argument("--qshift",type=int,default=0); ap.add_argument("--zp",type=int,default=0)
    sub=ap.add_subparsers(dest="cmd",required=True)
    sub.add_parser("info")
    mm=sub.add_parser("matmul"); mm.add_argument("json_file"); mm.add_argument("-o","--output",default="npu_result.bin")
    add=sub.add_parser("add"); add.add_argument("json_file"); add.add_argument("-o","--output",default="npu_add.bin")
    pool=sub.add_parser("maxpool"); pool.add_argument("json_file"); pool.add_argument("-o","--output",default="npu_pool.bin")
    conv=sub.add_parser("conv"); conv.add_argument("json_file"); conv.add_argument("-o","--output",default="npu_conv.bin")
    conv.add_argument("--stride",type=int,default=None); conv.add_argument("--pad",type=int,default=None); conv.add_argument("--groups",type=int,default=None)
    raw=sub.add_parser("raw"); raw.add_argument("input_file"); raw.add_argument("--opcode",choices=["matmul","conv","maxpool","add"],required=True); raw.add_argument("--m",type=int,default=0); raw.add_argument("--n",type=int,default=0); raw.add_argument("--k",type=int,default=0); raw.add_argument("--output-bytes",type=int,required=True); raw.add_argument("-o","--output",default="npu_result.bin")
    a=ap.parse_args()

    if a.cmd=="info": print_info(request(a.host,a.port,OP_INFO)); return
    extra_flags=0
    if a.cmd=="matmul":
        d=json.load(open(a.json_file)); bias=d.get("bias"); payload,(M,N,K)=pack_matmul(d["A"],d["B"],bias=bias)
        out_bytes=M*N*4; opcode=OP_MATMUL; outfile=a.output; extra_flags=FLAG_MATMUL_BIAS if bias is not None else 0
    elif a.cmd=="add":
        d=json.load(open(a.json_file)); payload=pack_add(d["A"],d["B"])
        M=N=K=0; out_bytes=len(d["A"])*4; opcode=OP_ADD; outfile=a.output
    elif a.cmd=="conv":
        d=json.load(open(a.json_file))
        stride=d.get("stride",1) if a.stride is None else a.stride
        pad=d.get("pad",0) if a.pad is None else a.pad
        groups=d.get("groups",1) if a.groups is None else a.groups
        payload,shape=pack_conv_nhwc(d["input"],d["weights"],stride,pad,groups,d.get("bias"))
        M=N=K=0; out_bytes=shape[0]*shape[1]*shape[2]*4; opcode=OP_CONV; outfile=a.output
    elif a.cmd=="maxpool":
        d=json.load(open(a.json_file)); groups=d.get("groups")
        if groups is None:
            vals=d["values"]
            if len(vals)%4: raise ValueError("values length must be divisible by four")
            groups=[vals[i:i+4] for i in range(0,len(vals),4)]
        payload=pack_pool_groups(groups); M=N=K=0; out_bytes=len(groups)*4; opcode=OP_MAXPOOL; outfile=a.output
    else:
        payload=open(a.input_file,"rb").read(); M,N,K=a.m,a.n,a.k
        out_bytes=a.output_bytes; opcode={"matmul":OP_MATMUL,"conv":OP_CONV,"maxpool":OP_MAXPOOL,"add":OP_ADD}[a.opcode]; outfile=a.output

    result=request(a.host,a.port,opcode,M,N,K,payload,out_bytes,a.relu,a.qmul,a.qshift,a.zp,extra_flags=extra_flags)
    open(outfile,"wb").write(result)
    print(f"received {len(result)} bytes -> {outfile}")
    print("INT8 postprocessed results:",decode_i8_words(result))
    if a.cmd=="conv": print("Conv output shape (H,W,C):",shape)

if __name__=="__main__": main()
