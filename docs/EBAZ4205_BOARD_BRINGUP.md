# EBAZ4205 board integration — Sam NPU

## Architecture

```text
Cortex-A9 / Linux or bare metal
        |
      GP0 AXI
        |
   AXI control interconnect
      /              \
 NPU S_AXI_CTRL    AXI DMA S_AXI_LITE

DDR3 <-> PS7 <-> S_AXI_HP0 <-> AXI memory interconnect
                                  ^              ^
                                  |              |
                           DMA M_AXI_MM2S   DMA M_AXI_S2MM
                                  |              ^
                                  v              |
                            128-bit AXIS     32-bit AXIS
                                  |              ^
                                  v              |
                              Sam NPU -----------+
```

First bring-up runs the complete PL data path at PS `FCLK_CLK0 = 100 MHz`.

## One-command BD creation

From the project root:

```bash
/home/sum/Xilinx/Vivado/2020.2/bin/vivado \
  -mode batch \
  -source scripts/build_ebaz4205_system.tcl \
  | tee ebaz_bd.log
```

This creates `vivado_ebaz4205/`, adds all RTL, creates `npu_system`, connects PS7, GP0, HP0, AXI DMA, clocks/resets, NPU control and streams, assigns addresses, validates the BD, and generates a wrapper.

## If EBAZ board files are installed

The script searches for a board part containing `ebaz4205`. You can force the exact board part:

```bash
EBAZ_BOARD_PART='vendor:board:name:version' \
/home/sum/Xilinx/Vivado/2020.2/bin/vivado \
  -mode batch -source scripts/build_ebaz4205_system.tcl
```

Use a known-good EBAZ4205 Vivado 2020.2 board preset. The script intentionally does not invent DDR timings or MIO settings.

## Synthesis of the whole PS+DMA+NPU system

After the correct board preset is present:

```bash
RUN_SYNTH=1 /home/sum/Xilinx/Vivado/2020.2/bin/vivado \
  -mode batch -source scripts/build_ebaz4205_system.tcl \
  | tee ebaz_synth.log
```

Reports are written to `reports_ebaz/`.

## Implementation + bitstream

Only after the EBAZ4205 PS7/DDR preset is confirmed:

```bash
EBAZ_BOARD_PART='vendor:board:name:version' RUN_SYNTH=1 RUN_IMPL=1 \
/home/sum/Xilinx/Vivado/2020.2/bin/vivado \
  -mode batch -source scripts/build_ebaz4205_system.tcl \
  | tee ebaz_impl.log
```

The flow refuses `RUN_IMPL=1` when no board part was confirmed. That is intentional: wrong DDR/MIO settings can make a generated bitstream useless or unsafe to rely on.

## First hardware test

1. Use the generated Vitis `xparameters.h` addresses; do not assume a hard-coded AXI address.
2. Run AXI DMA loopback/sanity first.
3. Run a tiny 2x2 MatMul with zero bias and identity quantization.
4. Compare output against `sw/golden_model.py` / self-test vectors.
5. Then test 8x8, partial tiles, and Conv stream jobs.

## Current bias path

The BD wrapper ties `bias_flat` to zero for first hardware bring-up. This avoids exposing a 2048-bit bias bus in IP Integrator. After the basic DMA path is proven, bias should be moved into a BRAM-backed bias buffer accessed by the shared postprocessor.

## Ethernet clock profile for the no-Y3 revision

If Y3 is not populated, the IP101GA needs the 25 MHz reference clock from the
Zynq PL. The board reference design connects FPGA U18 to IP101GA pin 47 via
R1485; R1485 must be bridged. After confirming that physical link, use:

```bash
CONFIRM_R1485_BRIDGED=1 ./scripts/build_ebaz4205_no_y3.sh
```

This profile sets `EBAZ_PHY_CLOCK_FROM_PL=1`, enabling PS FCLK1 at 25 MHz and
constraining it to U18. It does not bypass the normal PS7 DDR/MIO preset gate.
Do not use this profile on a board where Y3 is populated and driving the PHY.
