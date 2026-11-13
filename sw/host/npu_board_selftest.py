#!/usr/bin/env python3
"""End-to-end bring-up self-test for the Sam NPU network accelerator.

Use --dry-run anywhere to validate all packet builders and golden expectations.
Without --dry-run it checks INFO, MatMul, Add, MaxPool, Conv+bias and depthwise
Conv over TCP against exact golden results.
"""
import argparse, sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
SW=HERE.parent
sys.path.insert(0,str(HERE)); sys.path.insert(0,str(SW))
import npu_net_client as cli
from pack_conv_stream import pack_conv_nhwc

def decode(blob): return cli.decode_i8_words(blob)
def expect(name,got,want):
    if list(got)!=list(want): raise RuntimeError(f'{name}: got {got}, expected {want}')
    print(f'PASS {name}: {got}')

def make_vectors():
    A=[[1,2],[3,4]]; B=[[5,6],[7,8]]; mm_bias=[1,-2]
    mm_payload,(M,N,K)=cli.pack_matmul(A,B,bias=mm_bias)
    add_A=[120,-5,-100]; add_B=[20,2,-50]; add_payload=cli.pack_add(add_A,add_B)
    groups=[[1,7,-2,5],[-3,-8,-1,-6]]; pool_payload=cli.pack_pool_groups(groups)

    inp=[[[2,3]]]
    w=[[[[2,3]]],[[[-1,4]]]]
    conv_payload,conv_shape=pack_conv_nhwc(inp,w,groups=1,bias=[5,-2])

    dw_w=[[[[4]]],[[[5]]]]
    dw_payload,dw_shape=pack_conv_nhwc(inp,dw_w,groups=2,bias=[1,-1])
    return {
      'mm':(mm_payload,(M,N,K),[20,20,44,48]),
      'add':(add_payload,[127,-3,-128]),
      'pool':(pool_payload,[7,-1]),
      'conv':(conv_payload,conv_shape,[18,8]),
      'dw':(dw_payload,dw_shape,[9,14]),
    }

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('host',nargs='?',default='192.168.50.2'); ap.add_argument('--port',type=int,default=9505); ap.add_argument('--dry-run',action='store_true')
    a=ap.parse_args(); v=make_vectors()
    print('packet bytes:',{k:len(x[0]) for k,x in v.items()})
    if a.dry_run:
        print('PASS dry-run packet/golden construction'); return

    info=cli.request(a.host,a.port,cli.OP_INFO); cli.print_info(info)
    p,(M,N,K),want=v['mm']; r=cli.request(a.host,a.port,cli.OP_MATMUL,M,N,K,p,M*N*4,extra_flags=cli.FLAG_MATMUL_BIAS); expect('matmul',decode(r),want)
    p,want=v['add']; r=cli.request(a.host,a.port,cli.OP_ADD,payload=p,out_bytes=len(want)*4); expect('add',decode(r),want)
    p,want=v['pool']; r=cli.request(a.host,a.port,cli.OP_MAXPOOL,payload=p,out_bytes=len(want)*4); expect('maxpool',decode(r),want)
    p,shape,want=v['conv']; r=cli.request(a.host,a.port,cli.OP_CONV,payload=p,out_bytes=len(want)*4); expect('conv+bias',decode(r),want)
    p,shape,want=v['dw']; r=cli.request(a.host,a.port,cli.OP_CONV,payload=p,out_bytes=len(want)*4); expect('depthwise conv',decode(r),want)
    print('ALL HARDWARE NETWORK SELF-TESTS PASS')
if __name__=='__main__': main()
