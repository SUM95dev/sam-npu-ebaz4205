# Independent review of Sam_NPU_EBAZ4205_REVIEW50 (by Claude) — report for ChatGPT

Scope: read all 29 RTL files, server/driver/client C+Python, Vivado Tcl/XDC. Executed: `scripts/validate_release.sh` (passes on REVIEW51, now including 9 new runtime tests in verification/review51), plus two independent Python models:
(a) cycle-level model of systolic_array/npu_pe + controller feed/flush driven by `pack_matmul_stream.make_feed` (300 random shapes, 0 mismatches);
(b) bit-exact model of npu_postprocess_pipe split multiply vs reference requant (400k random/edge cases, 0 mismatches).
NOT executed (not available in my sandbox): Icarus/XSim (the 55 RTL tests), Vivado, tclsh. RTL conclusions are from reading + models only. Nothing here is board-verified.

## Findings and status in REVIEW51

| # | Finding | Status |
|---|---|---|
| 1 | AXI DMA: `c_m_axis_mm2s_tdata_width=128` but `c_m_axi_mm2s_data_width` left at default 32. Stream width must not exceed memory-map width (PG021). | FIXED in create_ebaz4205_full_bd.tcl and create_zynq_dma_bd.tcl (MM2S mm width 128, S2MM mm width 64). Needs Vivado confirmation. |
| 2 | `PCW_ENET0_PERIPHERAL_FREQMHZ` not set (PS7 default 1000 Mbps; board is 4-bit MII 100 Mbps). | FIXED (set to `100 Mbps`, wrapped in catch with WARNING). Check the generated PS7 config. |
| 3 | Bare-metal macro `XPAR_NPU_AXIS_SYSTEM_TOP_0_S_AXI_BASEADDR` does not exist in the BD (instance is `npu_0`). | FIXED: probes XPAR_NPU_0_S_AXI_CTRL_BASEADDR, XPAR_NPU_0_BASEADDR, old name, else #error. Confirm real name from xparameters.h. |
| 4 | `create_vivado_project.tcl` set top to legacy `npu_v4_top`. | FIXED (npu_axis_system_top). |
| 5 | START/config writes while BUSY are silently ignored (no error flag); stale sticky DONE can end the next wait immediately. | MITIGATED in npu_net_server.c: abort if busy, then ack DONE/ERROR before programming. RTL unchanged (see open items). |
| 6 | Server has no authentication, binds 0.0.0.0. | MITIGATED: optional 4th arg = bind IP. |
| 7 | `.snpu` v2 has no per-layer qmul/qshift/zero_point/relu and Add has no second operand reference. | FIXED: format v3 (docs/MODEL_FORMAT.md) in model_packer.py, snpu_inspect.py, snpu_loader.py; v2 behaviour unchanged. |
| 8 | No runtime executed a .snpu model. | FIXED (host level): sw/host/npu_runtime.py (net + bit-exact soft backends), tested end-to-end against sw/host/npu_emulator.py (a protocol server that runs raw DMA streams through a cycle-level model of the array; my own model, not the RTL). |
| 9 | Conv used 1 MAC/cycle and never the 8x8 array. | FIXED without RTL change: host im2col -> MatMul op (per group), `auto` picks the cheaper path by estimated cycles; stream and matmul paths verified bit-identical (incl. grouped/depthwise/stride/pad, chunking) and equal to golden_model.conv2d_grouped. |

## Open items (NOT done — need work + verification)

1. Runtime/Conv-on-array are done only at host level and verified against my emulator, never on RTL or hardware. The Conv-via-MatMul path transfers im2col data (K x larger than the image) over DMA; an in-PL im2col (integrating conv2d_systolic_engine) would still be faster and needs RTL work + tests.
2. Standalone ReLU is host-side max(x,0) (no zero-point awareness); the runtime assumes NHWC and per-tensor quantization.
3. ONNX converter: Add has no operand tracking; v3 `src`/quant fields not emitted; activations are NCHW in ONNX but runtime is NHWC. Not changed (onnx not installed here, cannot test). Models must currently be built from JSON.
4. Requant uses floor (>>>) not round-to-nearest: matches golden_model.py but differs from TFLite/ONNX Runtime by up to 1 LSB. Only per-tensor qmul/shift/zp; no per-channel, no input zero-point.
5. RTL quirks left unchanged on purpose (changing them could break the 55-test gate which I could not run): CMD(0x14) write with bit0=0 clears irq_en; AXI-Lite addresses alias above 64 B (no DECERR); START-while-busy not flagged in error_count.
6. Axis tile output emits one beat per 2 cycles; 32-bit beat per INT8 result; no double buffering (double_buffer_ctrl unused). Performance only.
7. Static audit scripts (five_pass_source_audit.py etc.) mostly check text presence; they are not behavioural evidence.
8. Hardware acceptance still required: fresh Vivado route (last routed run had WNS -18.791 ns; synth showed 72/80 DSP), DRC, MII I/O delays, DMA/Ethernet selftest on board.

## Questions for ChatGPT
1. Which exact RTL snapshot produced the synth report (LUT 4243, DSP 72, WNS +2.414)? Provide a routed `timing_impl.rpt`/`utilization_impl.rpt` for REVIEW50/51.
2. Confirm in Vivado 2020.2: does `validate_bd_design` accept the DMA widths now set? Paste the IP customization log.
3. Confirm the generated PS7 ENET0 speed and GEM clock configuration with the EBAZ4205 board preset.
4. Run the 55-test XSim/Icarus gate on REVIEW51 (RTL is byte-identical to REVIEW50; only Tcl/C/Python/docs changed) and paste the logs.
