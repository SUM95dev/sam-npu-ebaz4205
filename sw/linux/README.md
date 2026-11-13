# Linux runtime

The minimal path uses UIO for the NPU control register aperture.

1. Reserve/map the NPU AXI-Lite address in Vivado (example 0x43C00000).
2. Add `npu-uio.dtsi` to the device tree, adjusting the address if needed.
3. Enable `uio_pdrv_genirq`. Preserve the board's existing kernel command line;
   append `uio_pdrv_genirq.of_id=generic-uio` if your kernel requires that
   module parameter. The DTS fragment intentionally does not overwrite `/chosen/bootargs`.
4. Compile:
   `gcc -O2 npu_uio.c -o npu_uio`
5. Run as root:
   `./npu_uio /dev/uio0`

For bulk DDR transfers use AXI DMA with a Linux DMA driver or a userspace DMA buffer framework.
UIO here controls the NPU; it does not pretend to replace a proper DMA driver.


## DMA proxy bring-up

`npu_dma_proxy.c` is included as a minimal DMAengine test driver. It requests
two DMA channels named `tx` and `rx`, allocates coherent TX/RX buffers, exposes
them with mmap, and provides synchronous ioctls for DMA submit/wait.

This is for board bring-up and validation, not a production security-hardened ABI.

Files:
- `npu_dma_proxy.c`
- `npu_dma_proxy_test.c`
- `npu-dma-proxy.dtsi`
- `Makefile`

## Ethernet accelerator mode

The release now contains a TCP front-end for using the EBAZ4205 as a dedicated
network NPU board:

- `npu_net_server.c` - TCP server on port 9505
- `../host/npu_net_client.py` - PC/main-board client
- `configure_npu_eth.sh` - direct-link static-IP helper
- `ebaz4205-gem0.dtsi` - optional GEM0 device-tree template
- `npu-net.service` - optional systemd unit

The DMA proxy now has asynchronous START/WAIT ioctls so RX/S2MM can be armed
before the NPU starts, avoiding the deadlock possible with a purely synchronous
proxy. See `docs/ETHERNET_NPU.md` for the full bring-up sequence.
