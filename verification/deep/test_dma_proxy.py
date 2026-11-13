#!/usr/bin/env python3
"""Execute actual DMA proxy functions with pthread-backed kernel/API mocks.
Not a loaded-kernel or physical DMA test. Optional argument: source tree.
"""
from pathlib import Path
import subprocess,tempfile,sys,os
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parents[2]
s=(root/'sw/linux/npu_dma_proxy.c').read_text()
def function(name):
 start=s.index('static ',s.index('\n',s.index(' '+name+'(')-20)) if False else 0
 import re
 m=re.search(r'static [\w *]+\b'+name+r'\(',s);start=m.start();op=s.index('{',m.end());depth=1;i=op+1
 while depth:
  depth+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[start:i]+'\n'
prefix=r'''
#define _DEFAULT_SOURCE
#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <pthread.h>
#include <stdatomic.h>
#include <unistd.h>
#include <time.h>
#include <sys/ioctl.h>
#define __user
#define READ_ONCE(x) __atomic_load_n(&(x),__ATOMIC_ACQUIRE)
#define WRITE_ONCE(x,v) __atomic_store_n(&(x),(v),__ATOMIC_RELEASE)
#define container_of(ptr,type,member) ((type*)((char*)(ptr)-offsetof(type,member)))
#define DMA_PREP_INTERRUPT 1
#define DMA_CTRL_ACK 2
#define msecs_to_jiffies(x) (x)
#define ENOTSUPP EOPNOTSUPP
typedef uintptr_t dma_addr_t;
typedef int dma_cookie_t;
struct mutex {pthread_mutex_t p;};
static void mutex_init(struct mutex*m){pthread_mutex_init(&m->p,0);}
static void mutex_lock(struct mutex*m){pthread_mutex_lock(&m->p);}
static void mutex_unlock(struct mutex*m){pthread_mutex_unlock(&m->p);}
struct kref {int refs;};
static void kref_init(struct kref*k){k->refs=1;}
static void kref_get(struct kref*k){++k->refs;}
static void kref_put(struct kref*k,void(*fn)(struct kref*)){if(!--k->refs)fn(k);}
struct device {int refs;};
static void put_device(struct device*d){--d->refs;}
struct miscdevice {int unused;};
struct file {void*private_data;};struct inode {int unused;};
struct platform_device {void*data;struct device dev;};
static void* platform_get_drvdata(struct platform_device*p){return p->data;}
static void misc_deregister(struct miscdevice*m){(void)m;}
static int freed,terminated,released;
static void dma_free_coherent(struct device*d,size_t n,void*p,dma_addr_t a){(void)d;(void)n;(void)a;free(p);freed++;}
#define kfree free
#define THIS_MODULE NULL
#define __module_get(m) ((void)(m))
#define dev_err(...) ((void)0)
struct completion {pthread_mutex_t m;pthread_cond_t c;int done;};
static atomic_int waiting;
static void init_completion(struct completion*d){pthread_mutex_init(&d->m,0);pthread_cond_init(&d->c,0);d->done=0;}
static void reinit_completion(struct completion*d){d->done=0;}
static void complete(struct completion*d){pthread_mutex_lock(&d->m);d->done++;pthread_cond_signal(&d->c);pthread_mutex_unlock(&d->m);}
static int wait_for_completion_timeout(struct completion*d,int timeout){
 (void)timeout;struct timespec t;clock_gettime(CLOCK_REALTIME,&t);t.tv_nsec+=200000000;if(t.tv_nsec>=1000000000){t.tv_sec++;t.tv_nsec-=1000000000;}
 pthread_mutex_lock(&d->m);atomic_fetch_add(&waiting,1);
 while(!d->done){if(pthread_cond_timedwait(&d->c,&d->m,&t)==ETIMEDOUT){pthread_mutex_unlock(&d->m);return 0;}}
 d->done--;pthread_mutex_unlock(&d->m);return 1;
}
enum dma_transfer_direction {DMA_MEM_TO_DEV,DMA_DEV_TO_MEM};
enum dma_status {DMA_COMPLETE,DMA_IN_PROGRESS,DMA_ERROR};
struct dma_async_tx_descriptor {void(*callback)(void*);void*callback_param;};
struct dma_chan {struct dma_async_tx_descriptor desc;int cookie,status,terminate_error;};
static struct dma_async_tx_descriptor* dmaengine_prep_slave_single(struct dma_chan*c,dma_addr_t a,unsigned n,enum dma_transfer_direction d,int flags){(void)a;(void)n;(void)d;(void)flags;return &c->desc;}
static dma_cookie_t dmaengine_submit(struct dma_async_tx_descriptor*d){(void)d;return 1;}
static int dma_submit_error(dma_cookie_t c){return c<0?c:0;}
static void dma_async_issue_pending(struct dma_chan*c){c->cookie=1;}
static int dmaengine_terminate_sync(struct dma_chan*c){terminated++;return c->terminate_error;}
static void dma_release_channel(struct dma_chan*c){(void)c;released++;}
static enum dma_status dma_async_is_tx_complete(struct dma_chan*c,int cookie,void*a,void*b){(void)a;(void)b;assert(cookie==1);return c->status;}
static int copy_from_user(void*dst,const void*src,size_t n){memcpy(dst,src,n);return 0;}
'''
body=s[s.index('#define BUF_BYTES'):s.index('static int npu_mmap')]
# Keep function definitions needed for lifecycle, independently of file ordering.
for name in ['npu_open','npu_destroy','npu_quarantine','npu_release','npu_remove_common']:
 if ' '+name+'(' in s:body+=function(name)
