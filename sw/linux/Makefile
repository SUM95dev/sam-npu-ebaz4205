obj-m += npu_dma_proxy.o

KDIR ?= /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)
CC ?= gcc
CFLAGS_USER ?= -O2 -Wall -Wextra

all: modules userspace

modules:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

userspace: npu_net_server npu_dma_proxy_test npu_uio

npu_net_server: npu_net_server.c
	$(CC) $(CFLAGS_USER) $< -o $@

npu_dma_proxy_test: npu_dma_proxy_test.c
	$(CC) $(CFLAGS_USER) $< -o $@

npu_uio: npu_uio.c
	$(CC) $(CFLAGS_USER) $< -o $@

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
	rm -f npu_net_server npu_dma_proxy_test npu_uio
