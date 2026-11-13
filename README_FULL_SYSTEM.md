> **Historical integration overview.** The canonical current release is `README.md` + `docs/FINAL_MAXED_RELEASE.md`; later v2 additions include IRQ/abort/performance telemetry, Conv bias, grouped/depthwise stream packing, hardware MaxPool and Add, streamed MatMul/Dense bias, strict model tooling, and a 28-test Vivado suite.

# Sam NPU Full System

Added on top of `Sam_NPU_CURRENT`:

- real AXI4-Lite slave wrapper
- AXI-Stream MatMul feeder
- AXI-Stream output serializer
- AXI-Stream Conv packet adapter
- hardware Conv2D geometry scheduler
- hardware Conv2D address generator
- Conv memory-side request/response engine
- Vitis bare-metal AXI DMA runtime example
- MatMul stream packer
- Conv stream packer
- Vivado Zynq + AXI DMA block-design skeleton

This is now a much more complete **system integration package**, but it is not claimed to be bitstream-verified.

The only intentionally unresolved hardware-specific item is the exact EBAZ4205 PS7 DDR/MIO configuration. Do not guess those settings; use a known-good EBAZ4205 PS project/configuration.
