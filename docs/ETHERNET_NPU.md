# Sam NPU as a network accelerator on EBAZ4205

## Final data path

```text
PC or main EBAZ4205
       |
       | 100BASE-T Ethernet / TCP
       v
EBAZ4205 NPU board: IP101GA PHY
       |
       | PS GEM0 via EMIO/MII
       v
Cortex-A9 / Linux TCP server
       |
       | copy into coherent DMA buffer
       v
DDR / AXI DMA MM2S -> Sam NPU -> AXI DMA S2MM
       |
       v
TCP reply -> PC/main board
```

Ethernet is the inter-board transport. AXI-Stream remains the internal high-speed
transport between AXI DMA and the NPU.

## Hardware integration

The EBAZ4205 PS preset enables GEM0 and MDIO through EMIO. The NPU Vivado flow
now exports the Ethernet pins and uses a known-working EBAZ4205 4-bit MII
mapping:

- RX clock: U14
- TX clock: U15
- RXD[3:0]: Y17, V17, V16, Y16
- RX_DV: W16
- TXD[3:0]: W18, Y18, V18, Y19
- TX_EN: W19
- MDC: W15
- MDIO: Y14

The Zynq PS exposes an 8-bit GMII data bus. The board PHY uses four data bits at
100 Mbps, so the BD pads RX[7:4] with zero and slices TX[3:0].

## Direct cable addressing

For a direct PC/main-board <-> NPU-board link, a router is not required.
Suggested addresses:

- PC/main board: `192.168.50.1/24`
- NPU board: `192.168.50.2/24`
- TCP NPU service: port `9505`

On the NPU Linux system:

```sh
ip link set eth0 up
ip addr flush dev eth0
ip addr add 192.168.50.2/24 dev eth0
```

On a Linux PC/main EBAZ:

```sh
sudo ip link set eth0 up
sudo ip addr flush dev eth0
sudo ip addr add 192.168.50.1/24 dev eth0
ping 192.168.50.2
```

If using a switch/router instead, use addresses valid for that LAN or DHCP.

## Linux device tree

The hardware handoff/XSA should expose GEM0 because the PS board preset enables
ENET0 on EMIO. For a custom Linux/PetaLinux device tree, merge the template in
`sw/linux/ebaz4205-gem0.dtsi` if GEM0 is not already enabled. Do not duplicate a
PHY node that your generated device tree already contains.

The NPU also needs:

- `sw/linux/npu-uio.dtsi` for the AXI-Lite register aperture
- `sw/linux/npu-dma-proxy.dtsi` for AXI DMA channels

## Build the runtime

On the target Linux system:

```sh
gcc -O2 -Wall npu_net_server.c -o npu_net_server
```

Build/load `npu_dma_proxy.ko` for the running target kernel and ensure:

```text
/dev/uio0
/dev/npu_dma
eth0
```

exist.

Start the accelerator server:

```sh
./npu_net_server 9505 /dev/uio0 /dev/npu_dma
```

## Host test

For MatMul, input JSON is the same format accepted by `pack_matmul_stream.py`:

```json
{"A":[[1,2],[3,4]], "B":[[5,6],[7,8]]}
```

From the PC/main board:

```sh
python3 sw/host/npu_net_client.py 192.168.50.2 --relu matmul matrix.json
```

The client packs the systolic feed, sends it over TCP, and receives the NPU
output. MatMul accumulation is INT32 internally, then the shared postprocessor applies
bias/requantization/ReLU/zero-point and saturates to INT8. Each final INT8 result
is sign-extended into one 32-bit AXI output word because `M_AXIS_OUT` is 32 bits.

For already-packed data:

```sh
python3 sw/host/npu_net_client.py 192.168.50.2 raw input.bin \
  --opcode matmul --m 8 --n 8 --k 8 --output-bytes 256 -o result.bin
```

Conv uses the corrected 128-bit DMA stream format from `pack_conv_stream.py`:
one Conv sample occupies one 16-byte DMA beat. Use the raw client and set
`--opcode conv` plus the exact expected output byte count.


## Final v2 network operations

The current server/client protocol keeps the same v1 wire header but exposes five opcodes:

