# Third independent 15-pass review (cumulative 45 passes)

This review operated on the actual `Sam_NPU_CURRENT` source tree.

## New fixes found in these 15 passes
1. **Conv configuration stability**: `conv2d_stream_engine` now latches bias, ReLU, quantization multiplier/shift and zero-point on accepted START. The first sample may still arrive on the START cycle.
2. **Postprocess multiplier sizing**: removed a pre-multiply sign extension that described a 65-bit multiplicand. The intended arithmetic is now expressed as a true 33-bit biased accumulator multiplied by a 32-bit quantization multiplier, producing a 65-bit result.
3. **Sticky configuration error semantics**: `CONFIG_ERROR_STICKY` is no longer cleared by partial M/N/K writes; it clears only on reset or a valid new START.
4. Added `tb_conv_config_latch.v` and strengthened `tb_regs_invalid_start.v`.
5. Canonical Vivado project name/manifest were synchronized with the current package.

## 15 review angles
1. RTL lexical/module structure
2. named-port hierarchy consistency
3. PE signed multiply/accumulate widths
4. systolic forwarding and zero flush
5. feeder request/valid stall contract
6. controller counter widths and K upper bound
7. M/N partial-tile masking
8. postprocess add/multiply/shift/saturation widths
9. Conv START/first-sample timing
10. Conv configuration stability during a job
11. register START lock and sticky status semantics
12. double-buffer state ordering review
13. standalone MaxPool/performance-counter review
14. testbench/interface consistency
15. package/TCL/manifest and integration-scope audit

## Checks executed in this environment
- existing Python numerical golden model: PASS
- existing cycle-model audit: PASS (1000 random matrix shapes)
- additional postprocess arithmetic stress: PASS (200,000 random cases)
- additional boundary/counter-width audit: PASS (5,000 random configurations)
- custom named-port/lexical structural audit: 0 issues found

## Tool-level limitation
No Verilog simulator or Vivado executable is available in this runtime, so xsim compile/elaboration/simulation and synthesis are **not** claimed here. Those remain the next decisive checks.

## Scope notes, not RTL errors
- Conv is currently a streamed dot-product primitive, not a complete spatial Conv2D window/address/channel scheduler.
- MaxPool, double-buffer control and performance counters exist as standalone modules but are not wired into `npu_v4_top`.
- PS7 DDR/AXI/DMA integration is not part of this core yet.
