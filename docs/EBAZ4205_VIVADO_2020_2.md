# EBAZ4205 Vivado 2020.2 setup

Do not manually guess DDR timing.

Two public reference routes exist for EBAZ4205:
1. DavidJRichards/EBAZ4205_BoardSupport — board definition for Vivado 2020.2 with a PS preset (`preset.xml`) intended to configure memory and PS devices.
2. Halolo/ebaz4205-vivado — a Vivado 2020.2 demo project containing processing-system configuration for the board.

Recommended:
- install/inspect one known-good 2020.2 board preset,
- create the PS7 block,
- apply the board preset,
- enable GP0 for NPU control and HP0 for DMA,
- connect AXI DMA to DDR through HP0,
- connect NPU AXI-Lite to GP0,
- connect DMA MM2S/S2MM streams to `npu_axis_system_top`.

Then validate the block design before bitstream generation.
