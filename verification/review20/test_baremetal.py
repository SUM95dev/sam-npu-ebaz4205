#!/usr/bin/env python3
"""Host mocks check sequencing/recovery; not an actual Xilinx BSP build."""
from pathlib import Path
import tempfile,subprocess
root=Path(__file__).resolve().parents[2]
headers={
'xparameters.h':'#define XPAR_NPU_AXIS_SYSTEM_TOP_0_S_AXI_BASEADDR 0\n',
'xil_io.h':'#include <stdint.h>\ntypedef uintptr_t UINTPTR;\nvoid Xil_Out32(UINTPTR,uint32_t);\nuint32_t Xil_In32(UINTPTR);\n',
'xil_cache.h':'void Xil_DCacheFlushRange(UINTPTR,uint32_t);\nvoid Xil_DCacheInvalidateRange(UINTPTR,uint32_t);\n',
'xaxidma.h':'typedef struct { int unused; } XAxiDma;\n#define XST_SUCCESS 0\n#define XAXIDMA_DEVICE_TO_DMA 1\n#define XAXIDMA_DMA_TO_DEVICE 0\nint XAxiDma_SimpleTransfer(XAxiDma*,UINTPTR,uint32_t,int);\nint XAxiDma_Busy(XAxiDma*,int);\nvoid XAxiDma_Reset(XAxiDma*);\nint XAxiDma_ResetIsDone(XAxiDma*);\n'}
code=r'''
#include <assert.h>
#include "SOURCE"
static int scenario,started,reset_count,polls,invalidated,submitted;
void Xil_Out32(UINTPTR a,uint32_t v){if(a==REG_CTRL && v==1)started=1;}
uint32_t Xil_In32(UINTPTR a){return a==REG_CTRL && started ? (scenario==3?0:2):0;}
void Xil_DCacheFlushRange(UINTPTR a,uint32_t n){(void)a;(void)n;}
void Xil_DCacheInvalidateRange(UINTPTR a,uint32_t n){(void)a;(void)n;assert(polls>=3);invalidated++;}
int XAxiDma_SimpleTransfer(XAxiDma*d,UINTPTR a,uint32_t n,int dir){(void)d;(void)a;(void)n;assert(dir==(submitted==0?1:0));submitted++;return (scenario==1&&dir==1)||(scenario==2&&dir==0);}
int XAxiDma_Busy(XAxiDma*d,int dir){(void)d;(void)dir;if(!started)return 0;polls++;return scenario==4||polls<3;}
void XAxiDma_Reset(XAxiDma*d){(void)d;reset_count++;}
int XAxiDma_ResetIsDone(XAxiDma*d){(void)d;return scenario!=5;}
int main(void){
 XAxiDma dma;uint8_t feed[128]={0};uint32_t result[1];
 for(scenario=0;scenario<=5;scenario++){
  started=reset_count=polls=invalidated=submitted=0;
  int rc=run_matmul(&dma,feed,128,result,4,1,1,1);
  if(scenario==0||scenario==5){assert(rc==0);assert(invalidated==1);assert(reset_count==0);}
  else {assert(rc<0);assert(reset_count==1);assert(invalidated==0);}
 }
 scenario=5;started=reset_count=polls=invalidated=submitted=0;
 /* A stuck reset is reported separately. */
 assert(npu_cancel_dma(&dma,-1)==-6);
 assert(run_matmul(&dma,feed,16,result,4,1,1,1)==-7);
 puts("PASS baremetal DMA completion, submit failures, NPU/DMA timeouts, reset failure, buffer size");return 0;
}
'''
with tempfile.TemporaryDirectory() as t:
 p=Path(t)
 for name,body in headers.items():(p/name).write_text(body)
 (p/'test.c').write_text(code.replace('SOURCE',str(root/'sw/npu_baremetal_example.c')))
 subprocess.run(['gcc','-std=c11','-Wall','-Wextra','-Werror','-DNPU_POLL_LIMIT=16','-I',str(p),str(p/'test.c'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