- `0`: INFO / hardware telemetry
- `1`: MatMul
- `2`: streaming Conv (including grouped/depthwise packing and per-output INT32 bias)
- `3`: MaxPool2x2
- `4`: elementwise INT8 Add / residual

Useful commands:

```sh
python3 sw/host/npu_net_client.py 192.168.50.2 info
python3 sw/host/npu_board_selftest.py 192.168.50.2
```

The board self-test covers MatMul with streamed Dense bias, Add, MaxPool, Conv+bias and depthwise Conv.
`--dry-run` validates all host packet builders without requiring hardware.

## TCP protocol

Request header is 36 bytes in network byte order, followed by the packed input
payload. It includes operation, M/N/K, ReLU flag, quantization parameters,
input size, output size, and request ID. Reply header is 16 bytes, followed by
output bytes on success.

TCP was selected instead of SPI or UDP for the first network release because it
provides reliable ordered transport and works directly from a PC or another
Linux EBAZ4205. A later performance release can add UDP/raw-Ethernet or a
zero-copy receive path if network overhead becomes significant.

## Important performance boundary

The onboard PHY is 10/100 Mbps. 100 Mbps is 12.5 MB/s theoretical line rate,
with lower application throughput after Ethernet/IP/TCP overhead. The compute
array can therefore be faster than the network for large tensors. The intended
usage is to keep weights/models resident when possible and send only required
input/output tensors rather than retransmitting the whole model for every job.

## Pin-safety / board-revision note

The Ethernet XDC mapping is checked against known EBAZ4205 reference designs:
U14 RXCLK, U15 TXCLK, W15 MDC, Y14 MDIO, W16 RXDV, RXD[0..3]
Y16/V16/V17/Y17, TXEN W19, and TXD[0..3] W18/Y18/V18/Y19.

The physical bus is 4-bit MII even though the Zynq EMIO ports are named GMII;
therefore Linux `phy-mode` is `mii`.

EBAZ4205 hardware revisions differ around the PHY crystal Y3. The default
build assumes the crystal/oscillator is fitted and does NOT drive U18.

For the cost-reduced/no-Y3 board, the reference design routes FPGA U18 to
IP101GA pin 47 (XOUT) through R1485. R1485 must be populated as a 0-ohm link
(bridged). The build then enables PS FCLK1 at 25 MHz and constrains that output
to U18. The no-Y3 profile is deliberately guarded:

    CONFIRM_R1485_BRIDGED=1 ./scripts/build_ebaz4205_no_y3.sh

Only set CONFIRM_R1485_BRIDGED=1 after verifying the R1485 link on the board.
Do not enable the PL clock when a fitted Y3 oscillator is already driving the
PHY reference input. The profile still requires a valid EBAZ4205 PS7 DDR/MIO
board preset before implementation/bitstream generation.

## MatMul/Dense bias over the network

Add an optional `bias` array of N signed INT32 values to the MatMul JSON:

```json
{"A":[[1,2],[3,4]], "B":[[5,6],[7,8]], "bias":[1,-2]}
```

The host automatically sets the MatMul-bias capability flag and inserts two
128-bit bias beats before each 8x8 output tile. Old JSON without `bias` remains
byte-compatible with the no-bias stream.

## Benchmark / diagnostics

The host runtime supports persistent TCP sessions, so repeated jobs do not pay a
new TCP connect/teardown cost. After the board self-test passes, measure both
end-to-end and hardware-cycle performance with:

```sh
python3 sw/host/npu_benchmark.py 192.168.50.2 --m 64 --n 64 --k 64 --runs 30 --bias
```

The tool prints best/median/p95 network latency, effective end-to-end GOPS and
the hardware `LAST_JOB_CYCLES` converted using the configured FCLK (100 MHz by
default). Treat peak GOPS as measured only after timing/bitstream/board tests.


## REVIEW50 completeness boundary

The no-Y3 clock profile is a build option, not proof of board wiring: R1485
must physically connect U18 to the PHY reference input. The active NPU system
uses the streaming Conv MAC path with host-side NHWC window expansion. The
separate memory-address Conv2D scheduler RTL is not reachable from the production
`npu_bd_top` hierarchy in REVIEW50.
