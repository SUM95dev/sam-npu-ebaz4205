#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define MAP_SIZE 0x1000
#define REG_CTRL   0x00
#define REG_M      0x04
#define REG_N      0x08
#define REG_K      0x0C
#define REG_ACT    0x10
#define REG_CMD    0x14
#define REG_QMUL   0x18
#define REG_QSHIFT 0x1C
#define REG_ZP     0x20
#define REG_VERSION 0x24
#define REG_CAPS    0x28
#define REG_LASTJOB 0x3C

static volatile uint32_t *regs;

static inline void wr(unsigned off, uint32_t v){ regs[off>>2]=v; }
static inline uint32_t rd(unsigned off){ return regs[off>>2]; }

int main(int argc,char **argv){
    const char *dev = "/dev/uio0";
    int do_abort = 0;
    for (int i=1; i<argc; ++i) {
        if (strcmp(argv[i], "--abort") == 0) do_abort = 1;
        else if (argv[i][0] == '-') {
            fprintf(stderr, "usage: %s [/dev/uioX] [--abort]\n", argv[0]);
            return 2;
        } else dev = argv[i];
    }

    int fd=open(dev,O_RDWR|O_SYNC);
    if(fd<0){perror("open uio");return 1;}
    regs=mmap(NULL,MAP_SIZE,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
    if(regs==MAP_FAILED){perror("mmap");close(fd);return 2;}

    uint32_t ctrl = rd(REG_CTRL);
    printf("NPU hw version=0x%08x caps=0x%08x ctrl=0x%08x last_job_cycles=%u\n",
           rd(REG_VERSION), rd(REG_CAPS), ctrl, rd(REG_LASTJOB));
    printf("status: busy=%u done=%u cfg_error=%u irq_pending=%u\n",
           ctrl&1u, (ctrl>>1)&1u, (ctrl>>2)&1u, (ctrl>>3)&1u);

    /* Safe diagnostic by default: never START a datapath without DMA armed. */
    if (do_abort) {
        wr(REG_CMD, (rd(REG_CMD)&1u) | (1u<<4));
        printf("hardware abort requested\n");
    }

    munmap((void*)regs,MAP_SIZE);
    close(fd);
    return 0;
}
