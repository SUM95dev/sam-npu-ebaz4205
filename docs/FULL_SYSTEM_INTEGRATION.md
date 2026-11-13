# Full-system integration

This package now contains two practical integration paths.

## Path A — Recommended first hardware path: AXI DMA + AXI Stream

PS DDR3 -> AXI DMA MM2S -> `npu_axis_system_top` -> AXI DMA S2MM -> PS DDR3

Control:
Cortex-A9 -> AXI GP0 -> AXI-Lite -> `npu_axis_system_top`

MatMul input stream beat (default N=8):
- bytes 0..7   = A edge vector
- bytes 8..15  = B edge vector
- feed beats per output tile = K + N - 1
- software packer: `sw/pack_matmul_stream.py`

MatMul output:
- signed INT8 values serialized as sign-extended 32-bit AXI Stream words
- only valid lanes of partial edge tiles are emitted

Conv streaming input:
- bits 7:0 = activation INT8
- bits 15:8 = weight INT8
- bit 16 of TDATA = final MAC sample for one output
- AXI TLAST = final beat of the entire Conv job
- software packer: `sw/pack_conv_stream.py`
- this path is easy to bring up, but software performs the spatial window packing.

## Path B — Hardware Conv2D scheduler

`conv2d_scheduler.v` + `conv2d_addrgen.v` + `conv2d_memory_top.v`

This path generates NHWC input addresses and O-H-W-I weight addresses in hardware.
It exposes request/response memory ports. Those ports can be connected to:
- an AXI master adapter
- BRAM caches
- a DMA/data mover

This is the hardware scheduler path; unlike the stream packer, the ARM does not need to create every convolution sample pair.

## What is still board-specific

Zynq PS7 DDR setup is not safely guessable from generic EBAZ4205 naming alone.
The exact PS7 DDR parameters, clocks, and MIO configuration must come from a known-good EBAZ4205 PS configuration/project.

The project therefore includes the reusable NPU and AXI/stream integration RTL but does not invent DDR electrical parameters.

## Bias

MatMul `bias_flat` is currently a local wide bus intended to come from BRAM.
For first bring-up use zero bias or preload a BRAM from PS/DMA.
A later optimization can make the shared postprocessor fetch one bias per lane from BRAM.

## Verification boundary

The source has static/model review but must still pass:
1. Vivado xvlog/xelab/xsim
2. synthesis
3. timing
4. board DDR/DMA test
