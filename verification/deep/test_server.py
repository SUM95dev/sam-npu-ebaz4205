#!/usr/bin/env python3
"""Host socketpair tests of actual C server framing/validation, no board/ioctl."""
from pathlib import Path
import tempfile,subprocess,os
root=Path(__file__).resolve().parents[2]
code=r'''
#define main npu_server_program_main
#include "SOURCE"
#undef main
#include <assert.h>
static uint32_t fake_regs[1024];
static int query(struct req_hdr_wire *h,const void *body,unsigned bytes,int expected){
 int f[2];uint8_t tx[256],rx[256];assert(!socketpair(AF_UNIX,SOCK_STREAM,0,f));
 assert(!send_all(f[0],h,sizeof(*h)));if(bytes)assert(!send_all(f[0],body,bytes));
 int rc=handle_client(f[1],-1,tx,rx);struct rep_hdr_wire rep;assert(!recv_all(f[0],&rep,sizeof(rep)));
 assert(!memcmp(rep.magic,"SNPR",4));assert(rep.request_id_be==h->request_id_be);assert((int32_t)ntohl(rep.status_be)==expected);
 if(expected==0){uint32_t info[7];assert(rc==0);assert(ntohl(rep.output_bytes_be)==sizeof(info));assert(!recv_all(f[0],info,sizeof(info)));assert(ntohl(info[0])==0x20000);}
 else {assert(rc==-1);assert(ntohl(rep.output_bytes_be)==0);}
 close(f[0]);close(f[1]);return 1;
}
static struct req_hdr_wire header(unsigned op,unsigned in,unsigned out){
 struct req_hdr_wire h={0};memcpy(h.magic,"SNPU",4);h.version_be=htons(1);h.opcode_be=htons(op);h.m_be=h.n_be=h.k_be=htons(1);h.input_bytes_be=htonl(in);h.output_bytes_be=htonl(out);h.request_id_be=htonl(123);h.qmul_be=htonl(1);return h;
}
int main(void){
 regs=fake_regs;fake_regs[REG_CAPS/4]=255;fake_regs[REG_VERSION/4]=0x20000;
 struct req_hdr_wire h=header(OP_INFO,0,0);int tests=query(&h,0,0,0);
 h.magic[0]='!';tests+=query(&h,0,0,-10);h=header(99,16,4);tests+=query(&h,0,0,-11);
 h=header(OP_INFO,16,0);tests+=query(&h,0,0,-11);
 h=header(OP_ADD,16,4);h.qshift=64;tests+=query(&h,0,0,-11);
 h=header(OP_CONV,16,4);h.flags_be=htons(FLAG_MATMUL_BIAS);tests+=query(&h,0,0,-11);
 h=header(OP_MATMUL,16,4);tests+=query(&h,0,0,-12);
 h=header(OP_MAXPOOL,16,4);tests+=query(&h,0,0,-12);
 h=header(OP_ADD,32,4);tests+=query(&h,0,0,-12);
 uint8_t badconv[16]={0};h=header(OP_CONV,16,4);tests+=query(&h,badconv,16,-13);
 fake_regs[REG_CAPS/4]=0;h=header(OP_ADD,16,4);tests+=query(&h,0,0,-14);
 unsigned max=131071;uint8_t *payload=calloc(max+1,16);assert(payload);
 payload[(max-1)*16+2]=1;assert(validate_conv_payload(payload,max*16,4)==0);
 payload[(max-1)*16+2]=0;payload[max*16+2]=1;assert(validate_conv_payload(payload,(max+1)*16,4)<0);
 assert(validate_conv_payload(payload,15,4)<0);assert(validate_conv_payload(payload,16,3)<0);free(payload);
 printf("PASS %d C server socketpair requests, Conv 131071/131072 MAC boundary and malformed lengths\n",tests);return 0;
}
'''.replace('SOURCE',str(root/'sw/linux/npu_net_server.c'))
with tempfile.TemporaryDirectory() as t:
 p=Path(t);(p/'test.c').write_text(code)
 subprocess.run(['gcc','-std=c11','-D_DEFAULT_SOURCE','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-g',str(p/'test.c'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True,timeout=10,env=dict(os.environ,ASAN_OPTIONS='detect_leaks=0'))
