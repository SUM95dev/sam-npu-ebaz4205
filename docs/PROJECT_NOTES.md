# Sam NPU for EBAZ4205 (Zynq-7010)

INT8 8x8 systolic-array NPU in Verilog, with host/Linux/PYNQ software and Vivado 2020.2 build scripts.
Written with ChatGPT, reviewed/fixed with Claude, and run on a real EBAZ4205 board.

## Status (hardware-verified, see [docs/PYNQ_BRINGUP.md](docs/PYNQ_BRINGUP.md))
- Routed timing met in Vivado 2020.2: setup WNS +0.593 ns, hold WHS +0.019 ns (bitstream built).
- On a real board (PYNQ 2.4): self-test, MatMul/Conv comparisons against a soft reference and an independent
  numpy model, a 300-job stress run and a digit-recognition demo (117/120 correct, outputs bit-identical to the
  reference) all passed.
- Not verified: long-duration stability, real FCLK frequency (100 MHz assumed in GOPS numbers), Ethernet on the
  board (no eth0 with the stock PYNQ image), large/real models (the ONNX converter is incomplete).
- Measured: ~5.8 GOPS hardware throughput on a 64x128x64 MatMul (100 MHz assumed); the Python server is ~150x slower end to end.

Everything below is the original project README (REVIEW50 text) and predates the hardware tests above.

---

# Sam NPU — REVIEW50 candidate

Read [REVIEW50.md](REVIEW50.md) first for this revision. Its 50 directed host checks and the existing 55 RTL regressions passed. No fresh Vivado timing or physical-board acceptance is claimed.

This revision changes host networking software and verification relative to DEEP_REVIEW. Keep a running older build intact until its logs can be reviewed.

- [DEEP_REVIEW.md](DEEP_REVIEW.md): preceding RTL/DMA/BD changes and hardware acceptance requirements.
- [README_FULL_SYSTEM.md](README_FULL_SYSTEM.md): system overview; historical details must be checked against current source.
- Build: `bash scripts/build_ebaz4205_final.sh`
- Host checks: `python3 verification/review50/run_50_checks.py`
- Full static/software gate: `bash scripts/validate_release.sh`

Older audit reports are historical evidence for their named versions, not a substitute for a new routed implementation and board test.


## Direct network Conv2D helper (host lowers spatial windows)

The host client now exposes `NpuSession.conv_nhwc(...)` and a `conv` CLI
subcommand. Input tensors are NHWC and weights are OHWI; the host creates the
streaming MAC sequence while the FPGA performs the INT8 dot products and
post-processing. This is not a claim that the unused legacy memory-address
Conv2D scheduler is integrated into the production datapath. Example JSON:

```json
{
  "input": [[[1], [2]], [[3], [4]]],
  "weights": [[[[2]]]],
  "stride": 1,
  "pad": 0,
  "groups": 1,
  "bias": [0]
}
```

Run with `python3 sw/host/npu_net_client.py 192.168.50.2 conv conv.json`.
