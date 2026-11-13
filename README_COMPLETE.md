> **Historical integration overview.** The canonical current release is `README.md` + `docs/FINAL_MAXED_RELEASE.md`; later v2 additions include IRQ/abort/performance telemetry, Conv bias, grouped/depthwise stream packing, hardware MaxPool and Add, streamed MatMul/Dense bias, strict model tooling, and a 28-test Vivado suite.

# Sam NPU — Complete Integrated Source Package

This package combines:
- tensor compute core
- MatMul/Dense
- Conv2D streaming and hardware-scheduled paths
- parallel Conv2D-to-systolic frontend
- quantization/post-processing
- memory buffering blocks
- AXI4-Lite control
- AXI-Stream DMA path
- Cortex-A9 bare-metal example
- Linux UIO control example
- custom model package/loader tooling
- Vivado block-design skeleton

## Important
"Complete source package" does not mean "hardware verified".

Before calling the accelerator finished on EBAZ4205, run:
1. Vivado compile/elaboration
2. all behavioral simulations
3. synthesis
4. utilization review
5. timing closure
6. known-good EBAZ4205 PS7/DDR preset
7. AXI DMA loopback test
8. MatMul hardware-vs-golden test
9. Conv2D hardware-vs-golden test


## Additional verification/integration tooling

Added:
- `scripts/run_vivado_verification.tcl`
- `scripts/build_bitstream_if_bd_ready.tcl`
- `sw/generate_selftest_vectors.py`
- `sw/perf_estimator.py`
- `sw/onnx_to_snpu.py`
- Linux DMAengine proxy driver and test utility

The package now contains scripts for the steps that require Vivado/board access,
but does not fabricate their results.

## Network NPU mode

EBAZ4205 Ethernet/GEM0 integration and a TCP accelerator runtime are included.
See `docs/ETHERNET_NPU.md`. The intended external link is Ethernet; internally,
Linux moves request payloads through the existing AXI DMA <-> AXI-Stream NPU path.
