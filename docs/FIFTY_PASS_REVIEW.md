# 50-pass review summary

This review was performed on the actual Sam_NPU_COMPLETE_PLUS source tree.

## Major issues found and corrected

1. Added the missing `shared_postprocess` module referenced by the parallel Conv path.
2. Fixed AXI4-Lite read timing so read data is captured after the requested register address is active.
3. Added AXI write-strobe propagation and byte-aware register updates.
4. Added MatMul output backpressure (`valid/ready`) so output tiles cannot be dropped while the DMA-side serializer is busy.
5. Made the tile serializer snapshot tile payload/mask before serial transmission.
6. Fixed serializer end-of-transfer handling so AXI `TLAST` is asserted only on the final valid lane of the final MatMul tile.
7. Reworked streaming Conv framing: bit 16 marks the final MAC sample for one output, while AXI `TLAST` marks the end of the whole Conv job.
8. Added a continuous Conv stream job engine with output backpressure and multi-output support.
9. Fixed the memory-side Conv request contract with request-pending flags to prevent duplicate reads.
10. Latched the Conv output address before the scheduler advances and added a finishing latch so final `done` is not lost before write-back.
11. Added divide-by-zero and invalid-geometry guards to the Conv scheduler.
12. Replaced the earlier parallel Conv systolic timing path with an on-the-fly Conv-to-GEMM feeder that reuses `matmul_engine`, inheriting its tiling, flush and output-backpressure behavior.
13. Fixed Conv GEMM feeder data/valid alignment so `feed_valid` is asserted only while the corresponding held A/B vectors are already visible.
14. Moved the superseded legacy parallel Conv frontend out of the default RTL source tree.
15. Added regression testbenches for AXI/output backpressure, multi-output Conv jobs and invalid Conv geometry.

## Automated audit result

`docs/FIFTY_PASS_AUDIT.json`: **50 / 50 checks passed**.

The checks include structural/lexical audits, named-port consistency, Python compilation, numerical golden tests, 1000 randomized systolic cycle cases, randomized MatMul stream framing, arithmetic-width checks, AXI handshake invariants, Conv geometry guards, Linux userspace C syntax checks, Vivado script consistency and ZIP CRC integrity.

## Verification boundary

No HDL compiler/simulator or Vivado installation is available in the review environment. Therefore this review does **not** claim successful `xvlog/xelab/xsim`, synthesis, timing closure, bitstream generation or EBAZ4205 hardware execution. Those are the next authoritative validation stages.