modern='struct kref refs;' in s
setup='mutex_init(&d->tx_op_lock);mutex_init(&d->rx_op_lock);kref_init(&d->refs);d->tx_dev=d->rx_dev=dev;' if modern else ''
code=r'''
static struct npu_dma* setup(struct device*dev,struct dma_chan*tx,struct dma_chan*rx){
 struct npu_dma*d=calloc(1,sizeof(*d));d->dev=dev;d->tx=tx;d->rx=rx;mutex_init(&d->lock);init_completion(&d->tx_done);init_completion(&d->rx_done);
 SETUP
 d->tx_cpu=malloc(64);d->rx_cpu=malloc(64);return d;
}
struct waiter{struct file*f;long result;};
static void* run_wait(void*p){struct waiter*w=p;w->result=npu_ioctl(w->f,NPU_DMA_TX_WAIT,0);return 0;}
int main(void){
 struct device dev={100};struct dma_chan tx={0},rx={0};struct npu_dma*d=setup(&dev,&tx,&rx);struct file f={&d->misc};struct inode inode={0};unsigned len=16;
 assert(!npu_open(&inode,&f));assert(npu_open(&inode,&f)==-EBUSY);
 assert(npu_ioctl(&f,NPU_DMA_TX_WAIT,0)==-EINVAL);
 assert(!npu_ioctl(&f,NPU_DMA_TX_START,(uintptr_t)&len));
 assert(npu_ioctl(&f,NPU_DMA_TX_START,(uintptr_t)&len)==-EBUSY);
 struct waiter w1={&f,999},w2={&f,999};pthread_t t1,t2;
 pthread_create(&t1,0,run_wait,&w1);while(!atomic_load(&waiting))usleep(1000);
 pthread_create(&t2,0,run_wait,&w2);usleep(20000);
 tx.status=DMA_COMPLETE;tx.desc.callback(tx.desc.callback_param);
 pthread_join(t1,0);pthread_join(t2,0);
 if(w1.result!=0||w2.result!=-EINVAL){fprintf(stderr,"FAIL concurrent WAIT: %ld %ld (expected 0, %d)\n",w1.result,w2.result,-EINVAL);return 1;}
 puts("PASS concurrent WAIT serialization");
 assert(!npu_ioctl(&f,NPU_DMA_TX_START,(uintptr_t)&len));
 assert(npu_ioctl(&f,NPU_DMA_TX_WAIT,0)==-ETIMEDOUT);assert(!d->tx_pending);
 assert(!npu_ioctl(&f,NPU_DMA_TX_START,(uintptr_t)&len));tx.terminate_error=-EIO;
 assert(npu_ioctl(&f,NPU_DMA_TX_CANCEL,0)==-EIO);assert(d->tx_pending);tx.terminate_error=0;assert(!npu_ioctl(&f,NPU_DMA_TX_CANCEL,0));
 puts("PASS timeout recovery and failed-cancel pending retention");
 assert(!npu_ioctl(&f,NPU_DMA_TX_START,(uintptr_t)&len));
 assert(!npu_ioctl(&f,NPU_DMA_RX_START,(uintptr_t)&len));
 assert(!npu_ioctl(&f,NPU_DMA_RX_CANCEL,0));assert(d->tx_pending);assert(!npu_ioctl(&f,NPU_DMA_TX_CANCEL,0));
 puts("PASS independent TX/RX operation");
 struct platform_device pdev={.data=d};npu_remove_common(&pdev);
 assert(freed==0 && released==0);memset(d->rx_cpu,42,64);
 assert(npu_ioctl(&f,NPU_DMA_TX_START,(uintptr_t)&len)==-ENODEV);
 assert(!npu_release(&inode,&f));assert(freed==2&&released==2);
 puts("PASS remove retains allocations until final file release, removed ioctl rejected");
 d=setup(&dev,&tx,&rx);f.private_data=&d->misc;assert(!npu_open(&inode,&f));
 tx.terminate_error=-EIO;assert(npu_release(&inode,&f)==-EIO);assert(d->quarantined&&d->removed);assert(freed==2);
 pdev.data=d;npu_remove_common(&pdev);assert(freed==2);assert(d->refs.refs==1);
 puts("PASS failed close cancellation quarantines allocations and rejects reuse");return 0;
}
'''.replace('SETUP',setup)
if not modern:
 code=code[:code.index(' d=setup(&dev,&tx,&rx);f.private_data')]+"return 0;\n}\n"
with tempfile.TemporaryDirectory() as t:
 p=Path(t);(p/'test.c').write_text(prefix+body+code)
 subprocess.run(['gcc','-std=c11','-Wall','-Wextra','-Wno-unused-function','-Wno-unused-parameter','-pthread','-fsanitize=address,undefined','-g',str(p/'test.c'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True,timeout=10,env=dict(os.environ,ASAN_OPTIONS='detect_leaks=0'))
