# Sam NPU — Ten-Pass Review

This package is the result of five earlier review passes plus five additional independent passes.

## Additional pass 6 — sequencing / race review
- Rechecked controller nonblocking-assignment semantics and feed handshake.
- Rechecked array clear/feed/flush ordering.
- Identified an architectural resource problem: 64 parallel requant multipliers were not realistic for XC7Z010.

## Additional pass 7 — reset/start/resource realism
- Replaced 64 per-lane postprocess blocks with one shared `tile_postprocess` engine.
- MatMul controller now waits for postprocessing before exposing `out_tile_valid` or clearing the accumulators for the next tile.
- This keeps one programmable requant multiplier instead of 64 copies.

## Additional pass 8 — widths and boundary arithmetic
- Rechecked 17-bit feed counters for K up to 65535.
- Rechecked ceil tile-count arithmetic using widened intermediate values.
- Reworked the requant multiplication description so a 65-bit result is retained without intentionally describing a 65x65 multiply.
- INT32 accumulation bound for signed INT8 and K<=65535 remains safe: max absolute positive bound is 1,073,725,440.

## Additional pass 9 — elaboration / Vivado integration review
- Updated controller testbenches for the new `post_start/post_done` interface.
- Updated project name in the Tcl script.
- Added a named-port audit across RTL and simulation files: 0 unknown/omitted named-port issues found.

## Additional pass 10 — coverage / end-to-end review
- Added `tb_tile_postprocess.v`.
- Added `tb_npu_top_2x2.v`, covering register programming -> START -> stalled feeder -> systolic array -> shared postprocess -> output -> DONE -> sticky status.
- Re-ran an independent cycle-level mathematical model across N=1/2/4/8 and multiple K values: 560 randomized cases, 0 failures.
- Re-ran lexical balance checks on all RTL and testbenches: 0 mismatches.

## Important remaining validation
No Verilog simulator (xsim/iverilog/verilator) is available in the generation environment. Therefore these reviews do not replace Vivado elaboration and behavioral simulation.

The next required validation is:
1. Create project with `scripts/create_vivado_project.tcl`.
2. Run all behavioral testbenches in Vivado 2020.2.
3. Synthesize `npu_v4_top` for the exact EBAZ4205 speed grade.
4. Inspect DSP/LUT/FF/BRAM and timing reports.

## Scope reminder
The current Conv block is a streaming dot-product/Conv compute primitive. Full image-window address generation, channel/kernel scheduling, and DDR/AXI integration are intentionally not claimed as complete in this package.
