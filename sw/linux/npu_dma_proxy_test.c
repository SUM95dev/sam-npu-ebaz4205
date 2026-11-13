#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#define BUF_BYTES (4*1024*1024)
#define NPU_DMA_IOC_MAGIC 'N'
#define NPU_DMA_TX_START _IOW(NPU_DMA_IOC_MAGIC, 3, unsigned int)
#define NPU_DMA_RX_START _IOW(NPU_DMA_IOC_MAGIC, 4, unsigned int)
#define NPU_DMA_TX_WAIT  _IO(NPU_DMA_IOC_MAGIC, 5)
#define NPU_DMA_RX_WAIT  _IO(NPU_DMA_IOC_MAGIC, 6)
#define NPU_DMA_TX_CANCEL _IO(NPU_DMA_IOC_MAGIC, 7)
#define NPU_DMA_RX_CANCEL _IO(NPU_DMA_IOC_MAGIC, 8)

int main(int argc,char **argv)
{
    const char *dev=argc>1?argv[1]:"/dev/npu_dma";
    int fd=open(dev,O_RDWR);
    if(fd<0){perror("open");return 1;}

    uint8_t *tx=mmap(NULL,BUF_BYTES,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
    uint8_t *rx=mmap(NULL,BUF_BYTES,PROT_READ|PROT_WRITE,MAP_SHARED,fd,BUF_BYTES);
    if(tx==MAP_FAILED||rx==MAP_FAILED){perror("mmap");return 2;}

    unsigned tx_len=1024, rx_len=1024;
    for(unsigned i=0;i<tx_len;i++) tx[i]=(uint8_t)i;

    /* Safe smoke test: prove both asynchronous submissions can be armed, then
       cancel them before unmapping the coherent buffers.  Full transfer tests
       should use npu_net_server, which starts the NPU between START and WAIT. */
    if(ioctl(fd,NPU_DMA_RX_START,&rx_len)<0) { perror("rx start"); return 3; }
    if(ioctl(fd,NPU_DMA_TX_START,&tx_len)<0) {
        perror("tx start");
        (void)ioctl(fd,NPU_DMA_RX_CANCEL);
        return 4;
    }
    puts("DMA async arm PASS; cancelling smoke-test transfers safely.");
    (void)ioctl(fd,NPU_DMA_TX_CANCEL);
    (void)ioctl(fd,NPU_DMA_RX_CANCEL);

    munmap(tx,BUF_BYTES); munmap(rx,BUF_BYTES); close(fd);
    return 0;
}
